import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

const red = [255, 0, 0, 255], clear = [10, 20, 30, 0];
const half = [200, 100, 50, 128], blue = [0, 0, 255, 255];
const white = [255, 255, 255, 255], green = [0, 255, 0, 255];

RgbaImage image3x2({int ppm = 0}) => RgbaImage(
    3,
    2,
    Uint8List.fromList(
        [...red, ...clear, ...half, ...blue, ...white, ...green]),
    xPixelsPerMetre: ppm,
    yPixelsPerMetre: ppm);

/// Chunks of [png] by type, checking every CRC on the way.
Map<String, Uint8List> chunksOf(Uint8List png) {
  final d = ByteData.sublistView(png);
  final chunks = <String, Uint8List>{};
  for (var o = 8; o < png.length;) {
    final len = d.getUint32(o);
    final type = String.fromCharCodes(png.sublist(o + 4, o + 8));
    expect(d.getUint32(o + 8 + len), pngCrc32(png.sublist(o + 4, o + 8 + len)),
        reason: '$type CRC');
    chunks[type] = png.sublist(o + 8, o + 8 + len);
    o += 12 + len;
  }
  return chunks;
}

void main() {
  group('encodePng (T1.8, PROTO-DC-V2.0 §11.1)', () {
    test('CRC-32 matches the PNG reference value', () {
      expect(pngCrc32('IEND'.codeUnits), 0xAE426082);
    });

    test('signature, chunk order, IHDR and pHYs (DPI kept)', () {
      final png = encodePng(image3x2(ppm: 3780));
      expect(png.sublist(0, 8), pngSignature);
      final chunks = chunksOf(png);
      expect(chunks.keys, ['IHDR', 'pHYs', 'IDAT', 'IEND']);
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
      final phys = ByteData.sublistView(chunks['pHYs']!);
      expect([phys.getUint32(0), phys.getUint32(4), phys.getUint8(8)],
          [3780, 3780, 1]);
    });

    test('Up filter rows decode back to the exact pixels', () {
      final raw =
          ZLibDecoder().convert(chunksOf(encodePng(image3x2()))['IDAT']!);
      expect(raw, hasLength((3 * 4 + 1) * 2));
      expect([raw[0], raw[13]], [0, 2]); // None, then Up
      final row0 = raw.sublist(1, 13);
      expect(row0, [...red, ...clear, ...half]);
      // Undo Up: each byte plus the byte above, mod 256.
      final row1 = [
        for (var i = 0; i < 12; i++) (raw[14 + i] + row0[i]) & 0xFF
      ];
      expect(row1, [...blue, ...white, ...green]);
    });

    test('without the filter rows are stored as-is', () {
      final raw = ZLibDecoder()
          .convert(chunksOf(encodePng(image3x2(), upFilter: false))['IDAT']!);
      expect([raw[0], raw[13]], [0, 0]);
      expect(raw.sublist(14), [...blue, ...white, ...green]);
    });

    test('no pHYs when DPI is unknown; 1x1 works', () {
      final png = encodePng(RgbaImage(1, 1, Uint8List.fromList(red)));
      expect(chunksOf(png).keys, ['IHDR', 'IDAT', 'IEND']);
    });
  });
}
