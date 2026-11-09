import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../../dropclip_core.dart';

/// File name for persistent revocation tombstones (§13.2.6 & §15.1).
const String kRevokedTombstonesFileName = 'revoked_tombstones.json';

/// Persistent revocation tombstone entry (§13.2.6).
class RevocationTombstone {
  final RevocationBroadcastToken token;
  final String status;
  final int recordedAt;

  const RevocationTombstone(
      {required this.token, required this.status, required this.recordedAt});

  RevocationTombstone copyWith({String? status}) => RevocationTombstone(
      token: token, status: status ?? this.status, recordedAt: recordedAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'token': token.toJson(),
        'status': status,
        'recorded_at': recordedAt
      };

  factory RevocationTombstone.fromJson(Map<String, dynamic> j) =>
      RevocationTombstone(
          token: RevocationBroadcastToken.fromJson(
              j['token'] as Map<String, dynamic>),
          status: (j['status'] as String?) ?? 'confirmed',
          recordedAt: j['recorded_at'] as int);
}

/// Manages local $<1\text{s}$ revocation, ECDSA-signed `cluster.revocation` gossip,
/// No-Self-Revocation-by-Proxy, Quarantine-then-Confirm, and Tombstone Anti-Entropy (§13, T1.13).
class RevocationManager {
  static const int maxTokenAgeMs = 86400000, maxSeenCacheSize = 200;
  final DeviceIdentityManager identityManager;
  final TrustedDeviceStore trustedStore;
  final Directory storageDir;
  final Future<void> Function(String peerId, Envelope frame)? sendFrame;
  final Future<void> Function(String peerId, int wsCloseCode)? disconnectPeer;
  final Future<void> Function(Envelope frame, {String? excludePeerId})?
      broadcastCluster;
  final int Function() _clockMs;
  final Map<String, RevocationTombstone> _tombstonesByRevokedId =
      <String, RevocationTombstone>{};
  final LinkedHashSet<String> _seenTokens = LinkedHashSet<String>();

  RevocationManager(
      {required this.identityManager,
      required this.trustedStore,
      required this.storageDir,
      this.sendFrame,
      this.disconnectPeer,
      this.broadcastCluster,
      int Function()? clockMs})
      : _clockMs = clockMs ?? (() => DateTime.now().millisecondsSinceEpoch);
  List<RevocationTombstone> get tombstones =>
      List<RevocationTombstone>.unmodifiable(_tombstonesByRevokedId.values);
  int get tombstoneCount => _tombstonesByRevokedId.length;
  bool isTombstoned(String id) => _tombstonesByRevokedId.containsKey(id);

