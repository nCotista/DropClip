import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'dib.dart' show NormalizationException;
import 'png_encoder.dart';

/// Wire PNG (FR-06, §11) → 8-bit RGBA, e.g. for Windows `CF_DIBV5`. Every
/// non-interlaced colour type and depth; 16-bit keeps the high byte. Checks
/// the signature, chunk CRCs and [maxPixels] before inflating (§11.3).
RgbaImage decodePng(Uint8List png,
    {int maxPixels = ProtocolConstants.imageMaxPixels}) {
  for (var i = 0; i < 8; i++) {
    if (png.length < 8 || png[i] != pngSignature[i]) {
      throw const NormalizationException('not a PNG');
    }
  }
  final d = ByteData.sublistView(png);
  _Header? h;
  Uint8List? palette, trns;
  var xPpm = 0, yPpm = 0;
  final idat = BytesBuilder(copy: false);
  var pos = 8;
  var ended = false;
  while (!ended) {
    if (pos + 12 > png.length) throw const NormalizationException('truncated');
    final len = d.getUint32(pos);
    if (len > png.length - pos - 12) {
      throw const NormalizationException('chunk past end of data');
    }
    final type = String.fromCharCodes(png, pos + 4, pos + 8);
    final body = Uint8List.sublistView(png, pos + 8, pos + 8 + len);
    if (pngCrc32(Uint8List.sublistView(png, pos + 4, pos + 8 + len)) !=
        d.getUint32(pos + 8 + len)) {
      throw NormalizationException('bad CRC in $type');
    }
    pos += 12 + len;
    if (h == null && type != 'IHDR') {
      throw const NormalizationException('IHDR must come first');
    }
    switch (type) {
      case 'IHDR':
        h = _Header.parse(body, maxPixels);
      case 'PLTE':
        palette = body;
      case 'tRNS':
        trns = body;
      case 'pHYs' when len == 9 && body[8] == 1:
        xPpm = ByteData.sublistView(body).getUint32(0);
        yPpm = ByteData.sublistView(body).getUint32(4);
      case 'IDAT':
        idat.add(body);
      case 'IEND':
        ended = true;
    }
  }
  final hdr = h!;
  if (hdr.colourType == 3 && palette == null) {
    throw const NormalizationException('palette image without PLTE');
  }

  final stride = (hdr.width * hdr.bitsPerPixel + 7) >> 3;
  final raw = _inflate(idat.takeBytes(), (stride + 1) * hdr.height);
  _unfilter(raw, stride, hdr.height, (hdr.bitsPerPixel + 7) >> 3);

  final out = Uint8List(hdr.width * hdr.height * 4);
  for (var y = 0; y < hdr.height; y++) {
    final row = y * (stride + 1) + 1, o = y * hdr.width * 4;
    if (hdr.colourType == 6 && hdr.depth == 8) {
      out.setRange(o, o + stride, raw, row); // the usual case: a plain copy
      continue;
    }
    for (var x = 0; x < hdr.width; x++) {
      _pixel(hdr, raw, row, x, palette, trns, out, o + x * 4);
    }
  }
  return RgbaImage(hdr.width, hdr.height, out,
      xPixelsPerMetre: xPpm.clamp(0, 1 << 30),
      yPixelsPerMetre: yPpm.clamp(0, 1 << 30));
}

class _Header {
  final int width, height, depth, colourType;

  _Header(this.width, this.height, this.depth, this.colourType);

  static const _channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4};
  static const _depths = {
    0: [1, 2, 4, 8, 16],
    2: [8, 16],
    3: [1, 2, 4, 8],
    4: [8, 16],
    6: [8, 16],
  };

  factory _Header.parse(Uint8List b, int maxPixels) {
    if (b.length != 13) throw const NormalizationException('bad IHDR');
    final d = ByteData.sublistView(b);
    final w = d.getUint32(0), h = d.getUint32(4);
    final depth = b[8], type = b[9];
    if (w == 0 || h == 0) throw NormalizationException('bad size ${w}x$h');
    if (w * h > maxPixels) throw NormalizationException('too large: ${w}x$h');
    if (!(_depths[type]?.contains(depth) ?? false)) {
      throw NormalizationException('bad colour type $type / depth $depth');
    }
    if (b[10] != 0 || b[11] != 0) {
      throw const NormalizationException('unknown compression or filter');
    }
    if (b[12] != 0) throw const NormalizationException('interlaced PNG');
    return _Header(w, h, depth, type);
  }

  int get bitsPerPixel => _channels[colourType]! * depth;
}

