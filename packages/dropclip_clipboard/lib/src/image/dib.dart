import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'png_encoder.dart';

/// Malformed or unsupported image input (PROTO-DC-V2.0 §11.3): callers drop
/// the clip; the app must never crash or run out of memory.
class NormalizationException implements Exception {
  final String message;
  const NormalizationException(this.message);
  @override
  String toString() => 'NormalizationException: $message';
}

const int _biRgb = 0, _biBitfields = 3;

/// Decodes a Windows `CF_DIB` / `CF_DIBV5` payload (BITMAPINFOHEADER,
/// V4 or V5 header + pixels, no file header) to RGBA (FR-06, §11.2):
/// BGR(A) → RGBA, bottom-up → top-down, alpha kept from `bV5AlphaMask`;
/// with no alpha, pixels are opaque. Supports 24/32 bpp, `BI_RGB` and
/// `BI_BITFIELDS` — what Windows puts on the clipboard for screenshots.
RgbaImage decodeDib(Uint8List dib,
    {int maxPixels = ProtocolConstants.imageMaxPixels}) {
  if (dib.length < 40) throw const NormalizationException('header too short');
  final d = ByteData.sublistView(dib);
  final headerSize = d.getUint32(0, Endian.little);
  if (headerSize != 40 && headerSize != 108 && headerSize != 124) {
    throw NormalizationException('unknown header size $headerSize');
  }
  if (dib.length < headerSize) {
    throw const NormalizationException('header truncated');
  }
  final width = d.getInt32(4, Endian.little);
  final rawHeight = d.getInt32(8, Endian.little);
  final bitCount = d.getUint16(14, Endian.little);
  final compression = d.getUint32(16, Endian.little);
  final height = rawHeight.abs();
  if (width <= 0 || height == 0) {
    throw NormalizationException('bad size ${width}x$rawHeight');
  }
  // §11.3: refuse decompression bombs before allocating anything.
  if (width * height > maxPixels) {
    throw NormalizationException('too large: ${width}x$height');
  }
  if (bitCount != 24 && bitCount != 32) {
    throw NormalizationException('unsupported $bitCount bpp');
  }
  if (compression != _biRgb &&
      !(compression == _biBitfields && bitCount == 32)) {
    throw NormalizationException('unsupported compression $compression');
  }

  // Channel masks: V4/V5 carry them in the header; a 40-byte header with
  // BI_BITFIELDS is followed by three DWORD masks (no alpha mask).
  var masks = (r: 0x00FF0000, g: 0x0000FF00, b: 0x000000FF, a: 0);
  var pixelOffset = headerSize;
  if (compression == _biBitfields) {
    if (headerSize == 40) {
      if (dib.length < 52) throw const NormalizationException('no masks');
      masks = (
        r: d.getUint32(40, Endian.little),
        g: d.getUint32(44, Endian.little),
        b: d.getUint32(48, Endian.little),
        a: 0,
      );
      pixelOffset = 52;
    } else {
      masks = (
        r: d.getUint32(40, Endian.little),
        g: d.getUint32(44, Endian.little),
        b: d.getUint32(48, Endian.little),
        a: d.getUint32(52, Endian.little),
      );
    }
  } else if (bitCount == 32 && headerSize > 40) {
    masks =
        (r: masks.r, g: masks.g, b: masks.b, a: d.getUint32(52, Endian.little));
  }

  final stride = ((width * bitCount + 31) ~/ 32) * 4;
  if (dib.length < pixelOffset + stride * height) {
    throw const NormalizationException('pixel data truncated');
  }
  final bottomUp = rawHeight > 0;
  final out = Uint8List(width * height * 4);
  final bpp = bitCount ~/ 8;
  var anyAlpha = false;
  // BI_RGB 32 bpp: the 4th byte is "reserved" but often carries alpha.
  final alpha = masks.a != 0
      ? _Channel(masks.a)
      : (compression == _biRgb ? _Channel(0xFF000000) : null);
  // Windows screenshots are BGRA bytes: copy them without bit fiddling.
  final bgra = bitCount == 32 &&
      masks.r == 0xFF0000 &&
      masks.g == 0xFF00 &&
      masks.b == 0xFF &&
      (alpha == null || alpha.mask == 0xFF000000);
  final r = _Channel(masks.r), g = _Channel(masks.g), b = _Channel(masks.b);

  for (var y = 0; y < height; y++) {
    final src = pixelOffset + (bottomUp ? height - 1 - y : y) * stride;
    var o = y * width * 4;
    var p = src;
    for (var x = 0; x < width; x++, o += 4, p += bpp) {
      if (bitCount == 24) {
        out[o] = dib[p + 2];
        out[o + 1] = dib[p + 1];
        out[o + 2] = dib[p];
        out[o + 3] = 255;
      } else if (bgra) {
        out[o] = dib[p + 2];
        out[o + 1] = dib[p + 1];
        out[o + 2] = dib[p];
        final a = alpha == null ? 255 : dib[p + 3];
        out[o + 3] = a;
        if (a != 0) anyAlpha = true;
      } else {
        final v = d.getUint32(p, Endian.little);
        out[o] = r.of(v);
        out[o + 1] = g.of(v);
        out[o + 2] = b.of(v);
        final a = alpha == null ? 255 : alpha.of(v);
        out[o + 3] = a;
        if (a != 0) anyAlpha = true;
      }
    }
  }
  // A 32 bpp DIB whose alpha bytes are all zero has no alpha at all (many
  // apps leave the byte unused); show it opaque, not invisible.
  if (bitCount == 32 && !anyAlpha) {
    for (var i = 3; i < out.length; i += 4) {
      out[i] = 255;
    }
  }

  return RgbaImage(width, height, out,
      xPixelsPerMetre: d.getInt32(24, Endian.little).clamp(0, 1 << 30),
      yPixelsPerMetre: d.getInt32(28, Endian.little).clamp(0, 1 << 30));
}

/// A bit-field channel; shift and width are worked out once per image.
class _Channel {
  final int mask, shift, bits;

  factory _Channel(int mask) {
    if (mask == 0) return const _Channel._(0, 0, 0);
    var shift = 0;
    while ((mask >> shift) & 1 == 0) {
      shift++;
    }
    return _Channel._(mask, shift, (mask >> shift).bitLength);
  }

  const _Channel._(this.mask, this.shift, this.bits);

  /// The channel of [value], scaled to 8 bits.
  int of(int value) {
    if (bits == 0) return 0;
    final v = (value & mask) >> shift;
    return bits >= 8 ? v >> (bits - 8) : (v * 255) ~/ ((1 << bits) - 1);
  }
}

/// `CF_DIB` / `CF_DIBV5` → canonical PNG for the wire (§11.2).
Uint8List dibToPng(Uint8List dib) => encodePng(decodeDib(dib));
