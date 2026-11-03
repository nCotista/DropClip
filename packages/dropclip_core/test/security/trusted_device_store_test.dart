import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('TrustedDeviceStore (T1.2 / E-02 / §15.3)', () {
    late Directory tempDir;
    late InMemorySecureKeyStore keyStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dc_trust_store_');
      keyStore = InMemorySecureKeyStore();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('Persists encrypted records, hides plaintext, and reloads on restart',
        () async {
      final store1 =
          TrustedDeviceStore(storageDir: tempDir, keyStore: keyStore);
      await store1.load();
      expect(store1.allDevices, isEmpty);

      final peer = TrustedDevice(
        deviceId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        name: 'Jay-Pixel-8',
        os: 'android',
        tier: 2,
        fp: 'ab' * 32,
        certPem: Uint8List.fromList(utf8.encode('CERT-PEM-BYTES')),
        pairedAt: 1711800000000,
        lastSeenAt: 1711800005000,
      );
      await store1.upsert(peer);

      final encFile = File('${tempDir.path}/$kTrustedDevicesFileName');
      expect(await encFile.exists(), isTrue);
      final rawOnDisk = await encFile.readAsBytes();
      expect(
        utf8.decode(rawOnDisk, allowMalformed: true),
        isNot(contains('Jay-Pixel-8')),
      );

      final store2 =
          TrustedDeviceStore(storageDir: tempDir, keyStore: keyStore);
      await store2.load();
      expect(store2.activeDevices.length, 1);
      expect(store2.fingerprintOf(peer.deviceId), peer.fp);
      expect(store2.isActiveFingerprint(peer.fp), isTrue);
      expect(store2.getByDeviceId(peer.deviceId)?.name, 'Jay-Pixel-8');
    });

    test('Quarantine status & removal immediately revoke active lookup',
        () async {
      final store = TrustedDeviceStore(storageDir: tempDir, keyStore: keyStore);
      final peer = TrustedDevice(
        deviceId: '11111111-2222-4333-8444-555555555555',
        name: 'Windows-PC',
        os: 'windows',
        tier: 1,
        fp: 'cd' * 32,
        pairedAt: 1711800000000,
        lastSeenAt: 1711800000000,
      );
      await store.upsert(peer);

      expect(await store.setStatus(peer.deviceId, 'quarantined'), isTrue);
      expect(store.isActiveFingerprint(peer.fp), isFalse);
      expect(store.fingerprintOf(peer.deviceId), isNull);
      expect(store.allDevices.length, 1);

      expect(await store.removeByFingerprint(peer.fp), isTrue);
      expect(store.allDevices, isEmpty);
      expect(await store.removeByDeviceId('non-existent'), isFalse);
    });

    test('Rejects tampered authentication tag and truncated envelope',
        () async {
      final store = TrustedDeviceStore(storageDir: tempDir, keyStore: keyStore);
      await store.upsert(
        TrustedDevice(
          deviceId: '99999999-2222-4333-8444-555555555555',
          name: 'Tamper-Peer',
          os: 'macos',
          tier: 1,
          fp: 'ef' * 32,
          pairedAt: 1,
          lastSeenAt: 1,
        ),
      );

      final encFile = File('${tempDir.path}/$kTrustedDevicesFileName');
      final bytes = await encFile.readAsBytes();
      bytes[bytes.length - 1] ^= 0xff;
      await encFile.writeAsBytes(bytes, flush: true);

      final reloader =
          TrustedDeviceStore(storageDir: tempDir, keyStore: keyStore);
      await expectLater(reloader.load(), throwsFormatException);

      await encFile.writeAsBytes(Uint8List(10), flush: true);
      await expectLater(reloader.load(), throwsFormatException);
    });
  });
}
