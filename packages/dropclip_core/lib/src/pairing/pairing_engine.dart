import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../../dropclip_core.dart';

/// QR Code JSON payload (`E-03` / PROTO-DC-V2.0 §5.3).
class QrPairingPayload {
  final String t, id, ip, fp, nonce;
  final int v, port, exp;

  const QrPairingPayload(
      {this.t = 'dropclip-pair',
      this.v = 1,
      required this.id,
      required this.ip,
      required this.port,
      required this.fp,
      required this.nonce,
      required this.exp});

  bool isExpired(int nowMs) => nowMs > exp;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': t,
        'v': v,
        'id': id,
        'ip': ip,
        'port': port,
        'fp': fp,
        'nonce': nonce,
        'exp': exp
      };

  factory QrPairingPayload.fromJson(Map<String, dynamic> j) {
    final t = j['t'] as String?;
    final fp = (j['fp'] as String? ?? '').toLowerCase();
    final nonce = j['nonce'] as String? ?? '';
    if (t != 'dropclip-pair' ||
        fp.length != 64 ||
        base64Decode(nonce).length != 16) {
      throw const ProtocolException(
          ProtocolErrorCode.pairingInvalid, 'Invalid QR pairing payload');
    }
    return QrPairingPayload(
        t: t!,
        v: (j['v'] as int?) ?? 1,
        id: j['id'] as String,
        ip: j['ip'] as String,
        port: j['port'] as int,
        fp: fp,
        nonce: nonce,
        exp: j['exp'] as int);
  }
}

/// Pairing state machine states (PROTO-DC-V2.0 §5.2).
enum PairingState { idle, open, committed, awaitingSas, paired, failed }

/// Host-side Commit-then-Reveal SAS & Zero-PIN-on-Wire Pairing Engine (§5, §9.2, T1.3).
class PairingEngine {
  static const int pairNonceTtlMs = 60000, pairConfirmTimeoutMs = 120000;
  static const int pairRateLimitPerIp = 5, pairMaxFailures = 3;
  static const int pairLockoutDurationMs = 300000;
  final DeviceIdentity hostIdentity;
  final int hostTier;
  final TrustedDeviceStore trustedStore;
  final int Function() _clockMs;
  PairingState _state = PairingState.idle;
  String? _pairId, _pin, _mode, _commitmentB, _currentSasCode;
  String? _clientDeviceId, _clientName, _clientOs, _clientFp;
  Uint8List? _nonceA, _clientCertPem;
  int _expMs = 0, _committedAtMs = 0, _clientTier = 1;
  final Map<String, List<int>> _reqStampsByIp = <String, List<int>>{};
  final Map<String, int> _failuresByIp = <String, int>{};
  final Map<String, int> _lockoutUntilByIp = <String, int>{};

  PairingEngine(
      {required this.hostIdentity,
      required this.trustedStore,
      this.hostTier = 1,
      int Function()? clockMs})
      : _clockMs = clockMs ?? (() => DateTime.now().millisecondsSinceEpoch);
  PairingState get state => _state;
  String? get currentSasCode => _currentSasCode;
  String? get currentPin => _pin;

  ({QrPairingPayload qr, String pin, Uint8List nonceA}) startSession(
      {required String hostIp,
      required int hostPort,
      Uint8List? nonceAOverride,
      String? pinOverride}) {
    final rng = Random.secure();
    final nonceA = nonceAOverride ??
        Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
    final pin = pinOverride ?? rng.nextInt(1000000).toString().padLeft(6, '0');
    final now = _clockMs();
    _state = PairingState.open;
    _pairId = _randomId(rng);
    _nonceA = Uint8List.fromList(nonceA);
    _pin = pin;
    _expMs = now + pairNonceTtlMs;
    _currentSasCode = null;
    final qr = QrPairingPayload(
        id: hostIdentity.deviceId,
        ip: hostIp,
        port: hostPort,
        fp: hostIdentity.fp,
        nonce: base64Encode(nonceA),
        exp: _expMs);
    return (qr: qr, pin: pin, nonceA: Uint8List.fromList(nonceA));
  }