  /// Deterministic 64-char SHA-256 hex digest of all stored tombstones for `hello` (§7.4.1).
  String get tombstonesHash {
    final keys = _tombstonesByRevokedId.keys.toList()..sort();
    final canonical = keys
        .map((k) => _tombstonesByRevokedId[k]!.token.signingInput)
        .join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<void> load() async {
    await storageDir.create(recursive: true);
    final file = File('${storageDir.path}/$kRevokedTombstonesFileName');
    if (!await file.exists()) {
      _tombstonesByRevokedId.clear();
      return;
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final list = raw['tombstones'] as List<dynamic>? ?? const <dynamic>[];
    _tombstonesByRevokedId.clear();
    for (final item in list) {
      final ts = RevocationTombstone.fromJson(item as Map<String, dynamic>);
      _tombstonesByRevokedId[ts.token.revokedId] = ts;
    }
  }

  /// Local Revocation (§13.1): Revokes [targetDeviceId] in $<1.0\text{ s}$, closes sockets (`4004`),
  /// signs `RevocationBroadcastToken`, persists tombstone, and broadcasts `cluster.revocation`.
  Future<RevocationBroadcastToken> revokePeerLocally(String targetDeviceId,
      {String reason = 'user_initiated'}) async {
    final now = _clockMs();
    final targetFp =
        trustedStore.getByDeviceId(targetDeviceId)?.fp ?? ('0' * 64);
    await trustedStore.removeByDeviceId(targetDeviceId);

    if (sendFrame != null) {
      final directFrame = _buildEnvelope(
          MessageType.deviceRevoked, now, <String, dynamic>{
        'reason': reason,
        'by': identityManager.identity.deviceId
      });
      try {
        await sendFrame!(targetDeviceId, directFrame)
            .timeout(const Duration(milliseconds: 200));
      } on Object {
        // Best-effort per §13.1; never delay revocation beyond 200ms
      }
    }
    if (disconnectPeer != null) {
      await disconnectPeer!(
          targetDeviceId, VersionNegotiator.wsCloseNotPairedOrRevoked);
    }

    final myId = identityManager.identity.deviceId;
    final unsigned = RevocationBroadcastToken(
        revokerId: myId,
        revokedId: targetDeviceId,
        revokedFp: targetFp,
        timestamp: now,
        signature: '');
    final sig = await identityManager.signUtf8(unsigned.signingInput);
    final token = RevocationBroadcastToken(
        revokerId: myId,
        revokedId: targetDeviceId,
        revokedFp: targetFp,
        timestamp: now,
        signature: sig);

    _recordSeen(token.signingInput);
    _tombstonesByRevokedId[targetDeviceId] =
        RevocationTombstone(token: token, status: 'confirmed', recordedAt: now);
    await _persistTombstones();

    if (broadcastCluster != null) {
      final bcast =
          _buildEnvelope(MessageType.clusterRevocation, now, token.toJson());
      await broadcastCluster!(bcast, excludePeerId: targetDeviceId);
    }
    return token;
  }

  /// Cluster Revocation Receiver (§13.2): Enforces No Self-Revocation by Proxy,
  /// verifies ECDSA P-256 signature, and applies Quarantine-then-Confirm.
  Future<bool> onClusterRevocation(RevocationBroadcastToken token,
      {String? senderPeerId}) async {
    final now = _clockMs();
    if (_seenTokens.contains(token.signingInput)) return false;
    if (token.revokedId == identityManager.identity.deviceId) return false;

    final existingTs = _tombstonesByRevokedId[token.revokedId];
    if (existingTs != null && existingTs.status == 'confirmed') return false;

    final revoker = trustedStore.getByDeviceId(token.revokerId);
    if (revoker == null ||
        revoker.status != 'active' ||
        revoker.certPem == null) {
      return false;
    }
    if ((now - token.timestamp).abs() > maxTokenAgeMs) return false;

    final validSig = await DeviceIdentityManager.verifyUtf8(
        canonicalInput: token.signingInput,
        signatureBase64: token.signature,
        certPem: revoker.certPem!);
    if (!validSig) return false;

    _recordSeen(token.signingInput);
    await trustedStore.setStatus(token.revokedId, 'quarantined');
    if (disconnectPeer != null) {
      await disconnectPeer!(
          token.revokedId, VersionNegotiator.wsCloseNotPairedOrRevoked);
    }
    _tombstonesByRevokedId[token.revokedId] = RevocationTombstone(
        token: token, status: 'quarantined', recordedAt: now);
    await _persistTombstones();

    if (broadcastCluster != null) {
      final bcast =
          _buildEnvelope(MessageType.clusterRevocation, now, token.toJson());
      await broadcastCluster!(bcast, excludePeerId: senderPeerId);
    }
    return true;
  }

  /// Local user confirms a quarantined revocation $\to$ permanently deletes peer from store.
  Future<bool> confirmQuarantinedRevocation(String revokedId) async {
    final ts = _tombstonesByRevokedId[revokedId];
    if (ts == null) return false;
    await trustedStore.removeByDeviceId(revokedId);
    _tombstonesByRevokedId[revokedId] = ts.copyWith(status: 'confirmed');
    await _persistTombstones();
    return true;
  }

  /// Local user rejects a quarantined revocation $\to$ restores victim & quarantines revoker (§13.2.4).
  Future<bool> rejectQuarantinedRevocation(String revokedId) async {
    final ts = _tombstonesByRevokedId.remove(revokedId);
    if (ts == null) return false;
    await trustedStore.setStatus(revokedId, 'active');
    await trustedStore.setStatus(ts.token.revokerId, 'quarantined');
    if (disconnectPeer != null) {
      await disconnectPeer!(
          ts.token.revokerId, VersionNegotiator.wsCloseNotPairedOrRevoked);
    }
    await _persistTombstones();
    return true;
  }

  /// Builds `revocation.sync` payload when `tombstones_hash` differs in `hello` (§13.2.6).
  Map<String, dynamic> buildSyncPayload() => <String, dynamic>{
        'tombstones_hash': tombstonesHash,
        'tombstone_count': tombstoneCount,
        'tokens':
            _tombstonesByRevokedId.values.map((t) => t.token.toJson()).toList()
      };

  /// Reconciles incoming `revocation.sync` tokens from a peer after reconnect (§13.2.6).
  Future<int> applySyncPayload(Map<String, dynamic> payload) async {
    final rawTokens = payload['tokens'] as List<dynamic>? ?? const <dynamic>[];
    var applied = 0;
    for (final item in rawTokens) {
      final token =
          RevocationBroadcastToken.fromJson(item as Map<String, dynamic>);
      if (await onClusterRevocation(token)) applied++;
    }
    return applied;
  }

  void _recordSeen(String key) {
    _seenTokens.remove(key);
    _seenTokens.add(key);
    while (_seenTokens.length > maxSeenCacheSize) {
      _seenTokens.remove(_seenTokens.first);
    }
  }

  Envelope _buildEnvelope(
      MessageType type, int nowMs, Map<String, dynamic> payload) {
    final myId = identityManager.identity.deviceId;
    return Envelope(
        type: type,
        msgId: _uuidV4(),
        origin: myId,
        hlc: Hlc(l: nowMs, c: 0, d: myId),
        ts: nowMs,
        payload: payload);
  }

  Future<void> _persistTombstones() async {
    await storageDir.create(recursive: true);
    final list = _tombstonesByRevokedId.values.map((t) => t.toJson()).toList();
    final json = jsonEncode(<String, dynamic>{
      'version': 1,
      'tombstones_hash': tombstonesHash,
      'tombstones': list
    });
    await File('${storageDir.path}/$kRevokedTombstonesFileName')
        .writeAsString(json, flush: true);
  }

  static String _uuidV4() {
    final r = Random.secure();
    String h(int n) => List<int>.generate(n, (_) => r.nextInt(16))
        .map((v) => v.toRadixString(16))
        .join();
    return '${h(8)}-${h(4)}-4${h(3)}-8${h(3)}-${h(12)}';
  }
}
