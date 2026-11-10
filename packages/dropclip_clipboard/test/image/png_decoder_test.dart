import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

/// Builds a PNG from unfiltered rows, applying [filters] (one per row,
/// cycling) so every decoder path is exercised.
Uint8List buildPng(int w, int h, int depth, int type, List<List<int>> rows,
    {List<int> filters = const [0],
    List<int>? plte,
    List<int>? trns,
    int interlace = 0,
    List<int>? zlib}) {
  final channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[type]!;
  final bpp = ((channels * depth) + 7) >> 3;
  final raw = <int>[];
  for (var y = 0; y < rows.length; y++) {
    final f = filters[y % filters.length], row = rows[y];
    final prev = y > 0 ? rows[y - 1] : List.filled(row.length, 0);
    raw.add(f);
    for (var i = 0; i < row.length; i++) {
      final a = i >= bpp ? row[i - bpp] : 0, b = prev[i];
      final c = i >= bpp ? prev[i - bpp] : 0;
      final p = a + b - c;
      final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
      final paeth = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
      final pred = [0, a, b, (a + b) >> 1, paeth][f];
      raw.add((row[i] - pred) & 0xFF);
    }
  }
  List<int> u32(int v) => [v >> 24, v >> 16 & 255, v >> 8 & 255, v & 255];
  final out = BytesBuilder()..add(pngSignature);
  void chunk(String t, List<int> data) {
    final body = [...t.codeUnits, ...data];
    out.add([...u32(data.length), ...body, ...u32(pngCrc32(body))]);
  }

  chunk('IHDR', [...u32(w), ...u32(h), depth, type, 0, 0, interlace]);
  if (plte != null) chunk('PLTE', plte);
  if (trns != null) chunk('tRNS', trns);
  chunk('IDAT', zlib ?? ZLibEncoder().convert(raw));
  chunk('IEND', []);
  return out.takeBytes();
}

void main() {
  group('decodePng (T1.8, FR-06)', () {
    test('reads back what encodePng wrote, with DPI', () {
      final px = Uint8List.fromList(List.generate(3 * 2 * 4, (i) => i * 7));
      final img = decodePng(encodePng(
          RgbaImage(3, 2, px, xPixelsPerMetre: 5669, yPixelsPerMetre: 5669)));
      expect([img.width, img.height], [3, 2]);
      expect(img.pixels, px);
      expect(img.xPixelsPerMetre, 5669);
    });

    test('undoes all five row filters', () {
      final rows = List.generate(
          5, (y) => List.generate(4 * 3, (i) => (y * 31 + i * 17) & 0xFF));
      final img =
          decodePng(buildPng(4, 5, 8, 2, rows, filters: [0, 1, 2, 3, 4]));
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 4; x++) {
          final o = (y * 4 + x) * 4;
          expect(img.pixels.sublist(o, o + 4),
              [...rows[y].sublist(x * 3, x * 3 + 3), 255]);
        }
      }
    });

    test('greyscale 1-bit and 16-bit, grey+alpha, RGBA 16-bit', () {
      expect(
          decodePng(buildPng(3, 1, 1, 0, [
            [0xA0]
          ])).pixels,
          [255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255]);
      expect(
          decodePng(buildPng(1, 1, 16, 0, [
            [0x12, 0x34]
          ])).pixels,
          [0x12, 0x12, 0x12, 255]);
      expect(
          decodePng(buildPng(1, 1, 8, 4, [
            [90, 40]
          ])).pixels,
          [90, 90, 90, 40]);
      expect(
          decodePng(buildPng(1, 1, 16, 6, [
            [1, 0, 2, 0, 3, 0, 4, 0]
          ])).pixels,
          [1, 2, 3, 4]);
    });

    test('palette with transparency and an RGB colour key', () {
      final pal = buildPng(2, 1, 4, 3, [
        [0x01]
      ], plte: [
        10,
        20,
        30,
        40,
        50,
        60
      ], trns: [
        255,
        128
      ]);
      expect(decodePng(pal).pixels, [10, 20, 30, 255, 40, 50, 60, 128]);
      final key = buildPng(2, 1, 8, 2, [
        [1, 2, 3, 9, 9, 9]
      ], trns: [
        0,
        1,
        0,
        2,
        0,
        3
      ]);
      expect(decodePng(key).pixels, [1, 2, 3, 0, 9, 9, 9, 255]);
    });

    group('rejects with NormalizationException (§11.3)', () {
      final ok = buildPng(1, 1, 8, 6, [
        [1, 2, 3, 4]
      ]);
      void rejects(Uint8List png, [int maxPixels = 64000000]) => expect(
          () => decodePng(png, maxPixels: maxPixels),
          throwsA(isA<NormalizationException>()));

      test('not a PNG, truncated, or a bad CRC', () {
        rejects(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0]));
        rejects(Uint8List.sublistView(ok, 0, ok.length - 5));
        rejects(Uint8List.fromList(ok)..[20] ^= 1);
      });

      test('too many pixels, checked before inflating', () {
        rejects(buildPng(5, 5, 8, 6, [], zlib: []), 24);
      });

      test('more image data than the size allows (zip bomb)', () {
        rejects(buildPng(1, 1, 8, 6, [],
            zlib: ZLibEncoder().convert(Uint8List(1 << 20))));
      });

      test('interlaced, bad filter, palette errors', () {
        rejects(buildPng(
            1,
            1,
            8,
            6,
            [
              [1, 2, 3, 4]
            ],
            interlace: 1));
        rejects(buildPng(1, 1, 8, 6, [],
            zlib: ZLibEncoder().convert([9, 1, 2, 3, 4])));
        rejects(buildPng(1, 1, 8, 3, [
          [5]
        ], plte: [
          1,
          2,
          3
        ]));
        rejects(buildPng(1, 1, 8, 3, [
          [0]
        ]));
        rejects(buildPng(1, 1, 8, 6, [], zlib: [1, 2, 3]));
      });
    });
  });
}
