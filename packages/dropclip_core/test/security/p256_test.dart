import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

SecurityContext _ctx(
        ({Uint8List certDer, Uint8List certPem, Uint8List keyPem}) id) =>
    SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
      ..useCertificateChainBytes(id.certPem)
      ..usePrivateKeyBytes(id.keyPem);

void main() {
  group('P256 (T1.2, §4.1, no openssl)', () {
    final host = P256.generate(commonName: 'dropclip-host');
    final peer = P256.generate(commonName: 'dropclip-peer');

    test('PEM is PKCS#8 key and X.509 cert matching the DER', () {
      expect(ascii.decode(host.keyPem), startsWith('-----BEGIN PRIVATE KEY'));
      final pem = ascii.decode(host.certPem);
      final body = pem
          .replaceAll(RegExp(r'-----[^-]+-----'), '')
          .replaceAll(RegExp(r'\s'), '');
      expect(base64Decode(body), host.certDer);
    });

    Future<String> handshake({required bool serverTrustsPeer}) async {
      final ctx = _ctx(host);
      if (serverTrustsPeer) ctx.setTrustedCertificatesBytes(peer.certPem);
      final server = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4, 0, ctx,
          requestClientCertificate: true);
      addTearDown(server.close);
      server.listen((s) {
        s.write(sha256.convert(s.peerCertificate!.der).toString());
        s.close();
      }, onError: (_) {});
      String? seenServerFp;
      try {
        final socket = await SecureSocket.connect(
          InternetAddress.loopbackIPv4,
          server.port,
          context: _ctx(peer),
          onBadCertificate: (c) {
            seenServerFp = sha256.convert(c.der).toString();
            return true;
          },
        );
        expect(seenServerFp, sha256.convert(host.certDer).toString());
        return await utf8.decoder.bind(socket).join();
      } on IOException {
        return '';
      }
    }

    test('mTLS 1.3 handshake pins both fingerprints', () async {
      expect(await handshake(serverTrustsPeer: true),
          sha256.convert(peer.certDer).toString());
    });

    // Why pairing must hand the host the client's cert (not just its fp).
    test('server refuses a client cert it was not given', () async {
      expect(await handshake(serverTrustsPeer: false), isEmpty);
    });

    test('sign/verify round trip; tampering and wrong key fail', () {
      final msg = utf8.encode('revoke:550e8400');
      final sig = P256.sign(host.keyPem, msg);
      expect(P256.verify(host.certPem, msg, sig), isTrue);
      expect(P256.verify(peer.certPem, msg, sig), isFalse);
      expect(P256.verify(host.certPem, utf8.encode('revoke:x'), sig), isFalse);
      expect(P256.verify(host.certPem, msg, [1, 2, 3]), isFalse);
    });

    test('every generated cert loads into BoringSSL (DER integers)', () {
      for (var i = 0; i < 400; i++) {
        final id = P256.generate(commonName: 'dropclip-$i');
        expect(() => _ctx(id), returnsNormally, reason: 'cert #$i');
        final msg = [i];
        expect(P256.verify(id.certPem, msg, P256.sign(id.keyPem, msg)), isTrue);
      }
    });

    test('every certificate has a fresh key and serial', () {
      final again = P256.generate(commonName: 'dropclip-host');
      expect(again.certDer, isNot(host.certDer));
      expect(again.keyPem, isNot(host.keyPem));
    });
  });
}
