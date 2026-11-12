import 'dart:async';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _Node {
  late final DeviceIdentityManager ids;
  late final TrustedDeviceStore store;
  late final PeerMesh mesh;
  TlsTransportServer? _server;
  TlsTransportServer get server => _server!;

  String get id => ids.identity.deviceId;

  static Future<_Node> start(String name) async {
    final n = _Node();
    final dir = await Directory.systemTemp.createTemp('dc_mesh_');
    final keys = InMemorySecureKeyStore();
    n.ids = DeviceIdentityManager(storageDir: dir, keyStore: keys);
    await n.ids.loadOrCreate(deviceName: name, os: 'windows');
    n.store = TrustedDeviceStore(
        storageDir: Directory('${dir.path}/t'), keyStore: keys);
    n.mesh = PeerMesh(
      identity: n.ids,
      store: n.store,
      hello: () => HelloPayload(
          deviceId: n.id,
          name: name,
          os: 'windows',
          tier: 1,
          appVersion: 'test',
          capabilities: const ['clip.text'],
          tombstonesHash: '',
          tombstoneCount: 0),
    );
    addTearDown(() async {
      await n.mesh.close();
      await n._server?.close(force: true);
      await dir.delete(recursive: true);
    });
    return n;
  }

  Future<void> listen() async => _server = await TlsTransportServer.bind(
        context: buildTls13Context(
            certPem: ids.identity.certPem,
            keyPem: await ids.loadPrivateKeyPem(),
            trustedPeerCertsPem: [
              for (final d in store.activeDevices) d.certPem!
            ]),
        isTrusted: store.isActiveFingerprint,
        pinnedHandler: (_) => Response.notFound(null),
        webSocket: mesh.accept,
        address: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
      );

  Future<void> trust(_Node other) => store.upsert(TrustedDevice(
      deviceId: other.id,
      name: other.ids.identity.name,
      os: 'windows',
      tier: 1,
      fp: other.ids.identity.fp,
      certPem: other.ids.identity.certPem,
      pairedAt: 0,
      lastSeenAt: 0));
}

Envelope _clip(String origin) => Envelope(
    type: MessageType.clipboardUpdate,
    msgId: '00000000-0000-4000-8000-00000000000a',
    origin: origin,
    hlc: Hlc.now(origin),
    ts: 1,
    payload: const {'content_type': 'text/plain'});

void main() {
  test('§6.2: mobile dials desktop, else the smaller id dials', () {
    bool dials(String me, int myTier, String peer, int peerTier) =>
        PeerMesh.shouldInitiate(
            myId: me, myTier: myTier, peerId: peer, peerTier: peerTier);
    expect(dials('b', 2, 'a', 1), isTrue);
    expect(dials('a', 1, 'b', 2), isFalse);
    expect(dials('a', 1, 'b', 1), isTrue);
    expect(dials('b', 1, 'a', 1), isFalse);
  });

  test('paired peers link up and exchange envelopes both ways', () async {
    final x = await _Node.start('X'), y = await _Node.start('Y');
    await x.trust(y);
    await y.trust(x);
    await x.listen();
    await y.listen();
    final (dialer, other) = x.id.compareTo(y.id) < 0 ? (x, y) : (y, x);

    final linked = other.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    // The non-initiator never dials; the initiator does.
    await other.mesh.reach(dialer.id, '127.0.0.1', dialer.server.port);
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    expect(await linked.timeout(const Duration(seconds: 5)), {dialer.id});
    await dialer.mesh.peerChanges
        .firstWhere((p) => p.isNotEmpty)
        .timeout(const Duration(seconds: 5), onTimeout: () => {});
    expect(dialer.mesh.connected, {other.id});

    final atOther = other.mesh.messages.first;
    await dialer.mesh.broadcast(_clip(dialer.id));
    final got = await atOther.timeout(const Duration(seconds: 5));
    expect(got.peerId, dialer.id);
    expect(got.envelope.msgId, '00000000-0000-4000-8000-00000000000a');

    final atDialer = dialer.mesh.messages.first;
    await other.mesh.broadcast(_clip(other.id));
    expect(
        (await atDialer.timeout(const Duration(seconds: 5))).peerId, other.id);
  });

  test('an unpaired device cannot open the Control Plane', () async {
    final x = await _Node.start('X'), stranger = await _Node.start('S');
    await x.listen();
    final client = await PinnedTransportClient.forIdentity(
        identity: stranger.ids,
        store: stranger.store,
        expectedFp: x.ids.identity.fp);
    addTearDown(client.close);
    await expectLater(
        client.connectWebSocket(
            Uri.parse('wss://127.0.0.1:${x.server.port}/api/v1/ws')),
        throwsA(anything));
    expect(x.mesh.connected, isEmpty);
  });
}
