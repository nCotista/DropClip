import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  const nodeId = '11111111-1111-4111-8111-111111111111';
  const peerId = '22222222-2222-4222-8222-222222222222';

  group('Android Platform Extensions (T2.2, T2.3, T2.4)', () {
    test('T2.2 Quick Settings Tile requires PendingIntent on API 34+ & focus',
        () async {
      final gw = InMemoryAndroidNativeGateway();
      final bridge = AndroidServiceBridge(gateway: gw);
      await bridge.startService();

      final tile = AndroidQuickSettingsTileCoordinator(
        sdkInt: 34,
        serviceBridge: bridge,
        initialClock: Hlc(l: 1000, c: 0, d: nodeId),
      );

      await expectLater(
        tile.onTileTapped(
          usedPendingIntent: false,
          hasWindowFocus: true,
          isSensitive: false,
          clipboardText: 'hi',
          startedAtMs: 1000,
          focusedAtMs: 1120,
        ),
        throwsStateError,
      );

      final env = await tile.onTileTapped(
        usedPendingIntent: true,
        hasWindowFocus: true,
        isSensitive: false,
        clipboardText: 'Quick Settings Clip',
        startedAtMs: 1000,
        focusedAtMs: 1180,
      );
      expect(env, isNotNull);
      expect(tile.lastActionLatencyMs, lessThan(1500));

      final suppressed = await tile.onTileTapped(
        usedPendingIntent: true,
        hasWindowFocus: true,
        isSensitive: true,
        clipboardText: 'secret-otp',
        startedAtMs: 1200,
        focusedAtMs: 1250,
      );
      expect(suppressed, isNull);
      expect(bridge.suppressedSensitiveCount, equals(1));
    });

    test('T2.3 Inbound Clipboard Receiver applies LWW and suppresses echoes',
        () async {
      final gw = InMemoryAndroidNativeGateway();
      final bridge = AndroidServiceBridge(gateway: gw);
      final receiver = AndroidClipboardInboundReceiver(
        serviceBridge: bridge,
        initialClock: Hlc(l: 1000, c: 0, d: nodeId),
      );

      final raw = utf8.encode('Desktop copied text');
      final hash = sha256.convert(raw).toString();
      final payload = ClipboardUpdatePayload(
        contentType: 'text/plain',
        hash: hash,
        size: raw.length,
        inline: base64Encode(raw),
      );
      final env = Envelope(
        type: MessageType.clipboardUpdate,
        msgId: peerId,
        origin: peerId,
        hlc: Hlc(l: 2000, c: 0, d: peerId),
        ts: 2000,
        payload: payload.toJson(),
      );

      final applied =
          await receiver.onInboundClipboardEnvelope(env, nowMs: 2000);
      expect(applied, isTrue);
      expect(gw.primaryClip, equals('Desktop copied text'));
      expect(receiver.isEchoSuppressed(hash, 2500), isTrue);
      expect(receiver.isEchoSuppressed(hash, 3000), isFalse);

      // Older HLC is rejected by LWW
      final staleEnv = Envelope(
        type: MessageType.clipboardUpdate,
        msgId: nodeId,
        origin: peerId,
        hlc: Hlc(l: 1500, c: 0, d: peerId),
        ts: 1500,
        payload: payload.toJson(),
      );
      expect(
        await receiver.onInboundClipboardEnvelope(staleEnv, nowMs: 2100),
        isFalse,
      );
    });

    test('T2.4 AndroidMediaStoreEngine routes MIME types and verifies SHA-256',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('android_media_');
      try {
        final engine = AndroidMediaStoreEngine(scopedStorageRoot: tempDir);
        expect(
          AndroidMediaStoreEngine.collectionForMime('image/png'),
          equals(AndroidMediaCollection.images),
        );
        expect(
          AndroidMediaStoreEngine.collectionForMime('video/mp4'),
          equals(AndroidMediaCollection.videos),
        );
        expect(
          AndroidMediaStoreEngine.collectionForMime('application/pdf'),
          equals(AndroidMediaCollection.downloads),
        );

        final bytes = utf8.encode('sample-photo-bytes');
        final item = FileOfferItem(
          itemId: nodeId,
          path: 'photo.png',
          size: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          mime: 'image/png',
          modifiedAt: 1700000000000,
        );
        final saved = await engine.saveIncomingStream(
          item: item,
          byteStream: Stream<List<int>>.value(bytes),
        );
        expect(await saved.exists(), isTrue);
        expect(saved.path, contains('Pictures/DropClip/photo.png'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('iOS Platform Extensions (T3.3, T3.4)', () {
    test('T3.3 IosShortcutsWidgetCoordinator falls back on iOS 15/16',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ios_group_');
      try {
        final groupSync = IosAppGroupSync(containerDirectory: tempDir);
        final ios16 = IosShortcutsWidgetCoordinator(
          iosMajorVersion: 16,
          appGroupSync: groupSync,
          initialClock: Hlc(l: 1000, c: 0, d: nodeId),
        );
        expect(ios16.supportsInteractiveWidgetIntent, isFalse);
        expect(
          ios16.preferredTrigger(IosActionTrigger.interactiveWidget),
          equals(IosActionTrigger.shortcutsBackTapFallback),
        );

        final env = await ios16.triggerSendClipboard(
          pasteboardText: 'iOS Shortcut Clip',
          isConcealed: false,
          nowMs: 2000,
        );
        expect(env, isNotNull);
        final storedHlc = await groupSync.readCurrentHlc();
        expect(storedHlc?.l, equals(2000));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('T3.4 IosPhotoKitFileReceiver routes media to PhotoKit & Documents',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ios_photokit_');
      try {
        final receiver = IosPhotoKitFileReceiver(containerRoot: tempDir);
        final data = Uint8List.fromList(utf8.encode('heic-image-payload'));
        final item = FileOfferItem(
          itemId: peerId,
          path: 'IMG_0001.JPG',
          size: data.length,
          sha256: sha256.convert(data).toString(),
          mime: 'image/jpeg',
          modifiedAt: 1700000000000,
        );
        final saved = await receiver.receiveFileStream(
          item: item,
          chunks: Stream<Uint8List>.value(data),
        );
        expect(await saved.exists(), isTrue);
        expect(receiver.importedPhotoLibraryAssets, hasLength(1));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Phase 4 QA Verifiers (T4.1, T4.3, T4.4)', () {
    test('T4.1 BenchmarkRegressionVerifier passes all NFR thresholds', () {
      const verifier = BenchmarkRegressionVerifier();
      final report = verifier.evaluate();
      expect(report.passesAllThresholds, isTrue);
      expect(report.cryptoAndParserUsPerOp, lessThan(100.0));
    });

    test('T4.3 ChaosSoakVerifier passes 20x reconnects, partition & <=5% RSS',
        () async {
      const chaos = ChaosSoakVerifier();
      final summary = await chaos.runChaosAndSoakSuite(
        reconnectCycles: 20,
        baselineRssMb: 42.0,
        finalSoakRssMb: 43.2,
      );
      expect(summary.passed, isTrue);
      expect(summary.reconnectCyclesCompleted, equals(20));
      expect(summary.partitionHealedAndConverged, isTrue);
      expect(summary.soakRssGrowthPercent, lessThanOrEqualTo(5.0));
    });

    test('T4.4 SusEvaluationAnalyzer verifies SUS >= 75 and <30s pairing', () {
      const analyzer = SusEvaluationAnalyzer();
      final cohort = <SusParticipantRecord>[
        SusParticipantRecord(
          participantId: 'P1',
          responses: const <int>[5, 1, 5, 1, 4, 2, 5, 1, 5, 1],
          pairingDurationSeconds: 18.4,
          completedOneClickTransfer: true,
        ),
        SusParticipantRecord(
          participantId: 'P2',
          responses: const <int>[4, 2, 4, 2, 4, 2, 4, 2, 5, 2],
          pairingDurationSeconds: 22.1,
          completedOneClickTransfer: true,
        ),
        SusParticipantRecord(
          participantId: 'P3',
          responses: const <int>[5, 2, 4, 1, 5, 1, 4, 1, 5, 2],
          pairingDurationSeconds: 15.7,
          completedOneClickTransfer: true,
        ),
      ];
      expect(analyzer.computeMeanSus(cohort), greaterThanOrEqualTo(75.0));
      expect(analyzer.passesUsabilityGate(cohort), isTrue);
    });
  });
}
