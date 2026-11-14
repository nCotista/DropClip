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
  StreamSubscription<String>? _mismatches;
  StreamSubscription<Set<String>>? _links;

  /// Paired-only HTTP routes by path prefix, e.g. `api/v1/blob/` (§9.1).
  final routes = <String, Handler>{};

  /// The browser companion at `/web` (no client cert; own token auth).
  Handler? webHandler;

  /// Settings → network adapter used for the pairing and web addresses;
  /// empty means pick automatically.
  String networkAdapter = '';

  final _addresses = <String, (String, int)>{};

  DesktopNode._(this.ids, this.store, this.pairing, this.mesh, this.server,
      this.revocation)
      : trusted = ValueNotifier(store.activeDevices.toList()) {
    _refresh();
    _revocations = mesh.messages.listen((m) async {
      final env = m.envelope;
      try {
        if (env.type == MessageType.deviceRevoked) {
          // The peer removed this device: forget it too (§13.1).
          await store.removeByDeviceId(m.peerId);
          await mesh.drop(
              m.peerId, VersionNegotiator.wsCloseNotPairedOrRevoked);
        } else if (env.type == MessageType.clusterRevocation) {
          await revocation.onClusterRevocation(
              RevocationBroadcastToken.fromJson(env.payload),
              senderPeerId: m.peerId);
        } else if (env.type == MessageType.revocationSync) {
          // §13.2.6: revocations made while this device was offline.
          await revocation.applySyncPayload(env.payload,
              senderPeerId: m.peerId);
        } else {
          return;
        }
      } on Object {
        // A malformed frame from a peer changes nothing.
        return;
      }
      _refresh();
    });
    // A peer's hello may carry a new name (it was renamed): show it.
    _links = mesh.peerChanges.listen((_) => _refresh());
    // §13.2.6: a peer whose tombstones differ gets ours right after hello.
    _mismatches = mesh.tombstoneMismatches.listen((peerId) {
      final sync = revocation.buildSyncEnvelope();
      if (sync != null) unawaited(mesh.broadcast(sync, to: peerId));
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
    void Function(String event, Map<String, Object?> data)? onMeshEvent,
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
    final mesh = PeerMesh(
        identity: ids,
        store: store,
        hello: () => node.hello,
        onEvent: onMeshEvent);
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
      webHandler: (r) => node.webHandler?.call(r) ?? Response.notFound(null),
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
        appVersion: '1.0.6',
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
  Future<({String pin, QrPairingPayload qr})> openPairing() async => pairing
      .open(ip: await localAddress(prefer: networkAdapter), port: server.port);

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

  /// Shows [name] to other devices from now on; paired peers see it when
  /// they next connect (their hello handling stores it).
  Future<void> rename(String name) async {
    await ids.rename(name);
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
    // Paired again after "Remove": the old revocation no longer applies.
    unawaited(revocation.clearTombstone(d.deviceId));
    _refresh();
  }

  Future<void> close() async {
    await _revocations?.cancel();
    await _mismatches?.cancel();
    await _links?.cancel();
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
    // The address of the live link is proven reachable; discovery may have
    // announced another adapter, or not have seen the peer at all (it then
    // dialed us and only its port is unknown: the default is the best guess).
    final link = mesh.linkAddress(peerId);
    final seen = _addresses[peerId];
    final host = link?.host ?? seen?.$1;
    final peer = store.activeDevices.where((d) => d.deviceId == peerId);
    if (host == null || peer.isEmpty) {
      throw const ProtocolException(
          ProtocolErrorCode.notPaired, 'peer address unknown');
    }
    final port = link?.port ?? seen?.$2 ?? kTransportPortFirst;
    final client = await PinnedTransportClient.forIdentity(
        identity: ids, store: store, expectedFp: peer.first.fp);
    // Fail in seconds, not the OS default of ~20 s, when the peer's
    // firewall drops the connection.
    client.httpClient.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.httpClient.openUrl(
          method, Uri(scheme: 'https', host: host, port: port, path: path));
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

/// The LAN IPv4 address other devices reach this PC on, for the pairing
/// and web QR codes. [prefer] is the adapter picked in Settings.
Future<String> localAddress({String? prefer}) async =>
    (await localLan(prefer: prefer))?.address ??
    InternetAddress.loopbackIPv4.address;

/// Every adapter with a non-loopback IPv4, best first, for Settings → network
/// adapter. Names are deduplicated and ordered by [adapterScore].
Future<List<String>> lanAdapterNames() async {
  final best = <String, int>{};
  for (final c in await _lanCandidates()) {
    final score = adapterScore(c);
    final seen = best[c.name];
    if (seen == null || score < seen) best[c.name] = score;
  }
  final names = best.keys.toList()
    ..sort((a, b) {
      final byScore = best[a]!.compareTo(best[b]!);
      return byScore != 0
          ? byScore
          : a.toLowerCase().compareTo(b.toLowerCase());
    });
  return names;
}

/// The adapter other devices reach this PC on: its OS name (e.g. `Wi-Fi`)
/// and IPv4 address, or null when the PC is on no network.
///
/// [prefer] wins when that adapter is present and has an address, so a PC
/// with a hypervisor switch or a VPN can be pinned to the real LAN instead
/// of trusting the automatic pick.
Future<({String name, String address})?> localLan({String? prefer}) async =>
    chooseAdapter(await _lanCandidates(), prefer ?? '');

/// Applies the Settings choice to [all]: [prefer] wins when that adapter has
/// an address, otherwise [pickLanAddress] decides. Null when there is no
/// usable adapter at all.
@visibleForTesting
({String name, String address})? chooseAdapter(
    List<({String name, InternetAddress address})> all, String prefer) {
  if (all.isEmpty) return null;
  final wanted = prefer.trim();
  if (wanted.isNotEmpty) {
    for (final c in all) {
      if (c.name == wanted) return (name: c.name, address: c.address.address);
    }
  }
  final address = pickLanAddress(all);
  for (final c in all) {
    if (c.address.address == address) return (name: c.name, address: address);
  }
  return null;
}

Future<List<({String name, InternetAddress address})>> _lanCandidates() async =>
    [
      for (final i
          in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) (name: i.name, address: a)
    ];

/// Adapter names that are never the LAN other devices reach this PC on:
/// hypervisor switches, container runtimes, VPN/tunnel clients, and the
/// Windows Wi-Fi Direct / hosted-network pseudo adapters. A PC with any of
/// these used to be pinned to the wrong address depending on the order the
/// OS happened to list them in.
final RegExp _virtualAdapter = RegExp(
    r'virtual|vethernet|hyper-?v|vmware|virtualbox|vbox|wsl|docker|'
    r'zerotier|tailscale|hamachi|radmin|nordlynx|wireguard|openvpn|vpn|'
    r'tun|tap|ppp|pseudo|loopback|wi-?fi direct|hosted network|'
    r'local area connection\*|bluetooth|npcap|vmnet|teredo|isatap|'
    r'softether',
    caseSensitive: false);

/// Subnets virtual switches and container runtimes hand out, plus the
/// 100.64/10 range Tailscale uses.
final RegExp _virtualSubnet = RegExp(r'^(192\.168\.56\.|192\.168\.137\.|'
    r'172\.(1[6-9]|2\d|3[01])\.|'
    r'100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)');

final RegExp _wifiName = RegExp(r'wi-?fi|wlan|wireless', caseSensitive: false);
final RegExp _wiredName = RegExp(r'ethernet|^eth|^en\d', caseSensitive: false);

bool _isPrivateV4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// Lower is better. 100 or more means "this is not the real LAN adapter".
@visibleForTesting
int adapterScore(({String name, InternetAddress address}) c) {
  final ip = c.address.address;
  var score = 0;
  if (_virtualAdapter.hasMatch(c.name)) score += 100;
  if (_virtualSubnet.hasMatch(ip)) score += 20;
  if (!_isPrivateV4(ip)) score += 10;
  if (!_wifiName.hasMatch(c.name)) {
    score += _wiredName.hasMatch(c.name) ? 1 : 5;
  }
  return score;
}

/// Picks the adapter other devices reach this PC on. Skips loopback,
/// link-local and virtual adapters, prefers Wi-Fi/Ethernet on a private
/// subnet, and breaks ties by name so the same PC always gets the same
/// answer no matter what order the OS lists adapters in.
String pickLanAddress(List<({String name, InternetAddress address})> all) {
  final usable = all
      .where((c) => !c.address.isLoopback && !c.address.isLinkLocal)
      .toList();
  if (usable.isEmpty) return InternetAddress.loopbackIPv4.address;
  final real = usable.where((c) => adapterScore(c) < 100).toList();
  final pool = real.isEmpty ? usable : real;
  pool.sort((a, b) {
    final byScore = adapterScore(a).compareTo(adapterScore(b));
    if (byScore != 0) return byScore;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0
        ? byName
        : a.address.address.compareTo(b.address.address);
  });
  return pool.first.address.address;
}
