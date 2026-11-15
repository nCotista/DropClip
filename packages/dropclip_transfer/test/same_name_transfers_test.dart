import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:test/test.dart';

/// BUG-03: two transfers of a file with the same name (the user sends
/// `photo.jpg` twice, or two devices send `IMG_0001.jpg` at once) used to
/// share one `photo.jpg.part`, so the second upload broke the first.
void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('dc_same_'));
  tearDown(() => dir.delete(recursive: true));

  FileOfferItem offer(String id, Uint8List bytes) => FileOfferItem(
      itemId: id,
      path: 'photo.jpg',
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mime: 'image/jpeg',
      modifiedAt: 0);

  test('two same-named files arriving at once are both saved', () async {
    final a = Uint8List.fromList(List.filled(kStreamingChunkSize + 10, 1));
    final b = Uint8List.fromList(List.filled(kStreamingChunkSize + 20, 2));
    // One receiver per transfer, as the desktop creates them.
    final ra = StreamingFileReceiver(destinationRoot: dir, transferId: 'a');
    final rb = StreamingFileReceiver(destinationRoot: dir, transferId: 'b');
    final ia = offer('i0', a), ib = offer('i0', b);

    // Interleaved, as two HTTP uploads stream at the same time.
    await ra.appendChunk(
        item: ia, offset: 0, chunk: a.sublist(0, kStreamingChunkSize));
    await rb.appendChunk(
        item: ib, offset: 0, chunk: b.sublist(0, kStreamingChunkSize));
    final fa = await ra.appendChunk(
        item: ia,
        offset: kStreamingChunkSize,
        chunk: a.sublist(kStreamingChunkSize));
    final fb = await rb.appendChunk(
        item: ib,
        offset: kStreamingChunkSize,
        chunk: b.sublist(kStreamingChunkSize));

    expect(await fa!.readAsBytes(), a);
    expect(await fb!.readAsBytes(), b);
    expect(fa.path, isNot(fb.path));
  });
}
