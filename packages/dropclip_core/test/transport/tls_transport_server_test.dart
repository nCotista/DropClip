import 'dart:convert';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/test_certs.dart';

void main() {
  late Directory tmp;
  late TestCert host;
  late TestCert peer;
  late TestCert rogue;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('dc_t14_');
    host = await generateTestCert(tmp, 'host');
    peer = await generateTestCert(tmp, 'peer');
    rogue = await generateTestCert(tmp, 'rogue');
  });

  tearDownAll(() => tmp.delete(recursive: true));

  /// Client pinned to [host]; presents [as] as its client cert when given.
  HttpClient client({TestCert? as}) {
    final ctx = SecurityContext(withTrustedRoots: false);
    if (as != null) {
      ctx
        ..useCertificateChainBytes(as.certPem)
        ..usePrivateKeyBytes(as.keyPem);
    }
    final c = HttpClient(context: ctx)
      ..badCertificateCallback =
          (cert, _, __) => certificateFingerprint(cert) == host.fp;
    addTearDown(() => c.close(force: true));
    return c;
  }

  Future<(int, String, HttpHeaders)> get(
    HttpClient c,
    int port,
    String path, {
    String method = 'GET',
  }) async {
    final req =
        await c.openUrl(method, Uri.parse('https://127.0.0.1:$port$path'));
    final resp = await req.close();
    return (
      resp.statusCode,
      await utf8.decoder.bind(resp).join(),
      resp.headers,
    );
  }

  Future<TlsTransportServer> serve({
    Set<String>? trusted,
    Handler? pairing,
    int first = 0,
    int last = 0,
  }) async {
    final fps = trusted ?? {peer.fp};
    final server = await TlsTransportServer.bind(
      context: buildTls13Context(
        certPem: host.certPem,
        keyPem: host.keyPem,
        trustedPeerCertsPem: [peer.certPem],
      ),
      isTrusted: fps.contains,
      pinnedHandler: (r) =>
          Response.ok(r.context[kPeerFingerprintContextKey] as String),
      pairingHandler: pairing,
      address: InternetAddress.loopbackIPv4,
      firstPort: first,
      lastPort: last,
    );
    addTearDown(() => server.close(force: true));
    return server;
  }

  test('pinned peer reaches handler with its fingerprint, no-store', () async {
    final server = await serve();
    final (status, body, headers) =
        await get(client(as: peer), server.port, '/api/v1/info');
    expect(status, 200);
    expect(body, peer.fp);
    expect(headers.value('cache-control'), 'no-store');
  });

  test('request without client cert gets 403 E_NOT_PAIRED', () async {
    final server = await serve();
    final (status, body, _) = await get(client(), server.port, '/api/v1/info');
    expect(status, 403);
    expect((jsonDecode(body) as Map)['error']['code'], 'E_NOT_PAIRED');
  });

  test('revoked fingerprint still handshakes but gets 403', () async {
    final trusted = {peer.fp};
    final server = await serve(trusted: trusted);
    trusted.clear();
    final (status, body, _) =
        await get(client(as: peer), server.port, '/api/v1/ws');
    expect(status, 403);
    expect(body, contains('E_NOT_PAIRED'));
  });

  test('unknown client cert is refused at the TLS handshake', () async {
    final server = await serve();
    await expectLater(
      get(client(as: rogue), server.port, '/api/v1/info'),
      throwsA(isA<IOException>()),
    );
  });

  test('pairing paths accept no client cert; 404 without handler', () async {
    final withPairing = await serve(
      pairing: (r) => Response.ok('pair:${r.requestedUri.path}'),
    );
    for (final path in kPairingPaths) {
      final (status, body, _) =
          await get(client(), withPairing.port, path, method: 'POST');
      expect(status, 200);
      expect(body, 'pair:$path');
    }
    final noPairing = await serve();
    final (status, _, _) =
        await get(client(), noPairing.port, '/api/v1/pair', method: 'POST');
    expect(status, 404);
  });

  test('peer trusted after bind can connect without restart', () async {
    final trusted = {peer.fp};
    final server = await serve(trusted: trusted);
    server.addTrustedPeerCert(rogue.certPem);
    trusted.add(rogue.fp);
    final (status, body, _) =
        await get(client(as: rogue), server.port, '/api/v1/info');
    expect(status, 200);
    expect(body, rogue.fp);
  });

  test('port auto-shifts to the next free port and fails when full', () async {
    final first = await serve();
    final shifted = await serve(first: first.port, last: first.port + 1);
    expect(shifted.port, first.port + 1);
    await expectLater(
      serve(first: first.port, last: first.port + 1),
      throwsA(isA<TransportBindException>()
          .having((e) => e.toString(), 'message', contains('no free port'))),
    );
  });

  test('default range is 53317-53417', () async {
    final server = await serve(
      first: kTransportPortFirst,
      last: kTransportPortLast,
    );
    expect(server.port, inInclusiveRange(53317, 53417));
  });

  test('TLS 1.2 is rejected, TLS 1.3 is accepted (downgrade)', () async {
    final server = await serve();
    Future<ProcessResult> sClient(String version) async {
      final p = await Process.start('openssl', [
        's_client', '-connect', '127.0.0.1:${server.port}', version, //
      ]);
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      await p.stderr.drain<void>();
      return ProcessResult(p.pid, await p.exitCode, out, '');
    }

    final tls12 = await sClient('-tls1_2');
    expect(tls12.exitCode, isNot(0));
    final tls13 = await sClient('-tls1_3');
    expect(tls13.stdout as String, contains('TLSv1.3'));
  });
}
