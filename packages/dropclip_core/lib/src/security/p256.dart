import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// ECDSA P-256 keys, self-signed X.509 certificates and signatures in pure
/// Dart (§4.1, ADR-006), so no device needs the `openssl` CLI.
///
/// Keys are PKCS#8 PEM (§4.2) and certificates are X.509 v3 with a 16-byte
/// random serial and `CN=dropclip-<device_id>` — both load straight into a
/// Dart `SecurityContext` for TLS 1.3.
class P256 {
  P256._();

  static final _curve = ECCurve_prime256v1();

  static const _oidEcPublicKey = [1, 2, 840, 10045, 2, 1];
  static const _oidPrime256v1 = [1, 2, 840, 10045, 3, 1, 7];
  static const _oidEcdsaSha256 = [1, 2, 840, 10045, 4, 3, 2];
  static const _oidCommonName = [2, 5, 4, 3];

  /// A new key pair and a certificate for [commonName], valid from [now]
  /// for [validity] (10 years per §4.1).
  static ({Uint8List certDer, Uint8List certPem, Uint8List keyPem}) generate({
    required String commonName,
    DateTime? now,
    Duration validity = const Duration(days: 3650),
  }) {
    final rng = Random.secure();
    final random = FortunaRandom()
      ..seed(KeyParameter(
          Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)))));
    final pair = (ECKeyGenerator()
          ..init(
              ParametersWithRandom(ECKeyGeneratorParameters(_curve), random)))
        .generateKeyPair();
    final private = pair.privateKey;
    final public = pair.publicKey.Q!.getEncoded(false);

    final start = (now ?? DateTime.now()).toUtc();
    final name = _seq([
      _set([
        _seq([_oid(_oidCommonName), _tlv(0x0c, utf8.encode(commonName))])
      ])
    ]);
    final serial = List<int>.generate(16, (_) => rng.nextInt(256));
    serial[0] &= 0x7f; // positive INTEGER
    final tbs = _seq([
      _tlv(0xa0, _tlv(0x02, [2])), // v3
      _tlv(0x02, serial),
      _seq([_oid(_oidEcdsaSha256)]),
      name,
      _seq([_time(start), _time(start.add(validity))]),
      name,
      _spki(public),
    ]);
    final sig = _signDer(private.d!, tbs);
    final der = _seq([
      tbs,
      _seq([_oid(_oidEcdsaSha256)]),
      _tlv(0x03, [0, ...sig]),
    ]);
    final pkcs8 = _seq([
      _tlv(0x02, [0]),
      _seq([_oid(_oidEcPublicKey), _oid(_oidPrime256v1)]),
      _tlv(
          0x04,
          _seq([
            _tlv(0x02, [1]),
            _tlv(0x04, _fixed32(private.d!)),
            _tlv(0xa1, _tlv(0x03, [0, ...public])),
          ])),
    ]);
    return (
      certDer: der,
      certPem: _pem('CERTIFICATE', der),
      keyPem: _pem('PRIVATE KEY', pkcs8),
    );
  }

  /// ECDSA-SHA256 signature (DER `SEQUENCE {r, s}`) of [message] with the
  /// PKCS#8 key from [generate].
  static Uint8List sign(Uint8List keyPem, List<int> message) =>
      _signDer(_privateScalar(keyPem), message);

  /// Whether [signatureDer] is a valid signature of [message] by the key in
  /// [certPem]. Malformed input returns false.
  static bool verify(Uint8List certPem, List<int> message, List<int> sigDer) {
    try {
      final q = _curve.curve.decodePoint(_publicKeyOf(_unpem(certPem)));
      final rs = _Der(sigDer).children(_Der(sigDer).read(0x30));
      final signature = ECSignature(_int(rs[0]), _int(rs[1]));
      final verifier = ECDSASigner(SHA256Digest())
        ..init(false, PublicKeyParameter(ECPublicKey(q, _curve)));
      return verifier.verifySignature(Uint8List.fromList(message), signature);
    } on Object {
      return false;
    }
  }

  static Uint8List _signDer(BigInt d, List<int> message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter(ECPrivateKey(d, _curve)));
    final s =
        signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
    return _seq([_tlv(0x02, _intBytes(s.r)), _tlv(0x02, _intBytes(s.s))]);
  }

  static BigInt _privateScalar(Uint8List keyPem) {
    final der = _unpem(keyPem);
    final outer = _Der(der).children(_Der(der).read(0x30));
    final sec1 = _Der(outer[2]).read(0x04);
    final fields = _Der(sec1).children(_Der(sec1).read(0x30));
    return _Der(fields[1])
        .read(0x04)
        .fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));
  }

  /// The uncompressed EC point in the certificate's SubjectPublicKeyInfo.
  static Uint8List _publicKeyOf(Uint8List certDer) {
    final cert = _Der(certDer).children(_Der(certDer).read(0x30));
    final tbs = _Der(cert[0]).children(_Der(cert[0]).read(0x30));
    final spki = tbs[tbs[0][0] == 0xa0 ? 6 : 5];
    final bits = _Der(spki).children(_Der(spki).read(0x30))[1];
    return _Der(bits).read(0x03).sublist(1);
  }

  static Uint8List _spki(Uint8List point) => _seq([
        _seq([_oid(_oidEcPublicKey), _oid(_oidPrime256v1)]),
        _tlv(0x03, [0, ...point]),
      ]);

  // --- DER encoding -------------------------------------------------------

  static Uint8List _tlv(int tag, List<int> value) {
    final n = value.length;
    final len = n < 0x80
        ? [n]
        : n < 0x100
            ? [0x81, n]
            : [0x82, n >> 8, n & 0xff];
    return Uint8List.fromList([tag, ...len, ...value]);
  }

  static Uint8List _seq(List<List<int>> items) =>
      _tlv(0x30, [for (final i in items) ...i]);

  static Uint8List _set(List<List<int>> items) =>
      _tlv(0x31, [for (final i in items) ...i]);

  static Uint8List _oid(List<int> arcs) {
    final out = <int>[arcs[0] * 40 + arcs[1]];
    for (final arc in arcs.skip(2)) {
      final b = <int>[arc & 0x7f];
      for (var v = arc >> 7; v > 0; v >>= 7) {
        b.insert(0, 0x80 | (v & 0x7f));
      }
      out.addAll(b);
    }
    return _tlv(0x06, out);
  }

  /// UTCTime until 2049, GeneralizedTime after (RFC 5280 §4.1.2.5).
  static Uint8List _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final rest =
        '${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
    return t.year < 2050
        ? _tlv(0x17, ascii.encode('${two(t.year % 100)}$rest'))
        : _tlv(0x18, ascii.encode('${t.year}$rest'));
  }

  static List<int> _intBytes(BigInt v) {
    final b = _unsigned(v);
    return b[0] & 0x80 != 0 ? [0, ...b] : b;
  }

  static List<int> _fixed32(BigInt v) {
    final b = _unsigned(v);
    return [...List<int>.filled(32 - b.length, 0), ...b];
  }

  static List<int> _unsigned(BigInt v) {
    final hex = v.toRadixString(16);
    final even = hex.length.isOdd ? '0$hex' : hex;
    return [
      for (var i = 0; i < even.length; i += 2)
        int.parse(even.substring(i, i + 2), radix: 16)
    ];
  }

  static BigInt _int(Uint8List tlv) {
    final v = _Der(tlv).read(0x02);
    return v.fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));
  }

  static Uint8List _pem(String label, List<int> der) {
    final b64 = base64Encode(der);
    final lines = [
      for (var i = 0; i < b64.length; i += 64)
        b64.substring(i, min(i + 64, b64.length))
    ];
    return Uint8List.fromList(ascii.encode(
        '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n'));
  }

  static Uint8List _unpem(Uint8List pem) {
    final text = ascii.decode(pem).replaceAll(RegExp(r'-----[^-]+-----'), '');
    return base64Decode(text.replaceAll(RegExp(r'\s'), ''));
  }
}

/// Minimal DER reader: one TLV at the start of [_bytes].
class _Der {
  final List<int> _bytes;

  _Der(this._bytes);

  ({int tag, int start, int end}) _header(int at) {
    final tag = _bytes[at];
    var len = _bytes[at + 1];
    var start = at + 2;
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | _bytes[start + i];
      }
      start += n;
    }
    if (start + len > _bytes.length) {
      throw const FormatException('DER length past end');
    }
    return (tag: tag, start: start, end: start + len);
  }

  /// The value of the first TLV, which must have [tag].
  Uint8List read(int tag) {
    final h = _header(0);
    if (h.tag != tag) throw FormatException('expected DER tag $tag');
    return Uint8List.fromList(_bytes.sublist(h.start, h.end));
  }

  /// Every TLV (header included) inside [value].
  List<Uint8List> children(Uint8List value) {
    final out = <Uint8List>[];
    final inner = _Der(value);
    for (var at = 0; at < value.length;) {
      final h = inner._header(at);
      out.add(Uint8List.fromList(value.sublist(at, h.end)));
      at = h.end;
    }
    return out;
  }
}