/// Inflates exactly [size] bytes. Stops as soon as the stream would grow
/// past it, so a small PNG cannot expand into gigabytes (§11.3).
Uint8List _inflate(Uint8List compressed, int size) {
  final out = Uint8List(size);
  var filled = 0;
  final inflater = ZLibDecoder().startChunkedConversion(_CappedSink((chunk) {
    if (filled + chunk.length > size) {
      throw const NormalizationException('image data too long');
    }
    out.setRange(filled, filled + chunk.length, chunk);
    filled += chunk.length;
  }));
  try {
    inflater
      ..add(compressed)
      ..close();
  } on FormatException {
    throw const NormalizationException('corrupt image data');
  }
  if (filled != size) throw const NormalizationException('image data short');
  return out;
}

class _CappedSink implements Sink<List<int>> {
  final void Function(List<int>) _onChunk;
  _CappedSink(this._onChunk);

  @override
  void add(List<int> chunk) => _onChunk(chunk);

  @override
  void close() {}
}

/// Reverses the per-row filters in place (PNG spec §9).
void _unfilter(Uint8List raw, int stride, int height, int bpp) {
  for (var y = 0; y < height; y++) {
    final f = y * (stride + 1), row = f + 1, up = row - stride - 1;
    final type = raw[f];
    for (var i = 0; i < stride; i++) {
      final a = i >= bpp ? raw[row + i - bpp] : 0;
      final b = y > 0 ? raw[up + i] : 0;
      final c = y > 0 && i >= bpp ? raw[up + i - bpp] : 0;
      final add = switch (type) {
        0 => 0,
        1 => a,
        2 => b,
        3 => (a + b) >> 1,
        4 => _paeth(a, b, c),
        _ => throw NormalizationException('bad filter $type'),
      };
      raw[row + i] = (raw[row + i] + add) & 0xFF;
    }
  }
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

void _pixel(_Header h, Uint8List raw, int row, int x, Uint8List? palette,
    Uint8List? trns, Uint8List out, int o) {
  final depth = h.depth, max = (1 << depth) - 1;
  // Sample n at its full depth.
  int full(int n) {
    final p = row + (x * h.bitsPerPixel >> 3) + n * depth ~/ 8;
    if (depth == 16) return raw[p] << 8 | raw[p + 1];
    if (depth == 8) return raw[p];
    final bit = x * depth;
    return (raw[row + (bit >> 3)] >> (8 - depth - (bit & 7))) & max;
  }

  // Scaled to 8 bits; 16-bit keeps its high byte.
  int s(int n) => depth == 16 ? full(n) >> 8 : full(n) * 255 ~/ max;
  // tRNS colour key for grey/RGB, compared at full depth.
  bool keyed(int samples) {
    if (trns == null || trns.length < 2 * samples) return false;
    final k = ByteData.sublistView(trns);
    for (var i = 0; i < samples; i++) {
      if (k.getUint16(2 * i) != full(i)) return false;
    }
    return true;
  }

  void put(int r, int g, int b, int a) => out
    ..[o] = r
    ..[o + 1] = g
    ..[o + 2] = b
    ..[o + 3] = a;

  switch (h.colourType) {
    case 0:
      put(s(0), s(0), s(0), keyed(1) ? 0 : 255);
    case 2:
      put(s(0), s(1), s(2), keyed(3) ? 0 : 255);
    case 3:
      final i = full(0);
      if (3 * i + 2 >= palette!.length) {
        throw NormalizationException('palette index $i out of range');
      }
      put(palette[3 * i], palette[3 * i + 1], palette[3 * i + 2],
          trns != null && i < trns.length ? trns[i] : 255);
    case 4:
      put(s(0), s(0), s(0), s(1));
    case 6:
      put(s(0), s(1), s(2), s(3));
  }
}
