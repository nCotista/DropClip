import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../dropclip_transfer.dart';

/// Normative 1 MiB streaming chunk size (SRS NFR-R01, Engineering Rule #5).
const int kStreamingChunkSize = 1024 * 1024;

/// Computes SHA-256 of [file] up to [maxBytes] by streaming in 1 MiB chunks.
/// Never buffers the whole file in RAM.
Future<String> computeFileSha256(
  File file, {
  int? maxBytes,
  int chunkSize = kStreamingChunkSize,
}) async {
  final output = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in readFileInChunks(
    file,
    offset: 0,
    maxBytes: maxBytes,
    chunkSize: chunkSize,
  )) {
    input.add(chunk);
  }
  input.close();
  return output.events.single.toString();
}

/// Streams [file] starting at [offset] in slices of at most [chunkSize] bytes.
Stream<Uint8List> readFileInChunks(
  File file, {
  int offset = 0,
  int? maxBytes,
  int chunkSize = kStreamingChunkSize,
}) async* {
  if (chunkSize <= 0) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
  }
  final end = maxBytes == null ? null : offset + maxBytes;
  final rawStream = file.openRead(offset, end);
  final buffer = BytesBuilder(copy: false);
  await for (final block in rawStream) {
    buffer.add(block);
    while (buffer.length >= chunkSize) {
      final all = buffer.takeBytes();
      yield Uint8List.sublistView(all, 0, chunkSize);
      if (all.length > chunkSize) {
        buffer.add(Uint8List.sublistView(all, chunkSize));
      }
    }
  }
  if (buffer.isNotEmpty) {
    yield buffer.takeBytes();
  }
}

/// Sink abstraction for sending streaming chunks over HTTP/1.1 Data Plane.
abstract interface class TransferChunkSink {
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required Uint8List bytes,
  });
}

/// Streams outbound files in 1 MiB chunks without whole-file RAM buffering
/// (T1.10, PROTO-DC-V2.0 §9.5 & §12.2).
class StreamingFileSender {
  final int chunkSize;

  const StreamingFileSender({this.chunkSize = kStreamingChunkSize});

  Future<void> sendFile({
    required String transferId,
    required FileOfferItem item,
    required File sourceFile,
    required TransferChunkSink sink,
    int startOffset = 0,
    void Function(TransferProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (startOffset < 0 || startOffset > item.size) {
      throw const ProtocolException(
        ProtocolErrorCode.offsetMismatch,
        'invalid start offset for streaming file sender',
      );
    }
    var currentOffset = startOffset;
    await for (final chunk in readFileInChunks(
      sourceFile,
      offset: startOffset,
      chunkSize: chunkSize,
    )) {
      if (isCancelled != null && isCancelled()) {
        throw const ProtocolException(
          ProtocolErrorCode.internal,
          'transfer cancelled by sender',
        );
      }
      await sink.sendChunk(
        transferId: transferId,
        itemId: item.itemId,
        offset: currentOffset,
        bytes: chunk,
      );
      currentOffset += chunk.length;
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          itemId: item.itemId,
          bytesTransferred: currentOffset,
          totalBytes: item.size,
        ),
      );
    }
  }
}

/// Receives streaming file chunks into `.part` files, enforces path safety and
/// disk quotas, and verifies SHA-256 before atomic rename (T1.10, §12.3).
class StreamingFileReceiver {
  final Directory destinationRoot;
  final Future<int> Function()? availableDiskBytes;
  final void Function(String itemId, int bytesWritten)? onCheckpointEligible;

  StreamingFileReceiver({
    required this.destinationRoot,
    this.availableDiskBytes,
    this.onCheckpointEligible,
  });

  /// Validates an entire offer batch for path traversal, reserved names,
  /// case-insensitive collisions, and available disk space.
  Future<void> validateOffer({required List<FileOfferItem> items}) async {
    try {
      PathSanitizer.validateOfferPaths(items.map((e) => e.path).toList());
    } on InvalidPathException catch (e) {
      throw ProtocolException(ProtocolErrorCode.invalidPath, e.reason);
    }
    if (availableDiskBytes != null) {
      final freeBytes = await availableDiskBytes!();
      final needed = items.fold<int>(0, (sum, item) => sum + item.size);
      if (freeBytes < needed) {
        throw const ProtocolException(
          ProtocolErrorCode.diskFull,
          'insufficient free disk space for file offer',
        );
      }
    }
  }

  File partFileFor(FileOfferItem item) {
    final safeRel = PathSanitizer.sanitize(item.path);
    return File('${destinationRoot.path}/$safeRel.part');
  }

  File finalFileFor(FileOfferItem item) {
    final safeRel = PathSanitizer.sanitize(item.path);
    return File('${destinationRoot.path}/$safeRel');
  }

  /// Appends [chunk] at [offset] to the `.part` file for [item].
  /// When the file reaches `item.size`, verifies SHA-256 and renames `.part`.
  Future<bool> writeChunk({
    required FileOfferItem item,
    required int offset,
    required Uint8List chunk,
  }) async =>
      await appendChunk(item: item, offset: offset, chunk: chunk) != null;

  /// A name next to [wanted] that is not taken: `photo.jpg`, then
  /// `photo (1).jpg`, `photo (2).jpg`, ... A received file never replaces
  /// one the user already has.
  static Future<File> freeNameFor(File wanted) async {
    if (!await wanted.exists()) return wanted;
    final path = wanted.path;
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    final hasExt = dot > slash + 1;
    final stem = hasExt ? path.substring(0, dot) : path;
    final ext = hasExt ? path.substring(dot) : '';
    for (var i = 1;; i++) {
      final next = File('$stem ($i)$ext');
      if (!await next.exists()) return next;
    }
  }

  /// Like [writeChunk], but returns the saved file once [item] is complete
  /// (null while more chunks are expected). A zero-length [chunk] at offset
  /// 0 completes an empty file.
  Future<File?> appendChunk({
    required FileOfferItem item,
    required int offset,
    required Uint8List chunk,
  }) async {
    if (chunk.length > kStreamingChunkSize) {
      throw const ProtocolException(
        ProtocolErrorCode.payloadTooLarge,
        'data plane chunk exceeds 1 MiB streaming limit',
      );
    }
    final partFile = partFileFor(item);
    await partFile.parent.create(recursive: true);
    final currentLen = await partFile.exists() ? await partFile.length() : 0;
    if (offset != currentLen) {
      throw ProtocolException(
        ProtocolErrorCode.offsetMismatch,
        'expected offset $currentLen but received $offset',
      );
    }
    if (offset + chunk.length > item.size) {
      throw const ProtocolException(
        ProtocolErrorCode.payloadTooLarge,
        'received bytes exceed declared file size',
      );
    }
    final raf = await partFile.open(mode: FileMode.append);
    try {
      await raf.writeFrom(chunk);
      await raf.flush();
    } finally {
      await raf.close();
    }

    final newLen = offset + chunk.length;
    onCheckpointEligible?.call(item.itemId, newLen);

    if (newLen == item.size) {
      final actualSha = await computeFileSha256(partFile);
      if (actualSha.toLowerCase() != item.sha256.toLowerCase()) {
        await partFile.delete();
        throw const ProtocolException(
          ProtocolErrorCode.checksumMismatch,
          'final SHA-256 checksum mismatch; .part file deleted',
        );
      }
      final wanted = finalFileFor(item);
      await wanted.parent.create(recursive: true);
      final target = await freeNameFor(wanted);
      await partFile.rename(target.path);
      return target;
    }
    return null;
  }
}
