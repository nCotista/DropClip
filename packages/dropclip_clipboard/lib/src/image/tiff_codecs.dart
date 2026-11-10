import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'dib.dart' show NormalizationException;

/// Decodes one TIFF strip to exactly [size] bytes: uncompressed (1), LZW
/// (5), Deflate (8, 32946) or PackBits (32773) — what macOS and Windows
/// write for clipboard images. Output never grows past [size], so a small
/// strip cannot expand into gigabytes (§11.3).
Uint8List decodeTiffStrip(int compression, Uint8List data, int size) {
  switch (compression) {
    case 1:
      if (data.length < size) throw const NormalizationException('strip short');
      return data;
    case 5:
      return _lzw(data, size);
    case 8 || 32946:
      return _inflate(data, size);
    case 32773:
      return _unpackBits(data, size);
  }
  throw NormalizationException('unsupported compression $compression');
}

/// Undoes TIFF predictor 2 (horizontal differencing) on 8-bit samples.
void undoTiffPredictor(Uint8List raw, int stride, int bpp) {
  for (var row = 0; row < raw.length; row += stride) {
    for (var i = row + bpp; i < row + stride; i++) {
      raw[i] = (raw[i] + raw[i - bpp]) & 0xFF;
    }
  }
}

/// TIFF LZW: MSB-first codes of 9–12 bits, Clear = 256, EOI = 257, the
/// code width grows one code early (as libtiff and Windows write it).
Uint8List _lzw(Uint8List data, int size) {
  final out = Uint8List(size);
  final prefix = Int32List(4096), length = Int32List(4096);
  final suffix = Uint8List(4096), first = Uint8List(4096);
  for (var i = 0; i < 256; i++) {
    suffix[i] = first[i] = i;
    length[i] = 1;
  }
  var o = 0, bit = 0, width = 9, next = 258, old = -1;
  final bits = data.length * 8;

  void emit(int code) {
    final n = length[code];
    if (o + n > size) throw const NormalizationException('strip too long');
    for (var k = n - 1, c = code; k >= 0; k--, c = prefix[c]) {
      out[o + k] = suffix[c];
    }
    o += n;
  }

  while (bit + width <= bits) {
    var code = 0;
    for (var k = 0; k < width; k++, bit++) {
      code = code << 1 | (data[bit >> 3] >> (7 - (bit & 7))) & 1;
    }
    if (code == 257) break;
    if (code == 256) {
      (next, width, old) = (258, 9, -1);
      continue;
    }
    if (old == -1) {
      if (code > 255) throw const NormalizationException('corrupt LZW strip');
    } else {
      if (code > next) throw const NormalizationException('corrupt LZW strip');
      if (next < 4096) {
        prefix[next] = old;
        suffix[next] = code < next ? first[code] : first[old];
        first[next] = first[old];
        length[next] = length[old] + 1;
        next++;
        if (next >= (1 << width) - 1 && width < 12) width++;
      }
    }
    emit(code);
    old = code;
  }
  if (o != size) throw const NormalizationException('strip short');
  return out;
}

Uint8List _inflate(Uint8List data, int size) {
  final out = Uint8List(size);
  var n = 0;
  final sink = ZLibDecoder().startChunkedConversion(_Collect((chunk) {
    if (n + chunk.length > size) {
      throw const NormalizationException('strip too long');
    }
    out.setRange(n, n + chunk.length, chunk);
    n += chunk.length;
  }));
  try {
    sink
      ..add(data)
      ..close();
  } on FormatException {
    throw const NormalizationException('corrupt strip');
  }
  if (n != size) throw const NormalizationException('strip short');
  return out;
}

Uint8List _unpackBits(Uint8List data, int size) {
  final out = Uint8List(size);
  var i = 0, o = 0;
  while (o < size && i < data.length) {
    final n = data[i++].toSigned(8);
    if (n >= 0) {
      if (i + n + 1 > data.length || o + n + 1 > size) break;
      out.setRange(o, o + n + 1, data, i);
      i += n + 1;
      o += n + 1;
    } else if (n != -128) {
      if (i >= data.length || o - n + 1 > size) break;
      out.fillRange(o, o - n + 1, data[i++]);
      o += 1 - n;
    }
  }
  if (o != size) throw const NormalizationException('bad PackBits strip');
  return out;
}

class _Collect implements Sink<List<int>> {
  final void Function(List<int>) _add;

  _Collect(this._add);

  @override
  void add(List<int> chunk) => _add(chunk);

  @override
  void close() {}
}
