import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'dib.dart' show NormalizationException;
import 'png_encoder.dart';

/// macOS `public.tiff` → RGBA (FR-06, PROTO-DC-V2.0 §11.2). A TIFF can hold
/// several images (Retina and non-Retina); the one with the most pixels is
/// used, at full size. Supports strips of 8/16-bit grey or RGB with an
/// optional alpha (premultiplied alpha is undone), uncompressed. [maxPixels]
/// is checked before any pixel data is read (§11.3).
RgbaImage decodeTiff(Uint8List tiff,
    {int maxPixels = ProtocolConstants.imageMaxPixels}) {
  if (tiff.length < 8) throw const NormalizationException('not a TIFF');
  final Endian e;
  if (tiff[0] == 0x49 && tiff[1] == 0x49) {
    e = Endian.little;
  } else if (tiff[0] == 0x4D && tiff[1] == 0x4D) {
    e = Endian.big;
  } else {
    throw const NormalizationException('not a TIFF');
  }
  final d = ByteData.sublistView(tiff);
  if (d.getUint16(2, e) != 42) throw const NormalizationException('not a TIFF');

  final ifds = <Map<int, List<int>>>[];
  final seen = <int>{};
  for (var off = d.getUint32(4, e); off != 0 && seen.add(off);) {
    if (off + 2 > tiff.length) throw const NormalizationException('bad IFD');
    final n = d.getUint16(off, e);
    if (off + 2 + n * 12 + 4 > tiff.length) {
      throw const NormalizationException('bad IFD');
    }
    final tags = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      final p = off + 2 + i * 12;
      tags[d.getUint16(p, e)] = _values(d, e, p);
    }
    ifds.add(tags);
    off = d.getUint32(off + 2 + n * 12, e);
  }
  int pixels(Map<int, List<int>> t) =>
      (t[256]?.first ?? 0) * (t[257]?.first ?? 0);
  ifds.sort((a, b) => pixels(b).compareTo(pixels(a)));
  if (ifds.isEmpty || pixels(ifds.first) == 0) {
    throw const NormalizationException('no image in TIFF');
  }
  return _decodeIfd(tiff, ifds.first, maxPixels);
}

/// `tiffToPng`: macOS clipboard TIFF → canonical wire PNG (§11.2).
Uint8List tiffToPng(Uint8List tiff) => encodePng(decodeTiff(tiff));

const _typeSizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8};

/// The values of one IFD entry. RATIONALs are returned as [num, den].
List<int> _values(ByteData d, Endian e, int p) {
  final type = d.getUint16(p + 2, e), count = d.getUint32(p + 4, e);
  final size = _typeSizes[type];
  if (size == null) return const [];
  final inline = size * count <= 4;
  final at = inline ? p + 8 : d.getUint32(p + 8, e);
  if (count > 1 << 24 || at + size * count > d.lengthInBytes) {
    throw const NormalizationException('bad TIFF tag');
  }
  return [
    for (var i = 0; i < count; i++)
      ...switch (type) {
        3 => [d.getUint16(at + 2 * i, e)],
        4 => [d.getUint32(at + 4 * i, e)],
        5 => [d.getUint32(at + 8 * i, e), d.getUint32(at + 8 * i + 4, e)],
        _ => [d.getUint8(at + i)],
      },
  ];
}

RgbaImage _decodeIfd(Uint8List tiff, Map<int, List<int>> t, int maxPixels) {
  int one(int tag, int fallback) => t[tag]?.first ?? fallback;
  final w = one(256, 0), h = one(257, 0);
  if (w * h > maxPixels) throw NormalizationException('too large: ${w}x$h');
  final spp = one(277, 1), bits = t[258] ?? const [1];
  final depth = bits.first, photometric = one(262, -1);
  final compression = one(259, 1);
  if (t.containsKey(322)) throw const NormalizationException('tiled TIFF');
  if (one(284, 1) != 1) throw const NormalizationException('planar TIFF');
  if ((depth != 8 && depth != 16) || bits.any((b) => b != depth)) {
    throw NormalizationException('unsupported $depth-bit TIFF');
  }
  final colour = photometric == 2 ? 3 : 1;
  if ((photometric != 2 && photometric > 1) || spp < colour) {
    throw NormalizationException('unsupported photometric $photometric');
  }
  final hasAlpha = spp > colour;
  final premultiplied = hasAlpha && (t[338]?.first ?? 2) == 1;

  final bpp = spp * depth ~/ 8, stride = w * bpp;
  final raw = Uint8List(stride * h);
  final offsets = t[273] ?? const [], counts = t[279] ?? const [];
  final rowsPerStrip = one(278, h).clamp(1, h);
  if (offsets.length != counts.length || offsets.isEmpty) {
    throw const NormalizationException('bad strips');
  }
  for (var s = 0; s < offsets.length; s++) {
    final start = s * rowsPerStrip * stride;
    if (start >= raw.length) break;
    final size = (raw.length - start).clamp(0, rowsPerStrip * stride);
    if (offsets[s] + counts[s] > tiff.length) {
      throw const NormalizationException('strip past end of data');
    }
    final data =
        Uint8List.sublistView(tiff, offsets[s], offsets[s] + counts[s]);
    raw.setRange(start, start + size, _strip(compression, data, size));
  }

  final out = Uint8List(w * h * 4);
  // Big-endian 16-bit samples keep the first byte, little-endian the second.
  final hi = depth == 16 && tiff[0] == 0x49 ? 1 : 0;
  for (var p = 0; p < w * h; p++) {
    int s(int n) => raw[p * bpp + n * depth ~/ 8 + hi];
    final o = p * 4;
    var r = s(0), g = colour == 3 ? s(1) : r, b = colour == 3 ? s(2) : r;
    if (photometric == 0) (r, g, b) = (255 - r, 255 - g, 255 - b);
    final a = hasAlpha ? s(colour) : 255;
    if (premultiplied && a > 0 && a < 255) {
      int un(int c) => ((c * 255 + a ~/ 2) ~/ a).clamp(0, 255);
      (r, g, b) = (un(r), un(g), un(b));
    }
    out
      ..[o] = r
      ..[o + 1] = g
      ..[o + 2] = b
      ..[o + 3] = a;
  }
  return RgbaImage(w, h, out,
      xPixelsPerMetre: _ppm(t[282], one(296, 2)),
      yPixelsPerMetre: _ppm(t[283], one(296, 2)));
}

Uint8List _strip(int compression, Uint8List data, int size) {
  switch (compression) {
    case 1:
      if (data.length < size) throw const NormalizationException('strip short');
      return data;
  }
  throw NormalizationException('unsupported compression $compression');
}

int _ppm(List<int>? rational, int unit) {
  if (rational == null || rational.length < 2 || rational[1] == 0) return 0;
  final perUnit = rational[0] / rational[1];
  final ppm =
      switch (unit) { 2 => perUnit / 0.0254, 3 => perUnit * 100, _ => 0 };
  return ppm.round().clamp(0, 1 << 30);
}
