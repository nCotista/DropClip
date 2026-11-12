import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// This desktop on the network: persistent identity (T1.2), Trusted Store,
/// the mTLS server (T1.4) with pairing (T1.3) and the Control Plane mesh
/// (T1.5). Everything lives under the config directory.
class DesktopNode {
  final DeviceIdentityManager ids;
  final TrustedDeviceStore store;
  final PairingHost pairing;
  final PeerMesh mesh;
  final TlsTransportServer server;
  final RevocationManager revocation;

  /// Paired devices, refreshed after every change to the Trusted Store.
  final ValueNotifier<List<TrustedDevice>> trusted;

  /// Peers another device revoked; the user confirms or keeps them (§13).
  final quarantined = ValueNotifier<List<TrustedDevice>>(const []);
  StreamSubscription<PeerMessage>? _revocations;

  /// Paired-only HTTP routes by path prefix, e.g. `api/v1/blob/` (§9.1).
  final routes = <String, Handler>{};

  final _addresses = <String, (String, int)>{};

  DesktopNode._(this.ids, this.store, this.pairing, this.mesh, this.server,
      this.revocation)
      : trusted = ValueNotifier(store.activeDevices.toList()) {
    _refresh();
    _revocations = mesh.messages.listen((m) async {
      final env = m.envelope;
      if (env.type == MessageType.deviceRevoked) {
        // The peer removed this device: forget it too (§13.1).
        await store.removeByDeviceId(m.peerId);
        await mesh.drop(m.peerId, VersionNegotiator.wsCloseNotPairedOrRevoked);
      } else if (env.type == MessageType.clusterRevocation) {
        await revocation.onClusterRevocation(
            RevocationBroadcastToken.fromJson(env.payload),
            senderPeerId: m.peerId);
      } else {
        return;
      }
      _refresh();
    });
  }

  DeviceIdentity get me => ids.identity;

  /// Loads or creates the identity, then binds the first free port of
  /// 53317–53417 (§3.1). [pinned] serves the paired-only HTTP routes.
  static Future<DesktopNode> start({
    required Directory dir,
    required SecureKeyStore keys,
    required String name,
    required DeviceOs os,
    void Function(String)? log,
  }) async {
    final ids = DeviceIdentityManager(
        storageDir: Directory('${dir.path}/identity'), keyStore: keys);
    await ids.loadOrCreate(deviceName: name, os: os.name);
    final store = TrustedDeviceStore(
        storageDir: Directory('${dir.path}/trust'), keyStore: keys);
    await store.load();
    late DesktopNode node;
    final pairing = PairingHost(
      engine: PairingEngine(hostIdentity: ids.identity, trustedStore: store),
      store: store,
      onPaired: (d) => node._added(d),
    );
    final mesh = PeerMesh(identity: ids, store: store, hello: () => node.hello);
    final revocation = RevocationManager(
      identityManager: ids,
      trustedStore: store,
      storageDir: Directory('${dir.path}/revocation'),
      sendFrame: (peer, env) => mesh.broadcast(env, to: peer),
      disconnectPeer: mesh.drop,
      broadcastCluster: (env, {excludePeerId}) async {
        for (final p in mesh.connected) {
          if (p != excludePeerId) await mesh.broadcast(env, to: p);
        }
      },
    );
    await revocation.load();
    final server = await TlsTransportServer.bindForIdentity(
      identity: ids,
      store: store,
      pinnedHandler: (r) => node._route(r),
      pairingHandler: pairing.handler,
      webSocket: (req, fp) => unawaited(mesh.accept(req, fp)),
    );
    log?.call('listening on ${server.port}');
    return node = DesktopNode._(ids, store, pairing, mesh, server, revocation);
  }

  /// The mDNS TXT record (§3.2) with the real port and cert fingerprint.
  DiscoveryRecord get record => DiscoveryRecord(
        deviceId: me.deviceId,
        name: me.name,
        os: DeviceOs.values.byName(me.os),
        port: server.port,
        fingerprint: me.fp,
        capabilities: const ['clip.text', 'clip.image', 'file'],
      );

  HelloPayload get hello => HelloPayload(
        deviceId: me.deviceId,
        name: me.name,
        os: me.os,
        tier: 1,
        appVersion: '1.0.0',
        capabilities: record.capabilities,
        tombstonesHash: revocation.tombstonesHash,
        tombstoneCount: revocation.tombstoneCount,
      );

