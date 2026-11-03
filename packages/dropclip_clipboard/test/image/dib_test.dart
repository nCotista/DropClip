import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

/// Builds a DIB from top-down RGBA pixels, like Windows puts on the
/// clipboard. [header] is 40, 108 or 124 bytes.
Uint8List makeDib(int w, int h, List<List<int>> rgba,
    {int bpp = 32,
    int header = 40,
    bool bitfields = false,
    bool bottomUp = true,
    int pelsPerMetre = 0,
    ({int r, int g, int b, int a})? masks}) {
  final m =
      masks ?? (r: 0x00FF0000, g: 0x0000FF00, b: 0x000000FF, a: 0xFF000000);
  final stride = ((w * bpp + 31) ~/ 32) * 4;
  final extra = bitfields && header == 40 ? 12 : 0;
  final d = ByteData(header + extra + stride * h)
    ..setUint32(0, header, Endian.little)
    ..setInt32(4, w, Endian.little)
    ..setInt32(8, bottomUp ? h : -h, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, bpp, Endian.little)
    ..setUint32(16, bitfields ? 3 : 0, Endian.little)
    ..setInt32(24, pelsPerMetre, Endian.little)
    ..setInt32(28, pelsPerMetre, Endian.little);
  if (bitfields || header > 40) {
    d
      ..setUint32(40, m.r, Endian.little)
      ..setUint32(44, m.g, Endian.little)
      ..setUint32(48, m.b, Endian.little);
    if (header > 40) d.setUint32(52, m.a, Endian.little);
  }
  int place(int v, int mask) {
    if (mask == 0) return 0;
    var s = 0;
    while ((mask >> s) & 1 == 0) {
      s++;
    }
    return (v << s) & mask;
  }

  for (var y = 0; y < h; y++) {
    final row = header + extra + (bottomUp ? h - 1 - y : y) * stride;
    for (var x = 0; x < w; x++) {
      final p = rgba[y * w + x], o = row + x * (bpp ~/ 8);
      if (bpp == 24) {
        d
          ..setUint8(o, p[2])
          ..setUint8(o + 1, p[1])
          ..setUint8(o + 2, p[0]);
      } else {
        d.setUint32(
            o,
            place(p[0], m.r) |
                place(p[1], m.g) |
                place(p[2], m.b) |
                place(p[3], m.a),
            Endian.little);
      }
    }
  }
  return d.buffer.asUint8List();
}

List<List<int>> pixels(RgbaImage img) => [
      for (var i = 0; i < img.pixels.length; i += 4)
        img.pixels.sublist(i, i + 4),
    ];

const red = [255, 0, 0, 255], green = [0, 255, 0, 255];
const blue = [0, 0, 255, 255], clear = [10, 20, 30, 0];
const half = [200, 100, 50, 128], white = [255, 255, 255, 255];

