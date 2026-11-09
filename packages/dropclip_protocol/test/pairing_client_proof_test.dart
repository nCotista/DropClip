import 'dart:convert';
import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  const hostFp =
      '0000000000000000000000000000000000000000000000000000000000000000';
  const clientFp =
      '1111111111111111111111111111111111111111111111111111111111111111';
  final nonceA = Uint8List.fromList(utf8.encode('0123456789abcdef'));
  final qr = <String, dynamic>{
    't': 'dropclip-pair',
    'v': 1,
    'fp': hostFp,
    'nonce': base64Encode(nonceA),
    'exp': 60000,
  };

  PairingClientProof newQr() => PairingClientProof.fromQr(
        qr: qr,
        clientFingerprint: clientFp,
        nowMs: () => 1000,
      );

  test('QR commitment precedes Host reveal and both sides calculate SAS', () {
    final client = newQr();
    final start = client.begin();
    expect(start.keys, unorderedEquals(['fp', 'commitment_B', 'method']));
    expect(start['method'], 'qr');
    expect(() => client.sas, throwsStateError);

    final confirm = client.acceptHostReveal(
      pairId: 'pair-1',
      tlsServerFingerprint: hostFp,
      responseFingerprint: hostFp,
      responseNonceA: base64Encode(nonceA),
    );
    final nonceB = Uint8List.fromList(base64Decode(confirm['nonce_B']!));
    expect(
      SasCalculator.verifyCommitment(start['commitment_B']!, nonceB, clientFp),
      isTrue,
    );
    expect(
      client.sas,
      SasCalculator.calculateSasDual(hostFp, clientFp, nonceA, nonceB),
    );
    expect(client.finalize(userConfirmedMatch: true), {
      'pair_id': 'pair-1',
      'result': 'match',
    });
  });

  test('PIN stays local and rejection produces mismatch request', () {
    final client = PairingClientProof.forPin(
      pin: '123456',
      clientFingerprint: clientFp,
    );
    final start = client.begin();
    expect(start['method'], 'pin');
    expect(start.keys, isNot(contains('pin')));
    expect(start.keys, isNot(contains('pin_hash')));

    final confirm = client.acceptHostReveal(
      pairId: 'pair-2',
      tlsServerFingerprint: hostFp,
      responseFingerprint: hostFp,
      responseNonceA: base64Encode(nonceA),
    );
    final nonceB = Uint8List.fromList(base64Decode(confirm['nonce_B']!));
    expect(confirm.keys, unorderedEquals(['pair_id', 'nonce_B']));
    expect(
      client.sas,
      SasCalculator.calculateSasPinMode(
        hostFp,
        clientFp,
        nonceA,
        nonceB,
        '123456',
      ),
    );
    expect(client.finalize(userConfirmedMatch: false)['result'], 'mismatch');
    expect(() => client.sas, throwsStateError);
  });

  test('expired, malformed, and short QR nonces are rejected', () {
    expect(
      () => PairingClientProof.fromQr(
        qr: {...qr, 'exp': 1000},
        clientFingerprint: clientFp,
        nowMs: () => 1000,
      ),
      throwsArgumentError,
    );
    for (final badNonce in [
      'not-base64!',
      base64Encode([1, 2]),
    ]) {
      expect(
        () => PairingClientProof.fromQr(
          qr: {...qr, 'nonce': badNonce},
          clientFingerprint: clientFp,
          nowMs: () => 1000,
        ),
        throwsArgumentError,
      );
    }
  });

  test('QR expiration between scan and Host response aborts pairing', () {
    var now = 1000;
    final client = PairingClientProof.fromQr(
      qr: qr,
      clientFingerprint: clientFp,
      nowMs: () => now,
    )..begin();
    now = 60000;
    expect(
      () => client.acceptHostReveal(
        pairId: 'pair-expired',
        tlsServerFingerprint: hostFp,
        responseFingerprint: hostFp,
        responseNonceA: base64Encode(nonceA),
      ),
      throwsArgumentError,
    );
    expect(() => client.finalize(userConfirmedMatch: true), throwsStateError);
  });

  test('QR Host fingerprint or nonce substitution aborts before reveal', () {
    for (final response in [
      (hostFp, clientFp, base64Encode(nonceA)),
      (clientFp, clientFp, base64Encode(nonceA)),
      (hostFp, hostFp, base64Encode(utf8.encode('fedcba9876543210'))),
    ]) {
      final client = newQr()..begin();
      expect(
        () => client.acceptHostReveal(
          pairId: 'pair-3',
          tlsServerFingerprint: response.$1,
          responseFingerprint: response.$2,
          responseNonceA: response.$3,
        ),
        throwsArgumentError,
      );
      expect(() => client.sas, throwsStateError);
      expect(() => client.finalize(userConfirmedMatch: true), throwsStateError);
    }
  });

  test('PIN response fingerprint must match the TLS certificate', () {
    final client = PairingClientProof.forPin(
      pin: '123456',
      clientFingerprint: clientFp,
    )..begin();
    expect(
      () => client.acceptHostReveal(
        pairId: 'pair-4',
        tlsServerFingerprint: hostFp,
        responseFingerprint: clientFp,
        responseNonceA: base64Encode(nonceA),
      ),
      throwsArgumentError,
    );
    expect(() => client.sas, throwsStateError);
  });

  test('out-of-order calls and invalid PIN cannot produce a match', () {
    final client = newQr();
    expect(() => client.finalize(userConfirmedMatch: true), throwsStateError);
    expect(
      () => client.acceptHostReveal(
        pairId: 'pair-5',
        tlsServerFingerprint: hostFp,
        responseFingerprint: hostFp,
        responseNonceA: base64Encode(nonceA),
      ),
      throwsStateError,
    );
    client.begin();
    expect(() => client.begin(), throwsStateError);
    expect(
      () =>
          PairingClientProof.forPin(pin: '12345x', clientFingerprint: clientFp),
      throwsArgumentError,
    );
  });
}
