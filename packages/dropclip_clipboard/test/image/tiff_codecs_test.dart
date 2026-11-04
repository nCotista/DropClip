import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

import 'tiff_decoder_test.dart' show Img, buildTiff;

/// PackBits with literal runs of one byte, plus one repeat run when the
/// first two bytes match.
List<int> packBits(List<int> rows) => [
      if (rows.length > 1 && rows[0] == rows[1]) ...[-1 & 0xFF, rows[0]],
      for (final b in rows
          .skip(rows.length > 1 && rows[0] == rows[1] ? 2 : 0)) ...[0, b],
    ];

List<int> predict(List<int> rows, int bpp, int stride) => [
      for (var i = 0; i < rows.length; i++)
        i % stride < bpp ? rows[i] : (rows[i] - rows[i - bpp]) & 0xFF,
    ];

void main() {
  final rgba = [
    for (var i = 0; i < 6; i++) ...[i * 40, 255 - i * 40, i * 7, 255],
  ];

  group('TIFF strip codecs (T1.8)', () {
    test('Deflate, with and without the horizontal predictor', () {
      for (final p in [1, 2]) {
        final tiff = buildTiff([Img(3, 2, rgba, compression: 8, predictor: p)],
            encode: (img, rows) => ZLibEncoder()
                .convert(p == 2 ? predict(rows, 4, img.w * 4) : rows));
        expect(decodeTiff(tiff).pixels, rgba, reason: 'predictor $p');
      }
    });

    test('PackBits literal and repeat runs, in two strips', () {
      final px = [7, 7, 7, 7, ...rgba.sublist(4)];
      final tiff = buildTiff(
          [Img(3, 2, px, compression: 32773, rowsPerStrip: 1)],
          encode: (_, rows) => packBits(rows));
      expect(decodeTiff(tiff).pixels, px);
    });

    test('LZW from the Windows TIFF encoder (GDI+), alpha kept', () {
      final img = decodeTiff(
          File('test/image/fixtures/windows_lzw_rgba.tif').readAsBytesSync());
      expect([img.width, img.height], [23, 17]);
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 23; x++) {
          final o = (y * 23 + x) * 4, a = (x * 11 + y * 3) % 256;
          final expected = a == 0
              ? [img.pixels[o], img.pixels[o + 1], img.pixels[o + 2], 0]
              : [(x * 9) % 256, (y * 13) % 256, ((x + y) * 5) % 256, a];
          expect(img.pixels.sublist(o, o + 4), expected, reason: '($x, $y)');
        }
      }
    });

    group('rejects with NormalizationException (§11.3)', () {
      void rejects(Img img) => expect(() => decodeTiff(buildTiff([img])),
          throwsA(isA<NormalizationException>()));

      test('Deflate that inflates past the image (zip bomb) or is corrupt', () {
        final bomb = ZLibEncoder().convert(Uint8List(1 << 20));
        rejects(Img(3, 2, rgba, compression: 8, strip: bomb));
        rejects(Img(3, 2, rgba, compression: 8, strip: [1, 2]));
      });

      test('LZW that is corrupt, too long or too short', () {
        rejects(Img(3, 2, rgba, compression: 5, strip: [0xFF, 0xFF, 0xFF]));
        // Clear, then the literal 0 repeated far past 24 bytes, no EOI.
        final long = [0x80, ...List.filled(200, 0)];
        rejects(Img(3, 2, rgba, compression: 5, strip: long));
        rejects(Img(3, 2, rgba, compression: 5, strip: [0x80, 0x00, 0x60]));
      });

      test('PackBits too short, and a 16-bit predictor', () {
        rejects(Img(3, 2, rgba, compression: 32773, strip: [5]));
        rejects(Img(1, 1, [1, 2, 3, 4, 5, 6], spp: 3, depth: 16, predictor: 2));
      });
    });
  });
}
