import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:test/test.dart';

class _LoopbackChunkSink implements TransferChunkSink {
  final StreamingFileReceiver receiver;
  final FileOfferItem item;
  final ResumableCheckpointStore? checkpointStore;
  final List<int> chunkSizes = <int>[];

  /// Simulates a dropped connection: the chunk at this offset never arrives.
  final int? dropAtOffset;

  _LoopbackChunkSink({
    required this.receiver,
    required this.item,
    this.checkpointStore,
    this.dropAtOffset,
  });

  @override
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required Uint8List bytes,
  }) async {
    if (offset == dropAtOffset) {
      throw const SocketException('connection dropped');
    }
    chunkSizes.add(bytes.length);
    final completed = await receiver.writeChunk(
      item: item,
      offset: offset,
      chunk: bytes,
    );
    if (!completed && checkpointStore != null) {
      await checkpointStore!.recordProgressIfBoundary(
        transferId: transferId,
        item: item,
        bytesWritten: offset + bytes.length,
      );
    }
  }
}

void main() {
  group('StreamingFileSender & ResumableCheckpointStore (T1.10/T1.11)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dropclip_tx_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('streams multi-chunk file, verifies SHA-256, and renames .part',
        () async {
      final srcFile = File('${tempDir.path}/source.bin');
      final payload = Uint8List.fromList(
        List<int>.generate(2500000, (i) => i & 0xff),
      );
      await srcFile.writeAsBytes(payload, flush: true);

      final sha = await computeFileSha256(srcFile);
      final item = FileOfferItem(
        itemId: '11111111-1111-4111-8111-111111111111',
        path: 'docs/report.bin',
        size: payload.length,
        sha256: sha,
        mime: 'application/octet-stream',
        modifiedAt: 1700000000000,
      );

      final destDir = Directory('${tempDir.path}/downloads');
      final receiver = StreamingFileReceiver(
        destinationRoot: destDir,
        availableDiskBytes: () async => 100 * 1024 * 1024,
      );
      await receiver.validateOffer(items: <FileOfferItem>[item]);

      final sink = _LoopbackChunkSink(receiver: receiver, item: item);
      final progresses = <TransferProgress>[];
      const sender = StreamingFileSender();
      await sender.sendFile(
        transferId: 'tx-100',
        item: item,
        sourceFile: srcFile,
        sink: sink,
        onProgress: progresses.add,
      );

      expect(
        sink.chunkSizes,
        equals(<int>[kStreamingChunkSize, kStreamingChunkSize, 402848]),
      );
      expect(progresses.last.percentage, equals(100.0));
      expect(await receiver.partFileFor(item).exists(), isFalse);
      final finalFile = receiver.finalFileFor(item);
      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.length(), equals(payload.length));
    });

    test('rejects disk full, offset mismatch, and corrupted SHA-256 checksum',
        () async {
      final item = FileOfferItem(
        itemId: '22222222-2222-4222-8222-222222222222',
        path: 'bad.bin',
        size: 8,
        sha256: '0' * 64,
        mime: 'application/octet-stream',
        modifiedAt: 1700000000000,
      );
      final destDir = Directory('${tempDir.path}/downloads');
      final lowSpaceReceiver = StreamingFileReceiver(
        destinationRoot: destDir,
        availableDiskBytes: () async => 4,
      );
      await expectLater(
        lowSpaceReceiver.validateOffer(items: <FileOfferItem>[item]),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.errorCode,
            'errorCode',
            ProtocolErrorCode.diskFull,
          ),
        ),
      );

      final receiver = StreamingFileReceiver(destinationRoot: destDir);
      await expectLater(
        receiver.writeChunk(
          item: item,
          offset: 4,
          chunk: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.errorCode,
            'errorCode',
            ProtocolErrorCode.offsetMismatch,
          ),
        ),
      );

      await expectLater(
        receiver.writeChunk(
          item: item,
          offset: 0,
          chunk: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        ),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.errorCode,
            'errorCode',
            ProtocolErrorCode.checksumMismatch,
          ),
        ),
      );
      expect(await receiver.partFileFor(item).exists(), isFalse);
    });

    test('saves checkpoint, truncates unaligned tail on resume, and purges old',
        () async {
      final srcFile = File('${tempDir.path}/resume_src.bin');
      final bytes = Uint8List.fromList(
        List<int>.generate(4096, (i) => i & 255),
      );
      await srcFile.writeAsBytes(bytes, flush: true);
      final sha = await computeFileSha256(srcFile);

      final item = FileOfferItem(
        itemId: '33333333-3333-4333-8333-333333333333',
        path: 'archive.tar',
        size: bytes.length,
        sha256: sha,
        mime: 'application/x-tar',
        modifiedAt: 1700000000000,
      );

      var clockMs = 1000000;
      final stateDir = Directory('${tempDir.path}/state');
      final downDir = Directory('${tempDir.path}/down');
      final store = ResumableCheckpointStore(
        stateDirectory: stateDir,
        downloadDirectory: downDir,
        checkpointIntervalBytes: 2048,
        nowMs: () => clockMs,
      );
      final receiver = StreamingFileReceiver(destinationRoot: downDir);

      // Write first 2048 bytes (checkpoint boundary) + 500 unaligned tail bytes
      await receiver.writeChunk(
        item: item,
        offset: 0,
        chunk: Uint8List.sublistView(bytes, 0, 2048),
      );
      final cp = await store.recordProgressIfBoundary(
        transferId: 'tx-resume',
        item: item,
        bytesWritten: 2048,
      );
      expect(cp, isNotNull);
      expect(cp!.checkpointOffset, equals(2048));

      await receiver.writeChunk(
        item: item,
        offset: 2048,
        chunk: Uint8List.sublistView(bytes, 2048, 2548),
      );

      // Reload store from disk and prepare resume (truncates 2548 -> 2048)
      final reloaded = ResumableCheckpointStore(
        stateDirectory: stateDir,
        downloadDirectory: downDir,
        checkpointIntervalBytes: 2048,
        nowMs: () => clockMs,
      );
      await reloaded.load();
      final resumeOffset = await reloaded.prepareResumeOffset(
        transferId: 'tx-resume',
        item: item,
      );
      expect(resumeOffset, equals(2048));
      expect(await receiver.partFileFor(item).length(), equals(2048));

      // Complete transfer from resumeOffset = 2048
      final done = await receiver.writeChunk(
        item: item,
        offset: resumeOffset,
        chunk: Uint8List.sublistView(bytes, 2048),
      );
      expect(done, isTrue);
      expect(await receiver.finalFileFor(item).exists(), isTrue);

      // Verify 24h stale checkpoint purge
      clockMs += kPartFileMaxAgeMs + 1000;
      final purged = await reloaded.purgeExpiredPartFiles();
      expect(purged, equals(1));
    });

    test('dropped streaming transfer resumes from the last checkpoint',
        () async {
      final srcFile = File('${tempDir.path}/big.bin');
      final payload = Uint8List.fromList(
        List<int>.generate(2500000, (i) => (i * 7) & 0xff),
      );
      await srcFile.writeAsBytes(payload, flush: true);
      final item = FileOfferItem(
        itemId: '44444444-4444-4444-8444-444444444444',
        path: 'video.mp4',
        size: payload.length,
        sha256: await computeFileSha256(srcFile),
        mime: 'video/mp4',
        modifiedAt: 1700000000000,
      );
      final downDir = Directory('${tempDir.path}/down');
      final store = ResumableCheckpointStore(
        stateDirectory: Directory('${tempDir.path}/state'),
        downloadDirectory: downDir,
        checkpointIntervalBytes: kStreamingChunkSize,
      );
      final receiver = StreamingFileReceiver(destinationRoot: downDir);
      const sender = StreamingFileSender();

      // The third chunk never arrives; two 1 MiB checkpoints were saved.
      await expectLater(
        sender.sendFile(
          transferId: 'tx-drop',
          item: item,
          sourceFile: srcFile,
          sink: _LoopbackChunkSink(
            receiver: receiver,
            item: item,
            checkpointStore: store,
            dropAtOffset: 2 * kStreamingChunkSize,
          ),
        ),
        throwsA(isA<SocketException>()),
      );
      final resumeAt =
          await store.prepareResumeOffset(transferId: 'tx-drop', item: item);
      expect(resumeAt, equals(2 * kStreamingChunkSize));

      final resumed = _LoopbackChunkSink(
        receiver: receiver,
        item: item,
        checkpointStore: store,
      );
      await sender.sendFile(
        transferId: 'tx-drop',
        item: item,
        sourceFile: srcFile,
        sink: resumed,
        startOffset: resumeAt,
      );
      expect(resumed.chunkSizes, equals(<int>[402848]));
      final finalFile = receiver.finalFileFor(item);
      expect(await computeFileSha256(finalFile), equals(item.sha256));
    });
  });
}
