// Hostile inputs for the file receiver that the desktop and the phone share.
// Each test states what a correct receiver must do; a failure is a bug.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:test/test.dart';

FileOfferItem item(String path, List<int> bytes,
        {String id = 'i0', int? size}) =>
    FileOfferItem(
        itemId: id,
        path: path,
        size: size ?? bytes.length,
        sha256: sha256.convert(bytes).toString(),
        mime: 'application/octet-stream',
        modifiedAt: 0);

/// Validates, then uploads every item whole. Returns the saved files; any
/// error escapes, as it would from the HTTP route.
Future<List<File>> receive(
    StreamingFileReceiver r, Map<FileOfferItem, List<int>> items) async {
  await r.validateOffer(items: items.keys.toList());
  final saved = <File>[];
  for (final e in items.entries) {
    final f = await r.appendChunk(
        item: e.key, offset: 0, chunk: Uint8List.fromList(e.value));
    if (f != null) saved.add(f);
  }
  return saved;
}

/// What the routes turn into an HTTP error. Anything else (e.g. a
/// FileSystemException) escapes the route and leaves the transfer hanging.
Matcher get handled => throwsA(isA<ProtocolException>());

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('dc_adv_'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // A long-path leftover; not this test's concern.
    }
  });

  group('offers that used to break the receiver', () {
    test('ADV-01 a file whose name is a folder already in Downloads', () async {
      // e.g. a file called "Screenshots" (no extension) while the folder
      // Downloads/Screenshots exists. It must be saved as "Screenshots (1)".
      Directory('${dir.path}/Screenshots').createSync();
      final r = StreamingFileReceiver(destinationRoot: dir);
      final bytes = [1, 2, 3];
      final saved = await receive(r, {item('Screenshots', bytes): bytes});
      expect(saved.single.readAsBytesSync(), bytes);
      expect(Directory('${dir.path}/Screenshots').existsSync(), isTrue);
    });

    test('ADV-01b a file and a folder with the same name in one offer',
        () async {
      // "report" is a file, and also the folder of "report/a.txt".
      final r = StreamingFileReceiver(destinationRoot: dir);
      final offer = [
        item('report', [1]),
        item('report/a.txt', [2], id: 'i1')
      ];
      await expectLater(r.validateOffer(items: offer), handled);
    });

    test('ADV-01c the same clash, differing only in case (Windows/macOS)',
        () async {
      final r = StreamingFileReceiver(destinationRoot: dir);
      final offer = [
        item('Report', [1]),
        item('report/a.txt', [2], id: 'i1')
      ];
      await expectLater(r.validateOffer(items: offer), handled);
    });

    test('ADV-02 an offer bigger than the free space', () async {
      // The phone accepts offers by itself; it now passes its free space.
      final r = StreamingFileReceiver(
          destinationRoot: dir, availableDiskBytes: () async => 1 << 30);
      await expectLater(
          r.validateOffer(items: [item('huge.bin', const [], size: 1 << 50)]),
          handled);
    });
  });

  group('hard cases the receiver already survives', () {
    test('ADV-03 a path longer than Windows MAX_PATH (260 chars)', () async {
      // Legal per §17.3: 12 folders of 120 chars, about 1 500 chars in all.
      final deep =
          [for (var i = 0; i < 12; i++) 'folder$i-${'x' * 112}'].join('/');
      final r = StreamingFileReceiver(destinationRoot: dir);
      final bytes = [1, 2, 3];
      final saved = await receive(r, {item('$deep/end.txt', bytes): bytes});
      expect(saved.single.readAsBytesSync(), bytes);
    });

    test('ADV-04 a file named like another file\'s temporary file', () async {
      // Item "photo.jpg.part" next to item "photo.jpg" in one offer.
      final r = StreamingFileReceiver(destinationRoot: dir);
      final a = [1, 1, 1], b = [2, 2];
      final saved = await receive(r, {
        item('photo.jpg', a): a,
        item('photo.jpg.part', b, id: 'i1'): b,
      });
      expect(saved.map((f) => f.readAsBytesSync()).toList(), [a, b]);
    });

    test('ADV-05 a sender retry racing the first upload of the same item',
        () async {
      // The first POST is still writing when the sender times out and
      // re-sends from 0. One may be refused; the file must not be corrupt.
      final r = StreamingFileReceiver(destinationRoot: dir);
      final bytes = List<int>.generate(kStreamingChunkSize * 2, (i) => i % 251);
      final it = item('race.bin', bytes);
      await r.validateOffer(items: [it]);
      final first = Uint8List.fromList(bytes.sublist(0, kStreamingChunkSize));
      final results = await Future.wait([
        r
            .appendChunk(item: it, offset: 0, chunk: first)
            .then((_) => 'ok', onError: (Object e) => '$e'),
        r
            .appendChunk(item: it, offset: 0, chunk: first)
            .then((_) => 'ok', onError: (Object e) => '$e'),
      ]);
      final part = r.partFileFor(it);
      // Whatever happened, at most one copy of the first chunk is on disk.
      expect(part.lengthSync(), kStreamingChunkSize, reason: '$results');
      final saved = await r.appendChunk(
          item: it,
          offset: kStreamingChunkSize,
          chunk: Uint8List.fromList(bytes.sublist(kStreamingChunkSize)));
      expect(saved!.readAsBytesSync(), bytes);
    });

    test('ADV-06 Thai name in NFC and NFD forms in one offer', () async {
      // "café" composed vs decomposed: different strings, same name on macOS.
      final r = StreamingFileReceiver(destinationRoot: dir);
      final a = [1], b = [2];
      final saved = await receive(r, {
        item('café.txt', a): a,
        item('café.txt', b, id: 'i1'): b,
      });
      expect(saved.map((f) => f.readAsBytesSync()).toList(), [a, b]);
      expect(saved[0].path, isNot(saved[1].path));
    });
  });
}
