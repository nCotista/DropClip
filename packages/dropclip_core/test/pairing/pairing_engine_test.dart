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

    test('PairingClientProof and PairingEngine interoperate in QR mode',
        () async {
      final engine = PairingEngine(
          hostIdentity: hostId,
          trustedStore: trustedStore,
          clockMs: () => nowMs);
      final sQr = engine.startSession(hostIp: '192.168.1.10', hostPort: 53318);
      final clientQr = PairingClientProof.fromQr(
          qr: sQr.qr.toJson(), clientFingerprint: fpHi, nowMs: () => nowMs);
      final rQr = engine.handlePairRequest(<String, dynamic>{
        ...clientQr.begin(),
        'device_id': '22222222-2222-4222-8222-222222222222',
        'name': 'Pixel-8',
        'os': 'android',
        'tier': 2,
      }, clientIp: '192.168.1.25', tlsClientCertFp: fpHi);
      final confirmQr = clientQr.acceptHostReveal(
          pairId: rQr['pair_id'] as String,
          tlsServerFingerprint: hostId.fp,
          responseFingerprint: rQr['host_fp'] as String,
          responseNonceA: rQr['nonce_A'] as String);
      engine.handlePairConfirm(confirmQr, clientIp: '192.168.1.25');
      expect(clientQr.sas, equals(engine.currentSasCode));
      await engine.handlePairFinalize(
          clientQr.finalize(userConfirmedMatch: true),
          clientIp: '192.168.1.25',
          hostUserConfirmedMatch: true);
      expect(engine.state, PairingState.paired);
    });

    test('PIN client and host agree without putting the PIN in requests',
        () async {
      final engine =
          PairingEngine(hostIdentity: hostId, trustedStore: trustedStore);
      engine.startSession(
          hostIp: '192.168.1.10', hostPort: 53318, pinOverride: '123456');
      final client =
          PairingClientProof.forPin(pin: '123456', clientFingerprint: fpHi);
      final begin = <String, dynamic>{
        ...client.begin(),
        'device_id': '22222222-2222-4222-8222-222222222222',
        'name': 'Pixel-8',
        'os': 'android',
      };
      final reveal = engine.handlePairRequest(begin,
          clientIp: '192.168.1.20', tlsClientCertFp: fpHi);
      final confirm = client.acceptHostReveal(
          pairId: reveal['pair_id'] as String,
          tlsServerFingerprint: hostId.fp,
          responseFingerprint: reveal['host_fp'] as String,
          responseNonceA: reveal['nonce_A'] as String);
      engine.handlePairConfirm(confirm, clientIp: '192.168.1.20');
      expect(client.sas, engine.currentSasCode);
      final finalize = client.finalize(userConfirmedMatch: true);
      for (final request in [begin, confirm, finalize]) {
        expect(request.keys,
            isNot(contains(anyOf('pin', 'pin_hash', 'pin_nonce'))));
        expect(request.values, isNot(contains('123456')));
      }
      await engine.handlePairFinalize(finalize,
          clientIp: '192.168.1.20', hostUserConfirmedMatch: true);
      expect(trustedStore.isActiveFingerprint(fpHi), isTrue);
    });

    test('SAS mismatch leaves the client untrusted', () async {
      final engine =
          PairingEngine(hostIdentity: hostId, trustedStore: trustedStore);
      final session =
          engine.startSession(hostIp: '192.168.1.10', hostPort: 53318);
      final client = PairingClientProof.fromQr(
          qr: session.qr.toJson(), clientFingerprint: fpHi);
      final reveal = engine.handlePairRequest(<String, dynamic>{
        ...client.begin(),
        'device_id': '22222222-2222-4222-8222-222222222222',
        'name': 'Pixel-8',
        'os': 'android',
      }, clientIp: '192.168.1.20', tlsClientCertFp: fpHi);
      final confirm = client.acceptHostReveal(
          pairId: reveal['pair_id'] as String,
          tlsServerFingerprint: hostId.fp,
          responseFingerprint: reveal['host_fp'] as String,
          responseNonceA: reveal['nonce_A'] as String);
      engine.handlePairConfirm(confirm, clientIp: '192.168.1.20');
      await expectLater(
          engine.handlePairFinalize(client.finalize(userConfirmedMatch: false),
              clientIp: '192.168.1.20', hostUserConfirmedMatch: true),
          throwsA(isA<ProtocolException>().having(
              (e) => e.errorCode, 'errorCode', ProtocolErrorCode.sasFailed)));
      expect(engine.state, PairingState.failed);
      expect(trustedStore.isActiveFingerprint(fpHi), isFalse);
    });

    test('changed commitment rejects reveal without trusting the client',
        () async {
      final engine =
          PairingEngine(hostIdentity: hostId, trustedStore: trustedStore);
      final session =
          engine.startSession(hostIp: '192.168.1.10', hostPort: 53318);
      final client = PairingClientProof.fromQr(
          qr: session.qr.toJson(), clientFingerprint: fpHi);
      final begin = client.begin();
      final reveal = engine.handlePairRequest(<String, dynamic>{
        ...begin,
        'commitment_B': '0' * 64,
        'device_id': '22222222-2222-4222-8222-222222222222',
        'name': 'Pixel-8',
        'os': 'android',
      }, clientIp: '192.168.1.20', tlsClientCertFp: fpHi);
      final confirm = client.acceptHostReveal(
          pairId: reveal['pair_id'] as String,
          tlsServerFingerprint: hostId.fp,
          responseFingerprint: reveal['host_fp'] as String,
          responseNonceA: reveal['nonce_A'] as String);
      expect(
          () => engine.handlePairConfirm(confirm, clientIp: '192.168.1.20'),
          throwsA(isA<ProtocolException>().having((e) => e.errorCode,
              'errorCode', ProtocolErrorCode.pairingInvalid)));
      expect(engine.state, PairingState.failed);
      expect(trustedStore.isActiveFingerprint(fpHi), isFalse);
    });

    test('sixth pair request from one IP is rate limited', () {
      var now = nowMs;
      final engine = PairingEngine(
          hostIdentity: hostId, trustedStore: trustedStore, clockMs: () => now);
      Map<String, dynamic> request() => <String, dynamic>{
            'device_id': '22222222-2222-4222-8222-222222222222',
            'name': 'Pixel-8',
            'os': 'android',
            'fp': fpHi,
            'method': 'pin',
            'commitment_B': SasCalculator.createCommitment(nonceB, fpHi),
          };
      for (var i = 0; i < 5; i++) {
        engine.startSession(hostIp: '192.168.1.10', hostPort: 53318);
        engine.handlePairRequest(request(),
            clientIp: '192.168.1.20', tlsClientCertFp: fpHi);
      }
      engine.startSession(hostIp: '192.168.1.10', hostPort: 53318);
      expect(
          () => engine.handlePairRequest(request(),
              clientIp: '192.168.1.20', tlsClientCertFp: fpHi),
          throwsA(isA<ProtocolException>().having(
              (e) => e.errorCode, 'errorCode', ProtocolErrorCode.rateLimited)));
      now += 60000;
      engine.startSession(hostIp: '192.168.1.10', hostPort: 53318);
      expect(
          engine.handlePairRequest(request(),
              clientIp: '192.168.1.20', tlsClientCertFp: fpHi)['status'],
          'awaiting_reveal');
    });
  });
}
