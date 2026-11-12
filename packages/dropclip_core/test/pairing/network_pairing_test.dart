import 'dart:convert';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

typedef _Node = ({DeviceIdentityManager ids, TrustedDeviceStore store});

Future<_Node> _node(String name) async {
  final dir = await Directory.systemTemp.createTemp('dc_net_pair_');
  addTearDown(() => dir.delete(recursive: true));
  final keys = InMemorySecureKeyStore();
  final ids = DeviceIdentityManager(storageDir: dir, keyStore: keys);
  await ids.loadOrCreate(deviceName: name, os: 'windows');
  final store = TrustedDeviceStore(
      storageDir: Directory('${dir.path}/trust'), keyStore: keys);
  await store.load();
  return (ids: ids, store: store);
}

void main() {
  late _Node host, client;
  late PairingHost pairing;
  late TlsTransportServer server;
  late String pin;
  late Map<String, dynamic> qr;

  setUp(() async {
    host = await _node('Host PC');
    client = await _node('Client PC');
    late TlsTransportServer s;
    pairing = PairingHost(
      engine: PairingEngine(
          hostIdentity: host.ids.identity, trustedStore: host.store),
      store: host.store,
      onPaired: (d) => s.addTrustedPeerCert(d.certPem!),
    );
    server = s = await TlsTransportServer.bindForIdentity(
      identity: host.ids,
      store: host.store,
      pinnedHandler: (_) => Response.ok('pinned'),
      pairingHandler: pairing.handler,
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0,
    );
    addTearDown(() => server.close(force: true));
    final session = pairing.open(ip: '127.0.0.1', port: server.port);
    pin = session.pin;
    qr = session.qr.toJson();
  });

  Future<TrustedDevice> pair({
    required String typedPin,
    required bool hostSaysMatch,
    List<String>? sasSeen,
  }) {
    final sub = pairing.events.listen((e) {
      if (e is PairingSasReady) {
        sasSeen?.add(e.sas);
        pairing.confirm(hostSaysMatch);
      }
    });
    addTearDown(sub.cancel);
    return PairingClient.pairWithPin(
      host: '127.0.0.1',
      port: server.port,
      pin: typedPin,
      me: client.ids.identity,
      store: client.store,
      expectedHostFp: host.ids.identity.fp,
      confirmSas: (sas, hostName) async {
        sasSeen?.add(sas);
        expect(hostName, 'Host PC');
        return true;
      },
    );
  }

  test('PIN pairing stores both sides, then mTLS works with no restart',
      () async {
    final sas = <String>[];
    final done = pairing.events.firstWhere((e) => e is PairingCompleted);
    final hostRecord =
        await pair(typedPin: pin, hostSaysMatch: true, sasSeen: sas);
    await done;

    expect(sas, hasLength(2));
    expect(sas[0], sas[1]);
    expect(hostRecord.fp, host.ids.identity.fp);
    expect(client.store.isActiveFingerprint(host.ids.identity.fp), isTrue);
    expect(host.store.isActiveFingerprint(client.ids.identity.fp), isTrue);

    final pinned = await PinnedTransportClient.forIdentity(
        identity: client.ids,
        store: client.store,
        expectedFp: host.ids.identity.fp);
    addTearDown(pinned.close);
    final req = await pinned.httpClient
        .getUrl(Uri.parse('https://127.0.0.1:${server.port}/api/v1/info'));
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(await utf8.decoder.bind(res).join(), 'pinned');
  });

  test('wrong PIN gives different SAS; nothing is stored', () async {
    final wrong = pin == '000000' ? '111111' : '000000';
    final sas = <String>[];
    await expectLater(
      pair(typedPin: wrong, hostSaysMatch: false, sasSeen: sas),
      throwsA(isA<PairingClientException>()
          .having((e) => e.code, 'code', 'E_SAS_FAILED')),
    );
    expect(sas[0], isNot(sas[1]));
    expect(client.store.activeDevices, isEmpty);
    expect(host.store.activeDevices, isEmpty);
  });

  test('Host refuses a cert that does not match the claimed fp', () async {
    final other = await _node('Other');
    final res = await pairing.handler(Request(
      'POST',
      Uri.parse('https://127.0.0.1/api/v1/pair'),
      body: jsonEncode({
        'fp': client.ids.identity.fp,
        'cert': base64Encode(other.ids.identity.certDer),
      }),
    ));
    expect(res.statusCode, 401);
    expect(await res.readAsString(), contains('E_PAIRING_INVALID'));
  });

  test('QR pairing pins the fp from the code and stores both sides', () async {
    final sas = <String>[];
    pairing.events.listen((e) {
      if (e is PairingSasReady) {
        sas.add(e.sas);
        pairing.confirm(true);
      }
    });
    final done = pairing.events.firstWhere((e) => e is PairingCompleted);
    await PairingClient.pairWithQr(
        qr: qr,
        me: client.ids.identity,
        store: client.store,
        confirmSas: (s, _) async {
          sas.add(s);
          return true;
        });
    await done;
    expect(sas[0], sas[1]);
    expect(host.store.isActiveFingerprint(client.ids.identity.fp), isTrue);
  });

  test('a QR whose fp is not the Host cert never connects', () async {
    await expectLater(
        PairingClient.pairWithQr(
            qr: {...qr, 'fp': 'a' * 64},
            me: client.ids.identity,
            store: client.store,
            confirmSas: (_, __) async => true),
        throwsA(anything));
    expect(client.store.activeDevices, isEmpty);
  });
}
