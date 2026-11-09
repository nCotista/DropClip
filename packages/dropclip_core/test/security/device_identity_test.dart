import 'dart:convert';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceIdentityManager & SecureKeyStore (T1.2 / E-01 / NFR-S02)', () {
    late Directory tempDir;
    late InMemorySecureKeyStore keyStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dc_identity_test_');
      keyStore = InMemorySecureKeyStore();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('Generates ECDSA P-256 identity on first run and reloads on restart',
        () async {
      final mgr1 =
          DeviceIdentityManager(storageDir: tempDir, keyStore: keyStore);
      final id1 =
          await mgr1.loadOrCreate(deviceName: 'Jay-MacBook', os: 'macos');

      expect(id1.version, 1);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id1.fp), isTrue);
      expect(id1.certDer, isNotEmpty);
      final mgr2 =
          DeviceIdentityManager(storageDir: tempDir, keyStore: keyStore);
      final id2 =
          await mgr2.loadOrCreate(deviceName: 'Ignored-On-Reload', os: 'macos');
      expect(id2.deviceId, id1.deviceId);
      expect(id2.fp, id1.fp);
      expect(id2.name, 'Jay-MacBook');
    });

    test('NFR-S02 Disk Audit: zero plaintext private keys in storageDir',
        () async {
      final mgr =
          DeviceIdentityManager(storageDir: tempDir, keyStore: keyStore);
      await mgr.loadOrCreate(deviceName: 'Audit-Node', os: 'macos');
      const forbiddenMarker = 'PRIVATE ' 'KEY';
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          final content = await entity.readAsString();
          expect(content.contains(forbiddenMarker), isFalse);
        }
      }
    });

    test('ECDSA P-256 signUtf8/verifyUtf8 & corrupted fingerprint rejection',
        () async {
      final mgr =
          DeviceIdentityManager(storageDir: tempDir, keyStore: keyStore);
      final id = await mgr.loadOrCreate(deviceName: 'Sign-Node', os: 'macos');
      const canonical =
          'dropclip-revoke-v1:11111111-1111-4111-8111-111111111111:'
          '22222222-2222-4222-8222-222222222222:1711800000000';
      final sig = await mgr.signUtf8(canonical);
      expect(
        await DeviceIdentityManager.verifyUtf8(
          canonicalInput: canonical,
          signatureBase64: sig,
          certPem: id.certPem,
        ),
        isTrue,
      );
      expect(
        await DeviceIdentityManager.verifyUtf8(
          canonicalInput: '${canonical}0',
          signatureBase64: sig,
          certPem: id.certPem,
        ),
        isFalse,
      );
      expect(
        await DeviceIdentityManager.verifyUtf8(
          canonicalInput: canonical,
          signatureBase64: '!!!not-base64!!!',
          certPem: id.certPem,
        ),
        isFalse,
      );

      final badJson = id.toJson()..['fp'] = '0' * 64;
      expect(() => DeviceIdentity.fromJson(badJson), throwsFormatException);

      await keyStore.delete(kIdentityKeyStoreKey);
      expect(await keyStore.read(kIdentityKeyStoreKey), isNull);
      expect(jsonEncode(id.toJson()), isNot(contains('PRIVATE')));
    });
  });
}