  Map<String, dynamic> handlePairRequest(Map<String, dynamic> body,
      {required String clientIp,
      required String tlsClientCertFp,
      Uint8List? tlsClientCertPem}) {
    final now = _clockMs();
    _enforceLockoutAndRateLimit(clientIp, now);
    if (body.containsKey('pin') ||
        body.containsKey('pin_nonce') ||
        body.containsKey('pin_hash')) {
      _fail(clientIp, now, ProtocolErrorCode.pairingInvalid, 'PIN on wire');
    }
    VersionNegotiator.negotiate(
        remoteV: (body['v'] as int?) ?? ProtocolConstants.protocolVersion,
        remoteMinV: (body['min_supported_v'] as int?) ??
            ProtocolConstants.minSupportedProtocolVersion);
    if (_state != PairingState.open || now > _expMs) {
      _state = PairingState.failed;
      throw const ProtocolException(
          ProtocolErrorCode.nonceExpired, 'Session expired');
    }
    final claimedFp = (body['fp'] as String? ?? '').toLowerCase();
    final commitmentB = (body['commitment_B'] as String? ?? '').toLowerCase();
    final mode = (body['method'] ?? body['mode']) as String? ?? '';
    if (claimedFp.length != 64 ||
        claimedFp != tlsClientCertFp.toLowerCase() ||
        commitmentB.length != 64 ||
        (mode != 'qr' && mode != 'pin')) {
      _fail(clientIp, now, ProtocolErrorCode.pairingInvalid, 'Invalid request');
    }
    if (mode == 'qr' && body.containsKey('qr_nonce')) {
      final Uint8List qrNonce;
      try {
        qrNonce = base64Decode(body['qr_nonce'] as String? ?? '');
      } on FormatException {
        _fail(clientIp, now, ProtocolErrorCode.pairingInvalid, 'Bad qr_nonce');
      }
      if (!_constantTimeEquals(qrNonce, _nonceA!)) {
        _fail(
            clientIp, now, ProtocolErrorCode.pairingInvalid, 'Nonce mismatch');
      }
    }
    _mode = mode;
    _commitmentB = commitmentB;
    _clientDeviceId = body['device_id'] as String;
    _clientName = body['name'] as String;
    _clientOs = body['os'] as String;
    _clientTier = (body['tier'] as int?) ?? 1;
    _clientFp = claimedFp;
    _clientCertPem = tlsClientCertPem;
    _committedAtMs = now;
    _state = PairingState.committed;
    return <String, dynamic>{
      'status': 'awaiting_reveal',
      'v': ProtocolConstants.protocolVersion,
      'pair_id': _pairId,
      'host_id': hostIdentity.deviceId,
      'host_name': hostIdentity.name,
      'host_os': hostIdentity.os,
      'host_tier': hostTier,
      'host_fp': hostIdentity.fp,
      'nonce_A': base64Encode(_nonceA!)
    };
  }

  Map<String, dynamic> handlePairConfirm(Map<String, dynamic> body,
      {required String clientIp}) {
    final now = _clockMs();
    _enforceLockoutAndRateLimit(clientIp, now);
    _checkSessionActive(body['pair_id'], PairingState.committed, now);
    final Uint8List nonceB;
    try {
      nonceB = base64Decode(body['nonce_B'] as String? ?? '');
    } on FormatException {
      _fail(clientIp, now, ProtocolErrorCode.pairingInvalid, 'Bad nonce_B');
    }
    if (nonceB.length != 16 ||
        !SasCalculator.verifyCommitment(_commitmentB!, nonceB, _clientFp!)) {
      _state = PairingState.failed;
      _fail(clientIp, now, ProtocolErrorCode.pairingInvalid, 'Bad commitment');
    }
    _currentSasCode = _mode == 'qr'
        ? SasCalculator.calculateSasDual(
            hostIdentity.fp, _clientFp!, _nonceA!, nonceB)
        : SasCalculator.calculateSasPinMode(
            hostIdentity.fp, _clientFp!, _nonceA!, nonceB, _pin!);
    _state = PairingState.awaitingSas;
    return <String, dynamic>{'status': 'awaiting_sas', 'pair_id': _pairId};
  }

  Future<Map<String, dynamic>> handlePairFinalize(Map<String, dynamic> body,
      {required String clientIp, required bool hostUserConfirmedMatch}) async {
    final now = _clockMs();
    _enforceLockoutAndRateLimit(clientIp, now);
    _checkSessionActive(body['pair_id'], PairingState.awaitingSas, now);
    if (body['result'] != 'match' || !hostUserConfirmedMatch) {
      _state = PairingState.failed;
      _fail(clientIp, now, ProtocolErrorCode.sasFailed, 'SAS rejected');
    }
    await trustedStore.upsert(TrustedDevice(
        deviceId: _clientDeviceId!,
        name: _clientName!,
        os: _clientOs!,
        tier: _clientTier,
        fp: _clientFp!,
        certPem: _clientCertPem,
        pairedAt: now,
        lastSeenAt: now));
    _failuresByIp.remove(clientIp);
    _state = PairingState.paired;
    return <String, dynamic>{'status': 'paired', 'paired_at': now};
  }

  void _checkSessionActive(Object? pairId, PairingState expected, int now) {
    if (_state != expected || pairId != _pairId) {
      throw const ProtocolException(
          ProtocolErrorCode.pairingInvalid, 'Invalid pairing session state');
    }
    if (now - _committedAtMs > pairConfirmTimeoutMs) {
      _state = PairingState.failed;
      throw const ProtocolException(
          ProtocolErrorCode.nonceExpired, 'Confirm window expired');
    }
  }

  void _enforceLockoutAndRateLimit(String ip, int nowMs) {
    final lockedUntil = _lockoutUntilByIp[ip];
    if (lockedUntil != null) {
      if (nowMs < lockedUntil) {
        throw const ProtocolException(
            ProtocolErrorCode.pairLocked, 'Pairing locked for 5 minutes');
      }
      _lockoutUntilByIp.remove(ip);
      _failuresByIp.remove(ip);
    }
    final stamps = (_reqStampsByIp[ip] ??= <int>[])
      ..removeWhere((t) => nowMs - t >= 60000);
    if (stamps.length >= pairRateLimitPerIp) {
      throw const ProtocolException(
          ProtocolErrorCode.rateLimited, 'Max 5 pairing req/min/IP');
    }
    stamps.add(nowMs);
  }

  Never _fail(String ip, int nowMs, ProtocolErrorCode code, String msg) {
    final count = (_failuresByIp[ip] ?? 0) + 1;
    _failuresByIp[ip] = count;
    if (count >= pairMaxFailures) {
      _lockoutUntilByIp[ip] = nowMs + pairLockoutDurationMs;
    }
    throw ProtocolException(code, msg);
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _randomId(Random rng) =>
      List<int>.generate(16, (_) => rng.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
}
