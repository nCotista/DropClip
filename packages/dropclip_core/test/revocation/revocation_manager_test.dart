import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('RevocationManager Cluster Revocation & Anti-Entropy (T1.13 / §13)',
      () {
    late Directory dirA, dirB, dirC;
    late DeviceIdentityManager idA, idB, idC;
    late TrustedDeviceStore storeA, storeB, storeC;
    const nowMs = 1711800000000;

    Future<void> trust(TrustedDeviceStore s, DeviceIdentity p) =>
        s.upsert(TrustedDevice(
            deviceId: p.deviceId,
            name: p.name,
            os: p.os,
            tier: 1,
            fp: p.fp,
            certPem: p.certPem,
            pairedAt: nowMs,
            lastSeenAt: nowMs));

    setUp(() async {
      dirA = await Directory.systemTemp.createTemp('dc_rev_a_');
      dirB = await Directory.systemTemp.createTemp('dc_rev_b_');
      dirC = await Directory.systemTemp.createTemp('dc_rev_c_');
      idA = DeviceIdentityManager(
          storageDir: dirA, keyStore: InMemorySecureKeyStore());
      idB = DeviceIdentityManager(
          storageDir: dirB, keyStore: InMemorySecureKeyStore());
      idC = DeviceIdentityManager(
          storageDir: dirC, keyStore: InMemorySecureKeyStore());
      final a = await idA.loadOrCreate(
          deviceName: 'Node-A',
          os: 'macos',
          deviceId: '11111111-1111-4111-8111-111111111111');
      final b = await idB.loadOrCreate(
          deviceName: 'Node-B',
          os: 'windows',
          deviceId: '22222222-2222-4222-8222-222222222222');
      final c = await idC.loadOrCreate(
          deviceName: 'Node-C',
          os: 'android',
          deviceId: '33333333-3333-4333-8333-333333333333');
      storeA = TrustedDeviceStore(storageDir: dirA, keyStore: idA.keyStore);
      storeB = TrustedDeviceStore(storageDir: dirB, keyStore: idB.keyStore);
      storeC = TrustedDeviceStore(storageDir: dirC, keyStore: idC.keyStore);
      await trust(storeA, b);
      await trust(storeA, c);
      await trust(storeB, a);
      await trust(storeB, c);
      await trust(storeC, a);
      await trust(storeC, b);
    });

    tearDown(() async {
      for (final d in <Directory>[dirA, dirB, dirC]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });

    test(
        'Local revoke (<1s), cluster quarantine (<2s), No-Self-Revoke & Anti-Entropy',
        () async {
      final closedOnA = <String, int>{};
      final revA = RevocationManager(
          identityManager: idA,
          trustedStore: storeA,
          storageDir: dirA,
          disconnectPeer: (peer, code) async => closedOnA[peer] = code,
          clockMs: () => nowMs);
      final revB = RevocationManager(
          identityManager: idB,
          trustedStore: storeB,
          storageDir: dirB,
          clockMs: () => nowMs);
      final revC = RevocationManager(
          identityManager: idC,
          trustedStore: storeC,
          storageDir: dirC,
          clockMs: () => nowMs);
      final sw = Stopwatch()..start();
      final token = await revA.revokePeerLocally(idC.identity.deviceId);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(storeA.isActiveFingerprint(idC.identity.fp), isFalse);
      expect(closedOnA[idC.identity.deviceId], 4004);
      expect(await revC.onClusterRevocation(token), isFalse);
      expect(storeC.isActiveFingerprint(idA.identity.fp), isTrue);
      expect(await revB.onClusterRevocation(token), isTrue);
      expect(storeB.isActiveFingerprint(idC.identity.fp), isFalse);
      expect(await revB.rejectQuarantinedRevocation(idC.identity.deviceId),
          isTrue);
      expect(storeB.isActiveFingerprint(idC.identity.fp), isTrue);
      expect(storeB.isActiveFingerprint(idA.identity.fp), isFalse);
      await storeB.setStatus(idA.identity.deviceId, 'active');
      final revB2 = RevocationManager(
          identityManager: idB,
          trustedStore: storeB,
          storageDir: dirB,
          clockMs: () => nowMs);
      expect(await revB2.applySyncPayload(revA.buildSyncPayload()), 1);
      expect(await revB2.confirmQuarantinedRevocation(idC.identity.deviceId),
          isTrue);
      expect(storeB.getByDeviceId(idC.identity.deviceId), isNull);
    });
  });
}