void main() {
  group('decodeDib (T1.8, FR-06, PROTO-DC-V2.0 §11.2)', () {
    test('24 bpp bottom-up with row padding → RGBA, opaque', () {
      final img = decodeDib(
          makeDib(3, 2, [red, green, blue, white, red, green], bpp: 24));
      expect([img.width, img.height], [3, 2]);
      expect(pixels(img), [red, green, blue, white, red, green]);
    });

    test('32 bpp BI_RGB with all-zero alpha bytes is opaque', () {
      final dib = makeDib(2, 1, [red, blue],
          masks: (r: 0xFF0000, g: 0xFF00, b: 0xFF, a: 0));
      expect(pixels(decodeDib(dib)), [red, blue]);
    });

    test('32 bpp BI_RGB top-down keeps real alpha', () {
      expect(pixels(decodeDib(makeDib(2, 1, [half, red], bottomUp: false))),
          [half, red]);
    });

    test('CF_DIBV5 BI_BITFIELDS keeps alpha from bV5AlphaMask', () {
      final dib =
          makeDib(3, 1, [clear, half, green], header: 124, bitfields: true);
      expect(pixels(decodeDib(dib)), [clear, half, green]);
    });

    test('40-byte header + BI_BITFIELDS masks in RGBA byte order', () {
      final dib = makeDib(2, 2, [red, green, blue, white],
          bitfields: true, masks: (r: 0xFF, g: 0xFF00, b: 0xFF0000, a: 0));
      expect(pixels(decodeDib(dib)), [red, green, blue, white]);
    });

    test('keeps every pixel (no downscale) and the DPI', () {
      final img =
          decodeDib(makeDib(5, 4, List.filled(20, half), pelsPerMetre: 5669));
      expect([img.width, img.height], [5, 4]);
      expect(img.xPixelsPerMetre, 5669);
    });

    test('malformed or unsupported input throws NormalizationException', () {
      final ok = makeDib(2, 2, [red, red, red, red]);
      Uint8List withHeader(int offset, int v, {int size = 4}) {
        final b = Uint8List.fromList(ok);
        final d = ByteData.sublistView(b);
        size == 2
            ? d.setUint16(offset, v, Endian.little)
            : d.setInt32(offset, v, Endian.little);
        return b;
      }

      for (final bad in [
        Uint8List(10), // too short
        withHeader(0, 64), // unknown header size
        withHeader(4, 0), // zero width
        withHeader(14, 8, size: 2), // 8 bpp palette
        withHeader(16, 1), // RLE8
        ok.sublist(0, ok.length - 1), // truncated pixels
      ]) {
        expect(() => decodeDib(bad), throwsA(isA<NormalizationException>()));
      }
      expect(() => decodeDib(ok, maxPixels: 3),
          throwsA(isA<NormalizationException>()),
          reason: 'pixel limit');
      expect(() => decodeDib(withHeader(4, 100000)),
          throwsA(isA<NormalizationException>()),
          reason: 'bomb size');
    });
  });

  group('encodePng', () {
    test('valid chunks, CRCs and pixels', () {
      final img = decodeDib(makeDib(
          3, 2, [red, clear, half, blue, white, green],
          header: 124, bitfields: true, pelsPerMetre: 3780));
      final png = encodePng(img);
      expect(png.sublist(0, 8), pngSignature);

      final d = ByteData.sublistView(png);
      final chunks = <String, Uint8List>{};
      for (var o = 8; o < png.length;) {
        final len = d.getUint32(o);
        final type = String.fromCharCodes(png.sublist(o + 4, o + 8));
        final body = png.sublist(o + 8, o + 8 + len);
        expect(
            d.getUint32(o + 8 + len), pngCrc32(png.sublist(o + 4, o + 8 + len)),
            reason: '$type CRC');
        chunks[type] = body;
        o += 12 + len;
      }
      expect(chunks.keys, ['IHDR', 'pHYs', 'IDAT', 'IEND']);
      expect(pngCrc32('IEND'.codeUnits), 0xAE426082);

      final ihdr = ByteData.sublistView(chunks['IHDR']!);
      expect([
        ihdr.getUint32(0),
        ihdr.getUint32(4),
        ihdr.getUint8(8),
        ihdr.getUint8(9)
      ], [
        3,
        2,
        8,
        6
      ]);
      expect(ByteData.sublistView(chunks['pHYs']!).getUint32(0), 3780);

      final raw = ZLibDecoder().convert(chunks['IDAT']!);
      expect(raw, hasLength((3 * 4 + 1) * 2));
      expect([raw[0], raw[13]], [0, 2]); // None, then Up
      final row0 = raw.sublist(1, 13);
      expect(row0, [...red, ...clear, ...half]);
      // Undo the Up filter: each byte plus the byte above, mod 256.
      final row1 = [
        for (var i = 0; i < 12; i++) (raw[14 + i] + row0[i]) & 0xFF
      ];
      expect(row1, [...blue, ...white, ...green]);

      final plain =
          ZLibDecoder().convert(_idat(encodePng(img, upFilter: false)));
      expect([plain[0], plain[13]], [0, 0]);
      expect(plain.sublist(14), [...blue, ...white, ...green]);
    });

    test('no pHYs when DPI is unknown', () {
      final png = dibToPng(makeDib(1, 1, [red]));
      expect(String.fromCharCodes(png).contains('pHYs'), isFalse);
    });

    test('4K screenshot converts (NFR-P05 timing printed)', () {
      final dib = makeDib(3840, 2160, List.filled(3840 * 2160, half),
          header: 124, bitfields: true);
      final sw = Stopwatch()..start();
      final png = dibToPng(dib);
      sw.stop();
      // ignore: avoid_print
      print('4K CF_DIBV5 → PNG: ${sw.elapsedMilliseconds} ms (JIT)');
      expect(png.length, greaterThan(0));
    });
  });
}

/// The IDAT payload of a PNG with a single IDAT chunk.
List<int> _idat(Uint8List png) {
  final d = ByteData.sublistView(png);
  for (var o = 8; o < png.length;) {
    final len = d.getUint32(o);
    if (String.fromCharCodes(png.sublist(o + 4, o + 8)) == 'IDAT') {
      return png.sublist(o + 8, o + 8 + len);
    }
    o += 12 + len;
  }
  throw StateError('no IDAT');
}
