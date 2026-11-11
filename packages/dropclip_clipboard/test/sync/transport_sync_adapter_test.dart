import 'dart:convert';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  const idA = '11111111-1111-4111-8111-111111111111';
  const idB = '22222222-2222-4222-8222-222222222222';

  group('TransportSyncAdapter & ClipboardSyncEngine Join (T1.9)', () {
    test('routes inline text and Data Plane image blobs between two nodes',
        () async {
      final wireFromA = <Envelope>[];
      Uint8List? writtenOnB;
      ClipType? writtenTypeOnB;
      late TransportSyncAdapter adapterA;

      adapterA = TransportSyncAdapter(
        sendBroadcastEnvelope: wireFromA.add,
        nowMs: () => 1700000000000,
      );
      final adapterB = TransportSyncAdapter(
        sendBroadcastEnvelope: (_) {},
        remoteBlobFetcher: (_, blobId) async => adapterA.getLocalBlob(blobId),
        osWriteClipboard: (type, raw) async {
          writtenTypeOnB = type;
          writtenOnB = raw;
        },
        nowMs: () => 1700000000000,
      );

      final engineA = ClipboardSyncEngine(
        myId: idA,
        ports: adapterA,
        policy: () => const SyncPolicy(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final engineB = ClipboardSyncEngine(
        myId: idB,
        ports: adapterB,
        policy: () => const SyncPolicy(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      // 1. Inline text sync
      final textBytes = Uint8List.fromList(utf8.encode('Hello DropClip Mesh'));
      engineA.onLocalChange(LocalClip(ClipType.text, textBytes));
      expect(wireFromA, hasLength(1));

      final inboundText =
          TransportSyncAdapter.envelopeToClipUpdate(wireFromA.single);
      await engineB.onRemoteUpdate(inboundText);
      expect(writtenTypeOnB, equals(ClipType.text));
      expect(utf8.decode(writtenOnB!), equals('Hello DropClip Mesh'));

      // 2. Data Plane PNG blob sync
      wireFromA.clear();
      final pngBytes = encodePng(RgbaImage(2, 2, Uint8List(16)));
      engineA.onLocalChange(LocalClip(ClipType.image, pngBytes));
      expect(wireFromA, hasLength(1));

      final inboundImg =
          TransportSyncAdapter.envelopeToClipUpdate(wireFromA.single);
      expect(inboundImg.blobId, isNotNull);
      await engineB.onRemoteUpdate(inboundImg);
      expect(writtenTypeOnB, equals(ClipType.image));
      expect(writtenOnB, equals(pngBytes));
    });

    test('expires blobs after TTL and clears clipboard when hash still matches',
        () async {
      var nowMs = 1000;
      var cleared = false;
      final sample = Uint8List.fromList(utf8.encode('ephemeral secret'));

      final adapter = TransportSyncAdapter(
        sendBroadcastEnvelope: (_) {},
        osReadClipboardRaw: () async => sample,
        osClearClipboard: () async => cleared = true,
        nowMs: () => nowMs,
      );

      final id = adapter.putBlob(sample, const Duration(seconds: 5));
      expect(adapter.getLocalBlob(id), equals(sample));

      nowMs = 7000;
      expect(
        () => adapter.getLocalBlob(id),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.errorCode,
            'errorCode',
            ProtocolErrorCode.blobExpired,
          ),
        ),
      );

      final digest = TransportSyncAdapter.clipUpdateToEnvelope(
        ClipUpdate(
          msgId: idA,
          origin: idA,
          hlc: Hlc(l: 1000, c: 0, d: idA),
          ts: 1000,
          type: ClipType.text,
          hash: '0587b9e6c1339a2b208f7c338cf6e43a'
              '04cb0f26b49d9d80b857a022b86d6097',
          size: sample.length,
          inline: sample,
        ),
      );
      expect(digest.type, equals(MessageType.clipboardUpdate));

      await adapter.clearIfStill(
        TransportSyncAdapter.envelopeToClipUpdate(digest).hash,
      );
      // Sample SHA-256 verify
      final eng = ClipboardSyncEngine(
        myId: idA,
        ports: adapter,
        policy: () => const SyncPolicy(),
      );
      eng.onLocalChange(LocalClip(ClipType.text, sample));
      await adapter.clearIfStill(eng.head!.update.hash);
      expect(cleared, isTrue);
    });
  });
}