  /// Dials every trusted peer discovery currently sees (§6.2 decides who).
  void onPeers(List<DiscoveredPeer> peers) {
    for (final p in peers) {
      _addresses[p.deviceId] = (p.address, p.record.port);
      if (p.canAutoConnect && p.state != PeerState.stale) {
        unawaited(mesh.reach(p.deviceId, p.address, p.record.port));
      }
    }
  }

  /// Shows this PIN and QR on screen (UI-03); see [PairingHost.events].
  Future<({String pin, QrPairingPayload qr})> openPairing() async =>
      pairing.open(ip: await localAddress(), port: server.port);

  /// Pairs with [peer] as the Client using the PIN shown on it.
  Future<TrustedDevice> pairWith(
    DiscoveredPeer peer,
    String pin,
    Future<bool> Function(String sas, String hostName) confirmSas,
  ) async {
    final device = await PairingClient.pairWithPin(
      host: peer.address,
      port: peer.record.port,
      expectedHostFp: peer.record.fingerprint,
      pin: pin,
      me: me,
      store: store,
      confirmSas: confirmSas,
    );
    _added(device);
    return device;
  }

  /// Revokes a peer (§13): tells it, signs a `cluster.revocation` for the
  /// other peers and drops the link; the server refuses it from now on.
  Future<void> forget(String deviceId) async {
    await revocation.revokePeerLocally(deviceId);
    _refresh();
  }

  /// Answer to a quarantined revocation from another device.
  Future<void> settleQuarantine(String deviceId, {required bool remove}) async {
    await (remove
        ? revocation.confirmQuarantinedRevocation(deviceId)
        : revocation.rejectQuarantinedRevocation(deviceId));
    _refresh();
  }

  void _refresh() {
    trusted.value = store.activeDevices.toList();
    quarantined.value =
        store.allDevices.where((d) => d.status == 'quarantined').toList();
  }

  void _added(TrustedDevice d) {
    if (d.certPem != null) server.addTrustedPeerCert(d.certPem!);
    _refresh();
  }

  Future<void> close() async {
    await _revocations?.cancel();
    await mesh.close();
    await pairing.close();
    await server.close(force: true);
  }

  /// GETs [path] from paired [peerId] over pinned mTLS (e.g. a blob, §9.3).
  Future<Uint8List> fetchFrom(String peerId, String path) =>
      _call(peerId, 'GET', path);

  /// Streams [body] to [path] on paired [peerId]; [onSent] counts bytes.
  Future<Uint8List> postTo(String peerId, String path, Stream<List<int>> body,
          {Map<String, String> headers = const {},
          void Function(int bytes)? onSent}) =>
      _call(peerId, 'POST', path, body: body, headers: headers, onSent: onSent);

  Future<Uint8List> _call(String peerId, String method, String path,
      {Stream<List<int>>? body,
      Map<String, String> headers = const {},
      void Function(int bytes)? onSent}) async {
    final at = _addresses[peerId];
    final peer = store.activeDevices.where((d) => d.deviceId == peerId);
    if (at == null || peer.isEmpty) {
      throw const ProtocolException(
          ProtocolErrorCode.notPaired, 'peer address unknown');
    }
    final client = await PinnedTransportClient.forIdentity(
        identity: ids, store: store, expectedFp: peer.first.fp);
    try {
      final req = await client.httpClient.openUrl(
          method, Uri(scheme: 'https', host: at.$1, port: at.$2, path: path));
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = ContentType.binary;
        await req.addStream(body.map((b) {
          onSent?.call(b.length);
          return b;
        }));
      }
      final res = await req.close();
      final bytes = await res.fold<BytesBuilder>(
          BytesBuilder(copy: false), (b, d) => b..add(d));
      if (res.statusCode != 200) {
        throw ProtocolException(
            ProtocolErrorCode.blobExpired, 'HTTP ${res.statusCode}');
      }
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }

  Future<Response> _route(Request r) async {
    final path = r.url.path;
    if (path == 'api/v1/info') {
      return Response.ok(jsonEncode(hello.toJson()),
          headers: const {'content-type': 'application/json'});
    }
    for (final e in routes.entries) {
      if (path.startsWith(e.key)) return e.value(r);
    }
    return Response.notFound(null);
  }
}

/// The first non-loopback IPv4 address, shown for manual pairing.
Future<String> localAddress() async {
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      if (!a.isLoopback && !a.isLinkLocal) return a.address;
    }
  }
  return InternetAddress.loopbackIPv4.address;
}
