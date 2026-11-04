import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

/// One image of a test TIFF: [samples] are the raw pixel bytes.
class Img {
  final int w, h, spp, depth, photometric, compression;
  final int? extraSamples;
  final List<int> samples;
  final int rowsPerStrip;

  /// Written as the single strip's data instead of [samples].
  final List<int>? strip;

  Img(this.w, this.h, this.samples,
      {this.spp = 4,
      this.depth = 8,
      this.photometric = 2,
      this.compression = 1,
      this.extraSamples = 2,
      this.strip,
      int? rowsPerStrip})
      : rowsPerStrip = rowsPerStrip ?? h;
}

/// A TIFF with one IFD per image; [encode] turns a strip's rows into its
/// stored bytes (uncompressed by default).
Uint8List buildTiff(List<Img> images,
    {bool bigEndian = false,
    List<int>? dpi,
    List<int> Function(Img img, List<int> rows)? encode}) {
  final e = bigEndian ? Endian.big : Endian.little;
  List<int> u32(int v) =>
      (ByteData(4)..setUint32(0, v, e)).buffer.asUint8List();
  List<int> u16(int v) =>
      (ByteData(2)..setUint16(0, v, e)).buffer.asUint8List();
  final body = [
    ...bigEndian ? [0x4D, 0x4D] : [0x49, 0x49], ...u16(42), 0, 0, 0, 0, //
  ];
  final ifds = <int>[];
  for (final img in images) {
    final stride = img.w * img.spp * img.depth ~/ 8;
    final offsets = <int>[], counts = <int>[];
    for (var y = 0; y < img.h; y += img.rowsPerStrip) {
      final rows = img.samples
          .sublist(y * stride, (y + img.rowsPerStrip).clamp(0, img.h) * stride);
      final data = img.strip ?? encode?.call(img, rows) ?? rows;
      offsets.add(body.length);
      counts.add(data.length);
      body.addAll(data);
    }
    final res = body.length, arrays = res + 8, n = offsets.length;
    body.addAll([
      ...u32(dpi?[0] ?? 72), ...u32(dpi?[1] ?? 1), //
      for (final o in offsets) ...u32(o),
      for (final c in counts) ...u32(c),
      for (var i = 0; i < img.spp; i++) ...u16(img.depth),
    ]);
    final entries = [
      [256, 4, 1, img.w],
      [257, 4, 1, img.h],
      [258, 3, img.spp, img.spp == 1 ? img.depth : arrays + 8 * n],
      [259, 3, 1, img.compression],
      [262, 3, 1, img.photometric],
      [273, 4, n, n == 1 ? offsets.first : arrays],
      [277, 3, 1, img.spp],
      [278, 4, 1, img.rowsPerStrip],
      [279, 4, n, n == 1 ? counts.first : arrays + 4 * n],
      [282, 5, 1, res],
      [283, 5, 1, res],
      [296, 3, 1, 2],
      if (img.extraSamples != null && img.spp > (img.photometric == 2 ? 3 : 1))
        [338, 3, 1, img.extraSamples!],
    ];
    ifds.add(body.length);
    body.addAll(u16(entries.length));
    for (final [tag, type, count, value] in entries) {
      final v = type == 3 && count == 1 ? [...u16(value), 0, 0] : u32(value);
      body.addAll([...u16(tag), ...u16(type), ...u32(count), ...v]);
    }
    body.addAll(u32(0)); // next IFD, linked below
  }
  void link(int at, int to) => body.setRange(at, at + 4, u32(to));
  link(4, ifds.first);
  for (var i = 0; i + 1 < ifds.length; i++) {
    link(ifds[i] + 2 + _count(body, ifds[i], e) * 12, ifds[i + 1]);
  }
  return Uint8List.fromList(body);
}

int _count(List<int> body, int at, Endian e) =>
    ByteData.sublistView(Uint8List.fromList(body)).getUint16(at, e);

void main() {
  final rgba = [
    for (var i = 0; i < 6; i++) ...[i * 40, 255 - i * 40, i * 7, 255],
  ];
  RgbaImage decode(List<Img> images, {bool bigEndian = false}) =>
      decodeTiff(buildTiff(images, bigEndian: bigEndian));

  group('decodeTiff (T1.8, §11.2 macOS public.tiff)', () {
    test('uncompressed RGBA in strips, little-endian, with DPI', () {
      final img = decodeTiff(
          buildTiff([Img(3, 2, rgba, rowsPerStrip: 1)], dpi: [144, 1]));
      expect([img.width, img.height], [3, 2]);
      expect(img.pixels, rgba);
      expect(img.xPixelsPerMetre, 5669); // 144 dpi
    });

    test('picks the image with the most pixels (Retina rep), any order', () {
      final small = Img(1, 1, [1, 2, 3, 255]), big = Img(3, 2, rgba);
      expect(decode([small, big]).pixels, rgba);
      expect(decode([big, small]).pixels, rgba);
      expect(decode([big], bigEndian: true).pixels, rgba);
    });

    test('RGB, grey, white-is-zero and 16-bit samples', () {
      expect(
          decode([
            Img(1, 1, [9, 8, 7], spp: 3)
          ]).pixels,
          [9, 8, 7, 255]);
      expect(
          decode([
            Img(1, 1, [50], spp: 1, photometric: 1)
          ]).pixels,
          [50, 50, 50, 255]);
      expect(
          decode([
            Img(1, 1, [50], spp: 1, photometric: 0)
          ]).pixels,
          [205, 205, 205, 255]);
      final wide = [0x11, 0xAA, 0x22, 0xBB, 0x33, 0xCC];
      expect(decode([Img(1, 1, wide, spp: 3, depth: 16)]).pixels,
          [0xAA, 0xBB, 0xCC, 255],
          reason: 'little-endian 16-bit keeps the high (second) byte');
    });

    test('premultiplied alpha is undone; straight alpha is kept', () {
      final px = [50, 25, 0, 128];
      expect(
          decode([Img(1, 1, px, extraSamples: 1)]).pixels, [100, 50, 0, 128]);
      expect(decode([Img(1, 1, px)]).pixels, px);
    });

    test('tiffToPng gives a PNG of the same pixels', () {
      expect(decodePng(tiffToPng(buildTiff([Img(3, 2, rgba)]))).pixels, rgba);
    });

    group('rejects with NormalizationException (§11.3)', () {
      void rejects(List<Img> images, [int maxPixels = 64000000]) => expect(
          () => decodeTiff(buildTiff(images), maxPixels: maxPixels),
          throwsA(isA<NormalizationException>()));

      test('not a TIFF, or cut short', () {
        expect(() => decodeTiff(Uint8List.fromList([0x89, 0x50, 0, 0, 0, 0])),
            throwsA(isA<NormalizationException>()));
        final ok = buildTiff([Img(3, 2, rgba)]);
        expect(() => decodeTiff(Uint8List.sublistView(ok, 0, 20)),
            throwsA(isA<NormalizationException>()));
      });

      test('too many pixels, checked before reading pixels', () {
        rejects([Img(3, 2, rgba)], 5);
      });

      test('unsupported compression, bit depth or colour model', () {
        rejects([Img(3, 2, rgba, compression: 7)]); // JPEG
        rejects([
          Img(1, 1, [1], spp: 1, depth: 4)
        ]);
        rejects([
          Img(1, 1, [1], spp: 1, photometric: 3)
        ]); // palette
      });

      test('a strip shorter than its rows', () {
        rejects([
          Img(3, 2, rgba, strip: [1, 2, 3])
        ]);
      });
    });
  });
}
