import 'dart:typed_data';

import 'png_decoder.dart';
import 'png_encoder.dart';

const _v5HeaderSize = 124;
const _biBitfields = 3;
const _lcsSrgb = 0x73524742; // 'sRGB'
const _lcsGmImages = 4; // perceptual rendering intent

/// RGBA → Windows `CF_DIBV5` (PROTO-DC-V2.0 §11.2): BITMAPV5HEADER, 32 bpp,
/// `BI_BITFIELDS` with an alpha mask, sRGB, rows bottom-up as most Windows
/// apps expect. Alpha is straight (not premultiplied), the same convention
/// `decodeDib` reads, so an image survives the trip unchanged.
Uint8List encodeDibV5(RgbaImage image) {
  final w = image.width, h = image.height, px = image.pixels;
  final out = Uint8List(_v5HeaderSize + w * h * 4);
  ByteData.sublistView(out)
    ..setUint32(0, _v5HeaderSize, Endian.little)
    ..setInt32(4, w, Endian.little)
    ..setInt32(8, h, Endian.little) // positive height = bottom-up
    ..setUint16(12, 1, Endian.little) // planes
    ..setUint16(14, 32, Endian.little)
    ..setUint32(16, _biBitfields, Endian.little)
    ..setUint32(20, w * h * 4, Endian.little)
    ..setInt32(24, image.xPixelsPerMetre, Endian.little)
    ..setInt32(28, image.yPixelsPerMetre, Endian.little)
    ..setUint32(40, 0x00FF0000, Endian.little) // red mask
    ..setUint32(44, 0x0000FF00, Endian.little) // green mask
    ..setUint32(48, 0x000000FF, Endian.little) // blue mask
    ..setUint32(52, 0xFF000000, Endian.little) // alpha mask
    ..setUint32(56, _lcsSrgb, Endian.little)
    ..setUint32(108, _lcsGmImages, Endian.little);

  final stride = w * 4;
  for (var y = 0; y < h; y++) {
    var s = y * stride;
    var o = _v5HeaderSize + (h - 1 - y) * stride;
    for (var x = 0; x < w; x++, s += 4, o += 4) {
      out[o] = px[s + 2]; // B
      out[o + 1] = px[s + 1]; // G
      out[o + 2] = px[s]; // R
      out[o + 3] = px[s + 3]; // A
    }
  }
  return out;
}

/// Wire PNG → `CF_DIBV5` for the Windows clipboard. Per §11.2 the app also
/// puts the PNG bytes on the clipboard unchanged under the registered `PNG`
/// format, so apps that read PNG get the original.
Uint8List pngToDibV5(Uint8List png) => encodeDibV5(decodePng(png));
