import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

class _TestCertBundle {
  final Uint8List certPem;
  final Uint8List keyPem;
  final String fingerprint;

  const _TestCertBundle({
    required this.certPem,
    required this.keyPem,
    required this.fingerprint,
  });
}

Future<_TestCertBundle> _generateP256SelfSigned(
  Directory dir,
  String deviceId,
) async {
  final keyFile = File('${dir.path}/$deviceId.k');
  final certFile = File('${dir.path}/$deviceId.crt');
  final derFile = File('${dir.path}/$deviceId.der');

  final reqRes = await Process.run('openssl', [
    'req',
    '-x509',
    '-newkey',
    'ec',
    '-pkeyopt',
    'ec_paramgen_curve:prime256v1',
    '-nodes',
    '-keyout',
    keyFile.path,
    '-out',
    certFile.path,
    '-days',
    '3650',
    '-subj',
    '/CN=dropclip-$deviceId',
  ]);
  if (reqRes.exitCode != 0) {
    throw StateError('openssl req failed: ${reqRes.stderr}');
  }

  final derRes = await Process.run('openssl', [
    'x509',
    '-in',
    certFile.path,
    '-outform',
    'DER',
    '-out',
    derFile.path,
  ]);
  if (derRes.exitCode != 0) {
    throw StateError('openssl x509 DER failed: ${derRes.stderr}');
  }

  final certPem = await certFile.readAsBytes();
  final keyPem = await keyFile.readAsBytes();
  final derBytes = await derFile.readAsBytes();
  final fp = sha256.convert(derBytes).toString();

  await keyFile.delete();
  await certFile.delete();
  await derFile.delete();

  return _TestCertBundle(certPem: certPem, keyPem: keyPem, fingerprint: fp);
}

void main() {
  group('S0.1 Spike: Cross-Platform ECDSA P-256 mTLS 1.3 & Pinning Matrix', () {
    late Directory tempDir;
    late _TestCertBundle hostCert;
    late _TestCertBundle trustedClientCert;
    late _TestCertBundle rogueClientCert;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('dropclip_s01_');
      hostCert = await _generateP256SelfSigned(
        tempDir,
        '550e8400-e29b-41d4-a716-446655440000',
      );
      trustedClientCert = await _generateP256SelfSigned(
        tempDir,
        'b2c3d4e5-6a7b-8c9d-0e1f-2a3b4c5d6e7f',
      );
      rogueClientCert = await _generateP256SelfSigned(
        tempDir,
        '99999999-0000-4000-8000-000000000000',
      );
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Mutual TLS 1.3 succeeds for pinned ECDSA P-256 client & server',
        () async {
      final trustedFingerprints = <String>{trustedClientCert.fingerprint};
      final serverCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(hostCert.certPem)
        ..usePrivateKeyBytes(hostCert.keyPem)
        ..setTrustedCertificatesBytes(trustedClientCert.certPem);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverCtx,
        requestClientCertificate: true,
      );
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        final clientCert = req.certificate;
        final clientFp = clientCert == null
            ? null
            : sha256.convert(clientCert.der).toString();
        if (req.uri.path.startsWith('/api/v1/pair')) {
          req.response
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode({'status': 'pair_endpoint_ok'}));
          await req.response.close();
          return;
        }
        if (clientFp == null || !trustedFingerprints.contains(clientFp)) {
          const err = ProtocolException(
            ProtocolErrorCode.notPaired,
            'client certificate not in trusted store',
          );
          req.response
            ..statusCode = err.httpStatus
            ..write(jsonEncode(err.toHttpJson()));
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'verified_fp': clientFp}));
        await req.response.close();
      });

      final clientCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(trustedClientCert.certPem)
        ..usePrivateKeyBytes(trustedClientCert.keyPem);
      final httpClient = HttpClient(context: clientCtx)
        ..badCertificateCallback = (cert, host, port) =>
            sha256.convert(cert.der).toString() == hostCert.fingerprint;
      addTearDown(() => httpClient.close(force: true));

      final req = await httpClient.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/api/v1/info'),
      );
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();
      expect(resp.statusCode, HttpStatus.ok);
      expect(
        (jsonDecode(body) as Map)['verified_fp'],
        trustedClientCert.fingerprint,
      );
    });

    test('Rejects untrusted/rogue client certificate & revoked fingerprint',
        () async {
      final trustedFingerprints = <String>{trustedClientCert.fingerprint};
      final serverCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(hostCert.certPem)
        ..usePrivateKeyBytes(hostCert.keyPem)
        ..setTrustedCertificatesBytes(trustedClientCert.certPem);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverCtx,
        requestClientCertificate: true,
      );
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        final clientCert = req.certificate;
        final clientFp = clientCert == null
            ? null
            : sha256.convert(clientCert.der).toString();
        if (clientFp == null || !trustedFingerprints.contains(clientFp)) {
          req.response
            ..statusCode = HttpStatus.forbidden
            ..write(
              jsonEncode(
                const ProtocolException(
                  ProtocolErrorCode.notPaired,
                  'E_NOT_PAIRED',
                ).toHttpJson(),
              ),
            );
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..write('ok');
        await req.response.close();
      });

      // 1. Rogue client presenting unpinned self-signed cert is rejected at TLS handshake
      final rogueCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(rogueClientCert.certPem)
        ..usePrivateKeyBytes(rogueClientCert.keyPem);
      final rogueClient = HttpClient(context: rogueCtx)
        ..badCertificateCallback = (cert, host, port) =>
            sha256.convert(cert.der).toString() == hostCert.fingerprint;
      addTearDown(() => rogueClient.close(force: true));

      await expectLater(
        () async {
          final r = await rogueClient.getUrl(
            Uri.parse('https://127.0.0.1:${server.port}/api/v1/info'),
          );
          await r.close();
        }(),
        throwsA(isA<IOException>()),
      );

      // 2. Revoking trustedClientCert in application store immediately returns 403 E_NOT_PAIRED (§4.4)
      trustedFingerprints.remove(trustedClientCert.fingerprint);
      final revokedClientCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(trustedClientCert.certPem)
        ..usePrivateKeyBytes(trustedClientCert.keyPem);
      final revokedClient = HttpClient(context: revokedClientCtx)
        ..badCertificateCallback = (cert, host, port) =>
            sha256.convert(cert.der).toString() == hostCert.fingerprint;
      addTearDown(() => revokedClient.close(force: true));

      final req = await revokedClient.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/api/v1/info'),
      );
      final resp = await req.close();
      await resp.drain<void>();
      expect(resp.statusCode, HttpStatus.forbidden);
    });

    test(
        'Rejects server with mismatched fingerprint in client pinning callback',
        () async {
      final serverCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(hostCert.certPem)
        ..usePrivateKeyBytes(hostCert.keyPem);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverCtx,
      );
      addTearDown(() => server.close(force: true));
      server.listen((req) => req.response.close());

      final client = HttpClient(
          context: SecurityContext(withTrustedRoots: false))
        ..badCertificateCallback = (cert, host, port) =>
            sha256.convert(cert.der).toString() == rogueClientCert.fingerprint;
      addTearDown(() => client.close(force: true));

      await expectLater(
        () async {
          final r = await client.getUrl(
            Uri.parse('https://127.0.0.1:${server.port}/api/v1/pair'),
          );
          await r.close();
        }(),
        throwsA(isA<HandshakeException>()),
      );
    });
  });
}
