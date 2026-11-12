import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Paired devices, refreshed after every change to the Trusted Store.
  final ValueNotifier<List<TrustedDevice>> trusted;

  DesktopNode._(this.ids, this.store, this.pairing, this.mesh, this.server)
      : trusted = ValueNotifier(store.activeDevices.toList());

  DeviceIdentity get me => ids.identity;

  /// Loads or creates the identity, then binds the first free port of
  /// 53317–53417 (§3.1). [pinned] serves the paired-only HTTP routes.
  static Future<DesktopNode> start({
    required Directory dir,
    required SecureKeyStore keys,
    required String name,
    required DeviceOs os,
    Handler? pinned,
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
    final server = await TlsTransportServer.bindForIdentity(
      identity: ids,
      store: store,
      pinnedHandler: pinned ?? _info(ids),
      pairingHandler: pairing.handler,
      webSocket: (req, fp) => unawaited(mesh.accept(req, fp)),
    );
    log?.call('listening on ${server.port}');
    return node = DesktopNode._(ids, store, pairing, mesh, server);
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
        tombstonesHash: '',
        tombstoneCount: 0,
      );

  /// Dials every trusted peer discovery currently sees (§6.2 decides who).
  void onPeers(List<DiscoveredPeer> peers) {
    for (final p in peers) {
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

  /// Removes a peer; the server refuses it on its next request (§4.4).
  Future<void> forget(String deviceId) async {
    await store.removeByDeviceId(deviceId);
    trusted.value = store.activeDevices.toList();
  }

  void _added(TrustedDevice d) {
    if (d.certPem != null) server.addTrustedPeerCert(d.certPem!);
    trusted.value = store.activeDevices.toList();
  }

  Future<void> close() async {
    await mesh.close();
    await pairing.close();
    await server.close(force: true);
  }

  static Handler _info(DeviceIdentityManager ids) =>
      (request) => request.url.path == 'api/v1/info'
          ? Response.ok(
              jsonEncode({
                'device_id': ids.identity.deviceId,
                'name': ids.identity.name,
                'os': ids.identity.os,
              }),
              headers: const {'content-type': 'application/json'})
          : Response.notFound(null);
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
