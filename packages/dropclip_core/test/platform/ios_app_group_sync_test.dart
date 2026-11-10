import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late InMemorySecureKeyStore keyStore;
  late TrustedDeviceStore trustedStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dropclip_t3_2_test_');
    keyStore = InMemorySecureKeyStore();
    trustedStore = TrustedDeviceStore(storageDir: tempDir, keyStore: keyStore);
    await trustedStore.load();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('T3.2 iOS Share Extension App Group Sync & <30 MB Memory Guard', () {
    test(
      'publishes trusted peer to group.com.dropclip.shared and rejects untrusted peers',
      () async {
        const peerId = '550e8400-e29b-41d4-a716-446655440000';
        final peerFp = 'b' * 64;
        await trustedStore.upsert(
          TrustedDevice(
            deviceId: peerId,
            name: 'Mac Studio',
            os: 'macos',
            tier: 1,
            fp: peerFp,
            pairedAt: 1757280000000,
            lastSeenAt: 1757280000000,
          ),
        );

        final appGroup = IosAppGroupSync(
          containerDirectory: tempDir,
          trustedStore: trustedStore,
        );
        await appGroup.publishActivePeer(
          IosSharedPeerEndpoint(
            deviceId: peerId,
            name: 'Mac Studio',
            ip: '192.168.1.25',
            port: 53317,
            fingerprint: peerFp,
            updatedAtMs: 1757280005000,
          ),
        );

        final loaded = await appGroup.readActivePeer();
        expect(loaded, isNotNull);
        expect(loaded!.ip, equals('192.168.1.25'));
        expect(loaded.fingerprint, equals(peerFp));

        expect(
          () => appGroup.publishActivePeer(
            IosSharedPeerEndpoint(
              deviceId: '99999999-e29b-41d4-a716-446655440000',
              name: 'Rogue PC',
              ip: '192.168.1.99',
              port: 53317,
              fingerprint: 'c' * 64,
              updatedAtMs: 1757280005000,
            ),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'persists state.json HLC and formats X-DropClip-HLC header for /api/v1/clipboard',
      () async {
        final appGroup = IosAppGroupSync(
          containerDirectory: tempDir,
          trustedStore: trustedStore,
        );
        const iosId = '11111111-2222-4333-8444-555555555555';
        final header1 = await appGroup.nextHlcHeader(
          deviceId: iosId,
          nowMs: 1757280000100,
        );
        final header2 = await appGroup.nextHlcHeader(
          deviceId: iosId,
          nowMs: 1757280000100,
        );
        final parsed1 = Hlc.parse(header1);
        final parsed2 = Hlc.parse(header2);
        expect(parsed2.compareTo(parsed1), greaterThan(0));
        expect(parsed2.c, equals(parsed1.c + 1));
      },
    );

    test(
      'streams 4 GB video in 1 MiB chunks with Peak RAM strictly < 30 MB (NFR-R03B)',
      () {
        final guard = IosExtensionMemoryGuard();
        const fourGiB = 4 * 1024 * 1024 * 1024;
        final chunks = guard.simulateChunkedStream(totalBytes: fourGiB);

        expect(chunks, equals(4096));
        expect(guard.currentAllocatedBytes, equals(0));
        expect(
          guard.peakAllocatedBytes,
          equals(ProtocolConstants.fileChunkSize),
        );
        expect(
          guard.peakAllocatedBytes,
          lessThan(IosExtensionMemoryGuard.maxPeakRamBytes),
        );
        expect(
          () => guard.acquireBuffer(
            IosExtensionMemoryGuard.safeAllocationBudgetBytes + 1,
          ),
          throwsStateError,
        );
      },
    );
  });
}
