import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// 8-bit RGBA pixels, top-down rows, 4 bytes per pixel.
class RgbaImage {
  final int width;
  final int height;
  final Uint8List pixels;

  /// Pixels per metre from the source, kept in the PNG `pHYs` chunk so DPI
  /// survives the trip (PROTO-DC-V2.0 §11.1). 0 = unknown.
  final int xPixelsPerMetre;
  final int yPixelsPerMetre;

  RgbaImage(this.width, this.height, this.pixels,
      {this.xPixelsPerMetre = 0, this.yPixelsPerMetre = 0})
      : assert(pixels.length == width * height * 4);
}

const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Encodes [image] as a truecolour-with-alpha PNG (the canonical wire
/// format, §11.1). Fast zlib level by default: clipboard images go over a
/// LAN, so encode time (NFR-P05) matters more than a few percent of size.
Uint8List encodePng(RgbaImage image, {int level = 1, bool upFilter = true}) {
  final w = image.width, h = image.height, stride = w * 4;
  final px = image.pixels;
  // Each row starts with its filter type. "Up" (2) stores the difference to
  // the row above: screenshots repeat a lot vertically, so this compresses
  // better and faster. The first row has no row above and uses None (0).
  final raw = Uint8List((stride + 1) * h);
  for (var y = 0; y < h; y++) {
    final o = y * (stride + 1), s = y * stride;
    if (!upFilter || y == 0) {
      raw.setRange(o + 1, o + 1 + stride, px, s);
      continue;
    }
    raw[o] = 2;
    for (var i = 0; i < stride; i++) {
      raw[o + 1 + i] = px[s + i] - px[s - stride + i];
    }
  }

  final out = BytesBuilder(copy: false)..add(pngSignature);
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // colour type: RGBA; compression/filter/interlace = 0
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  if (image.xPixelsPerMetre > 0 && image.yPixelsPerMetre > 0) {
    final phys = ByteData(9)
      ..setUint32(0, image.xPixelsPerMetre)
      ..setUint32(4, image.yPixelsPerMetre)
      ..setUint8(8, 1); // unit: metre
    _chunk(out, 'pHYs', phys.buffer.asUint8List());
  }
  _chunk(out, 'IDAT', ZLibEncoder(level: level).convert(raw));
  _chunk(out, 'IEND', const []);
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final typeBytes = type.codeUnits;
  out
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(typeBytes)
    ..add(data);
  var crc = _crcUpdate(0xFFFFFFFF, typeBytes);
  crc = _crcUpdate(crc, data) ^ 0xFFFFFFFF;
  out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crcUpdate(int crc, List<int> bytes) {
  var c = crc;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c;
}

/// CRC-32 as used by PNG (exposed for tests).
int pngCrc32(List<int> bytes) => _crcUpdate(0xFFFFFFFF, bytes) ^ 0xFFFFFFFF;
