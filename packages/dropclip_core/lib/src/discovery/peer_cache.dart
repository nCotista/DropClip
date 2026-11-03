import 'dart:async';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'txt_record.dart';

/// Peer lifecycle state (PROTO-DC-V2.0 §3.5, E-03). `removed` peers are
/// dropped from the cache rather than kept with a state.
enum PeerState { discovered, trustedOnline, connected, stale }

/// Client-side trust classification (PROTO-DC-V2.0 §3.4).
enum PeerTrust { trusted, untrusted, identityChanged }

/// Returns the pinned fingerprint for a trusted device id, or `null` when the
/// id is not in the Trusted Store.
typedef TrustedFingerprintLookup = String? Function(String deviceId);

/// A peer seen via mDNS.
class DiscoveredPeer {
  final DiscoveryRecord record;
  final String address;
  final DateTime lastSeen;
  final PeerState state;
  final PeerTrust trust;

  const DiscoveredPeer({
    required this.record,
    required this.address,
    required this.lastSeen,
    required this.state,
    required this.trust,
  });

  String get deviceId => record.deviceId;

  /// Only trusted peers with a matching fingerprint may auto-connect.
  bool get canAutoConnect => trust == PeerTrust.trusted;

  DiscoveredPeer copyWith({
    DiscoveryRecord? record,
    String? address,
    DateTime? lastSeen,
    PeerState? state,
    PeerTrust? trust,
  }) =>
      DiscoveredPeer(
        record: record ?? this.record,
        address: address ?? this.address,
        lastSeen: lastSeen ?? this.lastSeen,
        state: state ?? this.state,
        trust: trust ?? this.trust,
      );
}

/// Discovered Peer Cache keyed by `device_id` (T1.1, FR-01).
///
/// Time is injected through [now] so stale/remove timeouts are testable;
/// call [sweep] periodically (e.g. on every discovery query interval).
class PeerCache {
  final String localDeviceId;
  final TrustedFingerprintLookup trustedFingerprint;
  final DateTime Function() now;
  final Duration staleTimeout;
  final Duration removeTimeout;

  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _changes =
      StreamController.broadcast();

  PeerCache({
    required this.localDeviceId,
    required this.trustedFingerprint,
    DateTime Function()? now,
    this.staleTimeout = ProtocolConstants.deviceStaleTimeout,
    this.removeTimeout = ProtocolConstants.deviceRemoveTimeout,
  }) : now = now ?? DateTime.now;

  /// Emits a snapshot of all peers whenever the cache changes.
  Stream<List<DiscoveredPeer>> get changes => _changes.stream;

  List<DiscoveredPeer> get peers => List.unmodifiable(_peers.values);

  DiscoveredPeer? operator [](String deviceId) => _peers[deviceId];

  /// Records a resolved announcement. Returns `false` when it is dropped: our
  /// own record, or a TXT `port` that disagrees with the SRV port.
  bool onAnnouncement(DiscoveryRecord record, String address, {int? srvPort}) {
    if (record.deviceId == localDeviceId) return false;
    if (srvPort != null && srvPort != record.port) return false;

    final trust = _classify(record);
    final existing = _peers[record.deviceId];
    final state = _nextState(existing?.state, trust);

    // Same device_id with a new IP updates the entry in place (§3.3).
    _peers[record.deviceId] = DiscoveredPeer(
      record: record,
      address: address,
      lastSeen: now(),
      state: state,
      trust: trust,
    );
    _emit();
    return true;
  }

  /// Handles a goodbye packet (TTL = 0): the peer is removed immediately.
  void onGoodbye(String deviceId) {
    final peer = _peers[deviceId];
    if (peer == null || peer.state == PeerState.connected) return;
    _peers.remove(deviceId);
    _emit();
  }

  /// Marks a trusted peer connected after TLS + `hello` succeed.
  void markConnected(String deviceId) {
    final peer = _peers[deviceId];
    if (peer == null || peer.trust != PeerTrust.trusted) return;
    _update(peer.copyWith(state: PeerState.connected));
  }

  /// Returns a peer to `trustedOnline` when its WebSocket closes; liveness is
  /// measured from now since mDNS was ignored while connected.
  void markDisconnected(String deviceId) {
    final peer = _peers[deviceId];
    if (peer == null || peer.state != PeerState.connected) return;
    _update(peer.copyWith(state: PeerState.trustedOnline, lastSeen: now()));
  }

  /// Applies stale (30 s) and remove (120 s) timeouts. Connected peers are
  /// judged by WebSocket heartbeat, not mDNS (§3.5).
  void sweep() {
    final t = now();
    var changed = false;
    for (final peer in _peers.values.toList()) {
      if (peer.state == PeerState.connected) continue;
      final silence = t.difference(peer.lastSeen);
      if (silence > removeTimeout) {
        _peers.remove(peer.deviceId);
        changed = true;
      } else if (silence > staleTimeout && peer.state != PeerState.stale) {
        _peers[peer.deviceId] = peer.copyWith(state: PeerState.stale);
        changed = true;
      }
    }
    if (changed) _emit();
  }

  Future<void> dispose() => _changes.close();

  PeerTrust _classify(DiscoveryRecord record) {
    final pinned = trustedFingerprint(record.deviceId)?.toLowerCase();
    if (pinned == null) return PeerTrust.untrusted;
    return pinned == record.fingerprint
        ? PeerTrust.trusted
        : PeerTrust.identityChanged;
  }

  static PeerState _nextState(PeerState? current, PeerTrust trust) {
    if (trust != PeerTrust.trusted) return PeerState.discovered;
    if (current == PeerState.connected) return PeerState.connected;
    return PeerState.trustedOnline;
  }

  void _update(DiscoveredPeer peer) {
    _peers[peer.deviceId] = peer;
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(peers);
  }
}
