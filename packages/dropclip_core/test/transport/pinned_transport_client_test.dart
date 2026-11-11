import 'dart:convert';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/test_certs.dart';

void main() {
  late Directory tmp;
  late TestCert host;
  late TestCert me;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('dc_t14c_');
    host = await generateTestCert(tmp, 'host');
    me = await generateTestCert(tmp, 'me');
  });

  tearDownAll(() => tmp.delete(recursive: true));

  Future<TlsTransportServer> serve() async {
    final server = await TlsTransportServer.bind(
      context: buildTls13Context(
        certPem: host.certPem,
        keyPem: host.keyPem,
        trustedPeerCertsPem: [me.certPem],
      ),
      isTrusted: {me.fp}.contains,
      pinnedHandler: (_) => Response.ok('pinned'),
      pairingHandler: (_) => Response.ok('pairing'),
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0,
    );
    addTearDown(() => server.close(force: true));
    return server;
  }

  PinnedTransportClient paired({String? expectedFp, Set<String>? trusted}) {
    final c = PinnedTransportClient.paired(
      certPem: me.certPem,
      keyPem: me.keyPem,
      isTrusted: (trusted ?? {host.fp}).contains,
      expectedFp: expectedFp,
    );
    addTearDown(() => c.close(force: true));
    return c;
  }

  Future<(int, String)> send(
    PinnedTransportClient c,
    int port,
    String path, {
    String method = 'GET',
  }) async {
    final req = await c.httpClient
        .openUrl(method, Uri.parse('https://127.0.0.1:$port$path'));
    final resp = await req.close();
    return (resp.statusCode, await utf8.decoder.bind(resp).join());
  }

  test('paired client reaches pinned endpoint (expected fp, any case)',
      () async {
    final server = await serve();
    final c = paired(expectedFp: host.fp.toUpperCase(), trusted: {});
    expect(await send(c, server.port, '/api/v1/info'), (200, 'pinned'));
  });

  test('without expected fp the trusted store decides', () async {
    final server = await serve();
    expect(await send(paired(), server.port, '/api/v1/info'), (200, 'pinned'));
    await expectLater(
      send(paired(trusted: {}), server.port, '/api/v1/info'),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('server with a different fingerprint is rejected', () async {
    final server = await serve();
    await expectLater(
      send(paired(expectedFp: me.fp), server.port, '/api/v1/info'),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('pairing client sends no cert: pair OK, pinned endpoints 403', () async {
    final server = await serve();
    final c = PinnedTransportClient.pairing(expectedFp: host.fp);
    addTearDown(() => c.close(force: true));
    expect(
      await send(c, server.port, '/api/v1/pair', method: 'POST'),
      (200, 'pairing'),
    );
    final (status, body) = await send(c, server.port, '/api/v1/info');
    expect(status, 403);
    expect(body, contains('E_NOT_PAIRED'));
    expect(c.verifyServer(me.fp), isFalse);
  });

  test('connectWebSocket opens wss through the pinned client', () async {
    final raw = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      buildTls13Context(
        certPem: host.certPem,
        keyPem: host.keyPem,
        trustedPeerCertsPem: [me.certPem],
      ),
      requestClientCertificate: true,
    );
    addTearDown(() => raw.close(force: true));
    raw.listen((req) async {
      final fp = certificateFingerprint(req.certificate!);
      final ws = await WebSocketTransformer.upgrade(req);
      ws.add(fp);
      await ws.close();
    });
    final ws = await paired()
        .connectWebSocket(Uri.parse('wss://127.0.0.1:${raw.port}/api/v1/ws'));
    addTearDown(ws.close);
    expect(await ws.first, me.fp);
  });

  test('forIdentity and bindForIdentity pin each other end to end', () async {
    Future<(DeviceIdentityManager, TrustedDeviceStore)> device(
      String name,
    ) async {
      final keys = InMemorySecureKeyStore();
      final dir = await tmp.createTemp(name);
      final id = DeviceIdentityManager(storageDir: dir, keyStore: keys);
      await id.loadOrCreate(deviceName: name, os: 'linux');
      return (id, TrustedDeviceStore(storageDir: dir, keyStore: keys));
    }

    Future<void> trust(TrustedDeviceStore store, DeviceIdentity peer) =>
        store.upsert(TrustedDevice(
          deviceId: peer.deviceId,
          name: peer.name,
          os: peer.os,
          tier: 1,
          fp: peer.fp,
          certPem: peer.certPem,
          pairedAt: 0,
          lastSeenAt: 0,
        ));

    final (hostId, hostStore) = await device('h');
    final (clientId, clientStore) = await device('c');
    await trust(hostStore, clientId.identity);
    await trust(clientStore, hostId.identity);

    final server = await TlsTransportServer.bindForIdentity(
      identity: hostId,
      store: hostStore,
      pinnedHandler: (r) =>
          Response.ok(r.context[kPeerFingerprintContextKey] as String),
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0,
    );
    addTearDown(() => server.close(force: true));
    expect(server.address, InternetAddress.loopbackIPv4);

    final c = await PinnedTransportClient.forIdentity(
      identity: clientId,
      store: clientStore,
    );
    addTearDown(() => c.close(force: true));
    expect(
      await send(c, server.port, '/api/v1/info'),
      (200, clientId.identity.fp),
    );
  });
}
