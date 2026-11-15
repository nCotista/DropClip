import 'dart:convert';
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

  FileOfferItem offer(String id, Uint8List bytes, {String? badSha}) =>
      FileOfferItem(
        itemId: id,
        path: 'photo.jpg',
        size: bytes.length,
        sha256: badSha ?? sha256.convert(bytes).toString(),
        mime: 'image/jpeg',
        modifiedAt: 0,
      );

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

  test('concurrent same-name completions do not overwrite each other',
      () async {
    final a = Uint8List.fromList(utf8.encode('first-photo-bytes'));
    final b = Uint8List.fromList(utf8.encode('second-photo-bytes'));
    final ra = StreamingFileReceiver(destinationRoot: dir, transferId: 't1');
    final rb = StreamingFileReceiver(destinationRoot: dir, transferId: 't2');

    final files = await Future.wait([
      ra.appendChunk(item: offer('i0', a), offset: 0, chunk: a),
      rb.appendChunk(item: offer('i0', b), offset: 0, chunk: b),
    ]);
    final fa = files[0]!;
    final fb = files[1]!;
    expect(fa.path, isNot(fb.path));
    expect(await fa.readAsBytes(), a);
    expect(await fb.readAsBytes(), b);
  });

  test('partFileFor isolates transfers and sanitizes untrusted transferIds',
      () {
    final item = offer('i0', Uint8List.fromList([1]));
    final plain = StreamingFileReceiver(destinationRoot: dir);
    final t1a = StreamingFileReceiver(destinationRoot: dir, transferId: 'id-1');
    final t1b = StreamingFileReceiver(destinationRoot: dir, transferId: 'id-1');
    final t2 = StreamingFileReceiver(destinationRoot: dir, transferId: 'id-2');
    final hostile = StreamingFileReceiver(
      destinationRoot: dir,
      transferId: '../../evil\x00name',
    );

    expect(plain.partFileFor(item).path, endsWith('photo.jpg.part'));
    expect(t1a.partFileFor(item).path, t1b.partFileFor(item).path);
    expect(t1a.partFileFor(item).path, isNot(t2.partFileFor(item).path));
    final hp = hostile.partFileFor(item).path;
    expect(hp.startsWith(dir.path), isTrue);
    expect(hp.contains('..'), isFalse);
    expect(hp.contains('\x00'), isFalse);
  });

  test('checksum failure removes only its own .part file', () async {
    final a = Uint8List.fromList(List.filled(kStreamingChunkSize + 5, 3));
    final b = Uint8List.fromList(List.filled(16, 4));
    final ra = StreamingFileReceiver(destinationRoot: dir, transferId: 'good');
    final rb = StreamingFileReceiver(destinationRoot: dir, transferId: 'bad');
    final ia = offer('i0', a);
    final ib = offer('i0', b, badSha: '0' * 64);

    await ra.appendChunk(
        item: ia, offset: 0, chunk: a.sublist(0, kStreamingChunkSize));
    await expectLater(
      rb.appendChunk(item: ib, offset: 0, chunk: b),
      throwsA(isA<ProtocolException>()),
    );
    expect(await rb.partFileFor(ib).exists(), isFalse);
    expect(await ra.partFileFor(ia).exists(), isTrue);

    final saved = await ra.appendChunk(
      item: ia,
      offset: kStreamingChunkSize,
      chunk: a.sublist(kStreamingChunkSize),
    );
    expect(await saved!.readAsBytes(), a);
  });
}
