import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PairingEngine Commit-then-Reveal & Zero-PIN-on-Wire (T1.3 / §5)', () {
    late Directory tempDir;
    late TrustedDeviceStore trustedStore;
    late DeviceIdentity hostId;
    const nowMs = 1711800000000;
    const fpLo =
        '0000000000000000000000000000000000000000000000000000000000000000';
    const fpHi =
        '1111111111111111111111111111111111111111111111111111111111111111';
    final nonceA = Uint8List.fromList(utf8.encode('0123456789abcdef'));
    final nonceB = Uint8List.fromList(utf8.encode('fedcba9876543210'));

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dc_pair_test_');
      trustedStore = TrustedDeviceStore(
          storageDir: tempDir, keyStore: InMemorySecureKeyStore());
      hostId = DeviceIdentity(
          deviceId: '11111111-1111-4111-8111-111111111111',
          name: 'Jay-Mac',
          os: 'macos',
          certDer: Uint8List(8),
          certPem: Uint8List(8),
          fp: fpLo,
          createdAt: nowMs);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('QR Mode (337017), PIN Mode (639589), Zero-PIN & 3-strike lockout',
        () async {
      final engine = PairingEngine(
          hostIdentity: hostId,
          trustedStore: trustedStore,
          clockMs: () => nowMs);
      final s = engine.startSession(
          hostIp: '192.168.1.10', hostPort: 53318, nonceAOverride: nonceA);
      final parsedQr = QrPairingPayload.fromJson(s.qr.toJson());
      expect(parsedQr.isExpired(nowMs), isFalse);
      final commitB = SasCalculator.createCommitment(nonceB, fpHi);
      final r1 = engine.handlePairRequest(<String, dynamic>{
        'v': 1,
        'min_supported_v': 1,
        'device_id': '22222222-2222-4222-8222-222222222222',
        'name': 'Pixel-8',
        'os': 'android',
        'tier': 2,
        'fp': fpHi,
        'mode': 'qr',
        'qr_nonce': parsedQr.nonce,
        'commitment_B': commitB
      }, clientIp: '192.168.1.20', tlsClientCertFp: fpHi);
      engine.handlePairConfirm(<String, dynamic>{
        'pair_id': r1['pair_id'],
        'nonce_B': base64Encode(nonceB)
      }, clientIp: '192.168.1.20');
      expect(engine.currentSasCode, '337017');
      await engine.handlePairFinalize(
          <String, dynamic>{'pair_id': r1['pair_id'], 'result': 'match'},
          clientIp: '192.168.1.20', hostUserConfirmedMatch: true);
      expect(trustedStore.isActiveFingerprint(fpHi), isTrue);
      engine.startSession(
          hostIp: '192.168.1.10',
          hostPort: 53318,
          nonceAOverride: nonceA,
          pinOverride: '123456');
      final rPin = engine.handlePairRequest(<String, dynamic>{
        'device_id': '33333333-3333-4333-8333-333333333333',
        'name': 'iPhone-15',
        'os': 'ios',
        'tier': 3,
        'fp': fpHi,
        'mode': 'pin',
        'commitment_B': commitB
      }, clientIp: '192.168.1.30', tlsClientCertFp: fpHi);
      engine.handlePairConfirm(<String, dynamic>{
        'pair_id': rPin['pair_id'],
        'nonce_B': base64Encode(nonceB)
      }, clientIp: '192.168.1.30');
      expect(engine.currentSasCode, '639589');
      for (var i = 0; i < 3; i++) {
        expect(
            () => engine.handlePairRequest(<String, dynamic>{'pin': '123456'},
                clientIp: '10.0.0.5', tlsClientCertFp: fpHi),
            throwsA(isA<ProtocolException>()));
      }
      expect(
          () => engine.handlePairRequest(<String, dynamic>{},
              clientIp: '10.0.0.5', tlsClientCertFp: fpHi),
          throwsA(isA<ProtocolException>().having(
              (e) => e.errorCode, 'errorCode', ProtocolErrorCode.pairLocked)));
    });
  });
}
