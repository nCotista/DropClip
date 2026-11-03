import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

import 'dib_test.dart' show makeDib;

void main() {
  group('encodeDibV5 (T1.8, §11.2 PNG → Windows)', () {
    test('writes a 32 bpp BI_BITFIELDS V5 header with an alpha mask', () {
      final dib = encodeDibV5(RgbaImage(3, 2, Uint8List(24),
          xPixelsPerMetre: 3780, yPixelsPerMetre: 3780));
      final d = ByteData.sublistView(dib);
      int u32(int o) => d.getUint32(o, Endian.little);
      expect(dib.length, 124 + 3 * 2 * 4);
      expect(
          [u32(0), d.getInt32(4, Endian.little), d.getInt32(8, Endian.little)],
          [124, 3, 2]);
      expect([d.getUint16(12, Endian.little), d.getUint16(14, Endian.little)],
          [1, 32]);
      expect([u32(16), u32(20), u32(24), u32(28)], [3, 24, 3780, 3780]);
      expect([u32(40), u32(44), u32(48), u32(52)],
          [0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000]);
      expect([u32(56), u32(108)], [0x73524742, 4]);
    });

    test('stores rows bottom-up as BGRA', () {
      final dib = encodeDibV5(RgbaImage(
          1,
          2,
          Uint8List.fromList([
            1, 2, 3, 4, // top
            5, 6, 7, 8, // bottom
          ])));
      expect(dib.sublist(124), [7, 6, 5, 8, 3, 2, 1, 4]);
    });

    test('50 images survive Windows → wire PNG → Windows unchanged', () {
      // Lossless both ways, so every pixel matches (SSIM = 1.0 ≥ 0.99,
      // NFR-RE01). Sizes include odd widths and single rows/columns.
      final rnd = Random(29);
      for (var n = 0; n < 50; n++) {
        final w = 1 + rnd.nextInt(n.isEven ? 40 : 300);
        final h = 1 + rnd.nextInt(n.isEven ? 300 : 40);
        final alpha = n % 3; // 0 opaque, 1 partial, 2 binary transparency
        final px = [
          for (var i = 0; i < w * h; i++)
            [
              rnd.nextInt(256),
              rnd.nextInt(256),
              rnd.nextInt(256),
              // Pixel 0 stays opaque: an image whose alpha is all zero is
              // read as opaque on Windows (decodeDib), by design.
              i == 0 || alpha == 0
                  ? 255
                  : (alpha == 1
                      ? rnd.nextInt(256)
                      : (rnd.nextBool() ? 0 : 255)),
            ],
        ];
        final source =
            makeDib(w, h, px, header: 124, bitfields: true, bottomUp: n.isOdd);
        final back = decodeDib(pngToDibV5(dibToPng(source)));
        expect([back.width, back.height], [w, h], reason: 'image $n');
        expect(back.pixels, [for (final p in px) ...p], reason: 'image $n');
      }
    });

    test('keeps DPI from the PNG', () {
      final png = encodePng(RgbaImage(1, 1, Uint8List(4),
          xPixelsPerMetre: 5669, yPixelsPerMetre: 5669));
      final d = ByteData.sublistView(pngToDibV5(png));
      expect(d.getInt32(24, Endian.little), 5669);
    });

    test('a malformed PNG throws NormalizationException', () {
      expect(() => pngToDibV5(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<NormalizationException>()));
    });

    test('4K PNG converts (NFR-P05 timing printed)', () {
      final px = Uint8List(3840 * 2160 * 4);
      for (var i = 0; i < px.length; i++) {
        px[i] = (i * 31) >> 4;
      }
      final png = encodePng(RgbaImage(3840, 2160, px));
      final sw = Stopwatch()..start();
      final dib = pngToDibV5(png);
      sw.stop();
      // ignore: avoid_print
      print('4K PNG → CF_DIBV5: ${sw.elapsedMilliseconds} ms (JIT)');
      expect(dib.length, 124 + px.length);
    });
  });
}
