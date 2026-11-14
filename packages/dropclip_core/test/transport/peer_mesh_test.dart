import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  final events = <(String, Map<String, Object?>)>[];

  String get id => ids.identity.deviceId;

  static Future<_Node> start(String name,
      {Duration? grace,
      Duration? stableAfter,
      ReconnectBackoffPolicy? backoff,
      SecureKeyStore? keys}) async {
    final n = _Node();
    final dir = await Directory.systemTemp.createTemp('dc_mesh_');
    keys ??= InMemorySecureKeyStore();
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
      backoff: backoff,
      initiatorGrace: grace ?? const Duration(seconds: 10),
      stableAfter: stableAfter ?? const Duration(seconds: 10),
      onEvent: (event, data) => n.events.add((event, data)),
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

/// A keychain that can be made to fail, as iOS may right after launch.
class _FlakyKeys extends InMemorySecureKeyStore {
  bool failing = false;

  @override
  Future<Uint8List?> read(String key) async {
    if (failing) throw StateError('keychain not available');
    return super.read(key);
  }
}

/// Backoff that records which attempt it was asked for and waits briefly.
class _Recorded extends ReconnectBackoffPolicy {
  final attempts = <int>[];

  @override
  Duration delayForAttempt(int attempt) {
    attempts.add(attempt);
    return const Duration(milliseconds: 30);
  }
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

    await dialer.mesh.drop(other.id, 4004);
    expect(dialer.mesh.connected, isEmpty);
  });

  /// Two paired, listening nodes: (the §6.2 initiator, the other one).
  Future<(_Node, _Node)> pair(
      {Duration? grace,
      Duration? stableAfter,
      ReconnectBackoffPolicy? backoff}) async {
    Future<_Node> node(String name) => _Node.start(name,
        grace: grace, stableAfter: stableAfter, backoff: backoff);
    final x = await node('X'), y = await node('Y');
    await x.trust(y);
    await y.trust(x);
    await x.listen();
    await y.listen();
    return x.id.compareTo(y.id) < 0 ? (x, y) : (y, x);
  }

  Future<void> until(bool Function() ok, {int seconds = 5}) async {
    for (var i = 0; i < seconds * 50 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(ok(), isTrue);
  }

  test('§6.2 rule 3: the other side dials when the initiator does not',
      () async {
    final (dialer, other) =
        await pair(grace: const Duration(milliseconds: 300));
    // Only the non-initiator knows where its peer is, as when the
    // initiator's dial is blocked by a firewall on our side.
    await other.mesh.reach(dialer.id, '127.0.0.1', dialer.server.port);
    expect(other.mesh.connected, isEmpty);
    await until(() =>
        other.mesh.connected.contains(dialer.id) &&
        dialer.mesh.connected.contains(other.id));

    // When the rightful initiator connects after all, exactly one link
    // stays on each side (rule 4) and both remain connected.
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(dialer.mesh.connected, {other.id});
    expect(other.mesh.connected, {dialer.id});
  });

  test('the data plane gets the address of the live link', () async {
    final (dialer, other) = await pair();
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    await until(() => other.mesh.connected.isNotEmpty);
    expect(dialer.mesh.linkAddress(other.id),
        (host: '127.0.0.1', port: other.server.port));
    // The acceptor knows the peer's IP, not its listening port.
    expect(other.mesh.linkAddress(dialer.id), (host: '127.0.0.1', port: null));
    await dialer.mesh.drop(other.id, 4004);
    expect(dialer.mesh.linkAddress(other.id), isNull);
  });

  test('reach(force: true) redials a socket that still looks open', () async {
    final (dialer, other) = await pair();
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    await until(() => dialer.mesh.connected.contains(other.id));

    // The phone resumes from doze: `isClosed` is still false, yet the link
    // is dead. A plain reach does nothing; force must replace the session.
    await dialer.mesh
        .reach(other.id, '127.0.0.1', other.server.port, force: true);
    await until(() => dialer.mesh.connected.contains(other.id));
    expect(dialer.mesh.connected, {other.id});

    final atDialer = dialer.mesh.messages.first;
    await other.mesh.broadcast(_clip(other.id));
    expect(
        (await atDialer.timeout(const Duration(seconds: 5))).peerId, other.id);
  });

  test('a dead address is skipped for one that works', () async {
    final backoff = _Recorded();
    final (dialer, other) = await pair(backoff: backoff);
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    await until(() => other.mesh.connected.isNotEmpty);
    // A second announcement (another adapter) points nowhere; it is the
    // newest, so the next dial tries it first and then the one that worked.
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    await dialer.mesh.reach(other.id, '127.0.0.1', deadPort);

    await other.mesh.drop(dialer.id, 4000);
    await until(() => dialer.mesh.connected.isEmpty);
    await until(() => dialer.mesh.connected.contains(other.id));
    expect(dialer.mesh.linkAddress(other.id)?.port, other.server.port);
  });

  test('a link that keeps dropping right after hello backs off (§6.5)',
      () async {
    final backoff = _Recorded();
    final (dialer, other) = await pair(backoff: backoff);
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    for (var i = 0; i < 3; i++) {
      await until(() => other.mesh.connected.contains(dialer.id));
      // E.g. the same identity running twice keeps kicking this link out.
      await other.mesh.drop(dialer.id, 4001);
    }
    await until(() => backoff.attempts.length == 3);
    expect(backoff.attempts, [0, 1, 2]);
    expect(
        dialer.events.where((e) => e.$1 == 'closed').map((e) => e.$2['ready']),
        everyElement(isTrue));
  });

  test('a link that was stable reconnects at once after a drop', () async {
    final backoff = _Recorded();
    final (dialer, other) =
        await pair(backoff: backoff, stableAfter: Duration.zero);
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    for (var i = 0; i < 3; i++) {
      await until(() => other.mesh.connected.contains(dialer.id));
      await other.mesh.drop(dialer.id, 4000);
    }
    await until(() => backoff.attempts.length == 3);
    expect(backoff.attempts, [0, 0, 0]);
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

  test('reach(force: true) stops cleanly if close() runs mid-shutdown',
      () async {
    final (dialer, other) = await pair();
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    await until(() => other.mesh.connected.contains(dialer.id));
    await until(() => dialer.mesh.connected.contains(other.id));

    final redial = dialer.mesh
        .reach(other.id, '127.0.0.1', other.server.port, force: true);
    await dialer.mesh.close();
    await redial;
    expect(dialer.mesh.connected, isEmpty);
  });
  test('a peer that vanished without closing is replaced by its new link',
      () async {
    final (dialer, other) = await pair();
    // The first link goes through a proxy that later freezes: the phone was
    // killed (or lost Wi-Fi) and no FIN reaches the computer, so `other`
    // still holds a session that looks open.
    var frozen = false;
    final held = <Socket>[];
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await proxy.close();
      for (final s in held) {
        s.destroy();
      }
    });
    proxy.listen((inbound) async {
      // ignore: close_sinks, destroyed in tearDown via `held`.
      final out =
          await Socket.connect(InternetAddress.loopbackIPv4, other.server.port);
      held.addAll([inbound, out]);
      inbound.listen((d) => frozen ? null : out.add(d), onError: (_) {});
      out.listen((d) => frozen ? null : inbound.add(d), onError: (_) {});
    });
    await dialer.mesh.reach(other.id, '127.0.0.1', proxy.port);
    await until(() => other.mesh.connected.contains(dialer.id));
    await until(() => dialer.mesh.connected.contains(other.id));
    frozen = true;

    // The app starts again and dials the computer directly.
    await dialer.mesh
        .reach(other.id, '127.0.0.1', other.server.port, force: true);
    await until(() => dialer.mesh.connected.contains(other.id), seconds: 10);
    final atDialer = dialer.mesh.messages.first;
    await other.mesh.broadcast(_clip(other.id));
    expect(
        (await atDialer.timeout(const Duration(seconds: 5))).peerId, other.id);
  });

  test('a dial that fails before connecting is retried (keychain error)',
      () async {
    final backoff = _Recorded();
    final kx = _FlakyKeys(), ky = _FlakyKeys();
    final x = await _Node.start('X', keys: kx, backoff: backoff),
        y = await _Node.start('Y', keys: ky, backoff: backoff);
    await x.trust(y);
    await y.trust(x);
    await x.listen();
    await y.listen();
    final (dialer, other, keys) =
        x.id.compareTo(y.id) < 0 ? (x, y, kx) : (y, x, ky);
    keys.failing = true;
    await dialer.mesh.reach(other.id, '127.0.0.1', other.server.port);
    expect(dialer.mesh.connected, isEmpty);
    keys.failing = false;
    await until(() => dialer.mesh.connected.contains(other.id));
    expect(backoff.attempts, isNotEmpty);
  });
}
