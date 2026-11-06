import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'sas.dart';

/// Client-side proof for the three pairing requests in Protocol Spec §5.4.
/// Network transport and trusted-device persistence remain the caller's job.
class PairingClientProof {
  PairingClientProof._(
    this._method,
    this._clientFp,
    this._pin,
    this._qrHostFp,
    this._qrNonce,
    this._qrExpiryMs,
    this._nowMs,
  ) : _nonceB = _newNonce();

  static final _fingerprint = RegExp(r'^[0-9a-f]{64}$');
  static final _pinPattern = RegExp(r'^\d{6}$');

  static Uint8List _newNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
  }

  final String _method, _clientFp;
  final String? _pin, _qrHostFp;
  final Uint8List? _qrNonce;
  final int? _qrExpiryMs;
  final int Function() _nowMs;
  final Uint8List _nonceB;
  Uint8List? _nonceA;
  String? _hostFp, _pairId;
  bool _started = false, _finished = false;

  /// [qr] must come from the scanned visual channel, never an HTTP response.
  factory PairingClientProof.fromQr({
    required Map<String, dynamic> qr,
    required String clientFingerprint,
    int Function()? nowMs,
  }) {
    final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
    if (qr['t'] != 'dropclip-pair' || qr['v'] != 1) {
      throw ArgumentError('Invalid QR pairing type or version');
    }
    final hostFp = _validFingerprint(qr['fp']);
    final nonce = _decodeNonce(qr['nonce']);
    final expiry = qr['exp'];
    if (expiry is! int || clock() >= expiry) {
      throw ArgumentError('QR pairing session expired');
    }
    return PairingClientProof._(
      'qr',
      _validFingerprint(clientFingerprint),
      null,
      hostFp,
      nonce,
      expiry,
      clock,
    );
  }

  factory PairingClientProof.forPin({
    required String pin,
    required String clientFingerprint,
  }) {
    final localPin = pin.trim();
    if (!_pinPattern.hasMatch(localPin)) {
      throw ArgumentError('PIN must be six digits');
    }
    return PairingClientProof._(
      'pin',
      _validFingerprint(clientFingerprint),
      localPin,
      null,
      null,
      null,
      () => DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Call before receiving the Host nonce. The PIN never enters this payload.
  Map<String, String> begin() {
    if (_started || _finished) throw StateError('Pairing already started');
    _started = true;
    return {
      'fp': _clientFp,
      'commitment_B': SasCalculator.createCommitment(_nonceB, _clientFp),
      'method': _method,
    };
  }

  /// Pins the Host response to its TLS certificate, then reveals nonce_B.
  Map<String, String> acceptHostReveal({
    required String pairId,
    required String tlsServerFingerprint,
    required String responseFingerprint,
    required String responseNonceA,
  }) {
    if (!_started || _finished || _nonceA != null) {
      throw StateError('Unexpected Host reveal');
    }
    try {
      final tlsFp = _validFingerprint(tlsServerFingerprint);
      final responseFp = _validFingerprint(responseFingerprint);
      final nonceA = _decodeNonce(responseNonceA);
      if (pairId.isEmpty || tlsFp != responseFp) {
        throw ArgumentError('Host identity mismatch');
      }
      if (_method == 'qr' &&
          (_nowMs() >= _qrExpiryMs! ||
              tlsFp != _qrHostFp ||
              !_sameBytes(nonceA, _qrNonce!))) {
        throw ArgumentError('Host response differs from visual QR');
      }
      _hostFp = tlsFp;
      _nonceA = nonceA;
      _pairId = pairId;
      return {'pair_id': pairId, 'nonce_B': base64Encode(_nonceB)};
    } catch (_) {
      _finished = true;
      rethrow;
    }
  }

  /// Show this locally so the user can compare it on both devices.
  String get sas {
    if (_nonceA == null || _finished) throw StateError('SAS unavailable');
    return _method == 'qr'
        ? SasCalculator.calculateSasDual(_hostFp!, _clientFp, _nonceA!, _nonceB)
        : SasCalculator.calculateSasPinMode(
            _hostFp!,
            _clientFp,
            _nonceA!,
            _nonceB,
            _pin!,
          );
  }

  /// Only an explicit user comparison may provide [userConfirmedMatch].
  Map<String, String> finalize({required bool userConfirmedMatch}) {
    if (_nonceA == null || _finished) throw StateError('SAS unavailable');
    _finished = true;
    return {
      'pair_id': _pairId!,
      'result': userConfirmedMatch ? 'match' : 'mismatch',
    };
  }

  static String _validFingerprint(Object? value) {
    if (value is! String ||
        !_fingerprint.hasMatch(value.toLowerCase().trim())) {
      throw ArgumentError('Fingerprint must be 64 hex characters');
    }
    return value.toLowerCase().trim();
  }

  static Uint8List _decodeNonce(Object? value) {
    if (value is! String) throw ArgumentError('Nonce must be base64');
    try {
      final bytes = base64Decode(value);
      if (bytes.length == 16) return bytes;
    } on FormatException {
      // Use one error type for malformed and wrong-length nonce input.
    }
    throw ArgumentError('Nonce must decode to 16 bytes');
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
