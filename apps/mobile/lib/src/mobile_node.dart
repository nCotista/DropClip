import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shelf/shelf.dart';

import 'mobile_peer.dart';

/// Android Keystore-wrapped / iOS Keychain storage for the identity key
/// and the Trusted Store key (§4.2).
class SecureStorageKeyStore implements SecureKeyStore {
  final _s = const FlutterSecureStorage();

  @override
  Future<Uint8List?> read(String key) async {
    final v = await _s.read(key: key);
    return v == null ? null : base64Decode(v);
  }

  @override
  Future<void> write(String key, Uint8List value) =>
      _s.write(key: key, value: base64Encode(value));

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class _Incoming {
  final String peer;
  final Map<String, FileOfferItem> items;
  final completed = <String>{};

  /// Its own receiver, so its `.part` files are its own.
  final StreamingFileReceiver receiver;
  _Incoming(this.peer, this.items, this.receiver);
}

/// This device on the LAN (Tier 2 Android / Tier 3 iOS): identity, Trusted
/// Store, bidirectional pairing Host + Client, Control Plane mesh (§6.2), and
/// clipboard/file sync through [ClipboardSyncEngine] (FR-03B).
class MobileNode implements MobilePeer {
  final DeviceIdentityManager ids;
  final TrustedDeviceStore store;
  final PeerMesh mesh;
  final PairingHost pairing;
  final File _hosts;
  final Future<void> Function(String text) writeClipboard;
  final void Function(String text, String from) onReceived;

  /// The mTLS server paired devices send files and images to (§9).
  final TlsTransportServer server;

  /// Where received files and images are saved.
  final Directory received;

  /// A file or image from [from] is saved at [file].
  final void Function(File file, String from) onFile;

  final _incoming = <String, _Incoming>{};
  final _addresses = <String, (String host, int port)>{};
  Future<void> _hostOp = Future<void>.value();
  Future<void> _msgQueue = Future<void>.value();
  String _activeSender = '';
  DiscoveryService? _discovery;
  @override
  final ValueNotifier<List<TrustedDevice>> trusted;
  late final ClipboardSyncEngine _engine;
  late final StreamSubscription<PeerMessage> _sub;
  late final StreamSubscription<PairingHostEvent> _pairSub;
  final Future<String> Function() _localIp;
  Timer? _watchdog;

  /// Settings switch: off stops sending and receiving clips.
  final bool Function() syncEnabled;

  MobileNode._(
      this.ids,
      this.store,
      this.mesh,
      this.pairing,
      this._hosts,
      this.writeClipboard,
      this.onReceived,
      this.syncEnabled,
      this.server,
      this.received,
      this.onFile,
      this._localIp)
      : trusted = ValueNotifier(store.activeDevices.toList()) {
    _engine = ClipboardSyncEngine(
      myId: me.deviceId,
      policy: () => SyncPolicy(
          enabled: syncEnabled(),
          types: const {ClipType.text, ClipType.url, ClipType.image}),
      ports: TransportSyncAdapter(
        sendBroadcastEnvelope: (e) => unawaited(mesh.broadcast(e)),
        remoteBlobFetcher: (peer, id) => _fetch(peer, '/api/v1/blob/$id'),
        osWriteClipboard: (type, raw) async {
          if (type != ClipType.image) return writeClipboard(utf8.decode(raw));
          decodePng(raw);
          // shortcut: images are saved and listed, not put on the phone
          // clipboard (Flutter's clipboard is text only); add a plugin for
          // that when it is needed.
          final ms = DateTime.now().millisecondsSinceEpoch;
          final f = await StreamingFileReceiver.freeNameFor(
              File('${received.path}/image-$ms.png'));
          await f.parent.create(recursive: true);
          await f.writeAsBytes(raw);
          onFile(f, _activeSender);
        },
      ),
    );
    _pairSub = pairing.events.listen((event) {
      if (event
          case PairingCompleted(
            :final device,
            :final clientIp,
            :final clientPort,
          )) {
        if (clientIp != null && clientPort != null) {
          _addresses[device.deviceId] = (clientIp, clientPort);
          unawaited(_updateHosts(
              (hosts) => hosts[device.deviceId] = '$clientIp:$clientPort'));
          unawaited(mesh.reach(device.deviceId, clientIp, clientPort));
        }
      }
    });
    // A peer's hello may carry a new name (it was renamed): show it.
    mesh.peerChanges
        .listen((_) => trusted.value = store.activeDevices.toList());
    _sub = mesh.messages.listen((m) {
      _msgQueue = _swallow(_msgQueue.then<void>((_) => _onMessage(m)));
    });
  }

  Future<void> _onMessage(PeerMessage m) async {
    final type = m.envelope.type;
    if (type == MessageType.deviceRevoked) {
      // The peer removed this device: forget it too (§13.1).
      _incoming.removeWhere((_, v) => v.peer == m.peerId);
      _addresses.remove(m.peerId);
      await store.removeByDeviceId(m.peerId);
      await mesh.drop(m.peerId, VersionNegotiator.wsCloseNotPairedOrRevoked);
      await _updateHosts((hosts) => hosts.remove(m.peerId));
      trusted.value = store.activeDevices.toList();
      return;
    }
    if (type == MessageType.fileOffer) return _offered(m);
    if (type != MessageType.clipboardUpdate) return;
    _activeSender = _nameOf(m.peerId);
    try {
      final u = TransportSyncAdapter.envelopeToClipUpdate(m.envelope);
      final sent = await _engine.onRemoteUpdate(u, m.peerId);
      if (sent && u.inline != null && u.type != ClipType.image) {
        onReceived(utf8.decode(u.inline!), _nameOf(m.peerId));
      }
    } on Object {
      // An image the computer no longer has, bad PNG, or a malformed frame.
    } finally {
      _activeSender = '';
    }
  }

  String _nameOf(String deviceId) =>
      store.getByDeviceId(deviceId)?.name ?? deviceId;

  DeviceIdentity get me => ids.identity;

  int get _tier => me.os == 'ios' ? 3 : 2;

  @override
  Stream<Set<String>> get connectedChanges => mesh.peerChanges;
  @override
  Set<String> get connected => mesh.connected;

  static Future<MobileNode> start({
    required Directory dir,
    required SecureKeyStore keys,
    required String name,
    required String os,
    required Future<void> Function(String text) writeClipboard,
    required void Function(String text, String from) onReceived,
    bool Function()? syncEnabled,
    Directory? received,
    void Function(File file, String from)? onFile,
    Future<String> Function()? localIp,
    Future<int?> Function()? freeBytes,
    int firstPort = kTransportPortFirst,
    int lastPort = kTransportPortLast,
  }) async {
    final ids = DeviceIdentityManager(
        storageDir: Directory('${dir.path}/identity'), keyStore: keys);
    await ids.loadOrCreate(deviceName: name, os: os);
    final store = TrustedDeviceStore(
        storageDir: Directory('${dir.path}/trust'), keyStore: keys);
    await store.load();
    late MobileNode node;
    final mesh = PeerMesh(identity: ids, store: store, hello: () => node.hello);
    late final TlsTransportServer server;
    final pairing = PairingHost(
      engine: PairingEngine(
        hostIdentity: ids.identity,
        trustedStore: store,
        hostTier: ids.identity.os == 'ios' ? 3 : 2,
      ),
      store: store,
      onPaired: (d) {
        if (d.certPem != null) server.addTrustedPeerCert(d.certPem!);
        node.trusted.value = store.activeDevices.toList();
      },
    );
    server = await TlsTransportServer.bindForIdentity(
      identity: ids,
      store: store,
      pairingHandler: pairing.handler,
      pinnedHandler: (r) => node._route(r),
      webSocket: (r, fp) => unawaited(mesh.accept(r, fp)),
      firstPort: firstPort,
      lastPort: lastPort,
    );
    node = MobileNode._(
        ids,
        store,
        mesh,
        pairing,
        File('${dir.path}/hosts.json'),
        writeClipboard,
        onReceived,
        syncEnabled ?? () => true,
        server,
        received ?? Directory('${dir.path}/received'),
        onFile ?? (_, __) {},
        localIp ?? () => localLanIpv4());
    node._freeBytes = freeBytes;
    return node;
  }

  /// Free space where received files go; null when the platform cannot say.
  /// Offers are accepted without asking, so this is the only size gate.
  Future<int?> Function()? _freeBytes;

  /// Finds paired computers on the Wi-Fi and announces this phone, so it
  /// reconnects after the computer's address changes and shows up in the
  /// computer's Dropzone (§3).
  Future<void> startDiscovery(MdnsBackend backend) async {
    final cache = PeerCache(
        localDeviceId: me.deviceId, trustedFingerprint: store.fingerprintOf);
    cache.changes.listen((peers) async {
      final updates = <String, String>{
        for (final p in peers)
          if (p.canAutoConnect && p.state != PeerState.stale)
            p.deviceId: '${p.address}:${p.record.port}',
      };
      if (updates.isEmpty) return;
      await _withHostLock(() async {
        final hosts = await _savedHosts();
        var dirty = false;
        for (final e in updates.entries) {
          if (hosts[e.key] != e.value) {
            hosts[e.key] = e.value;
            dirty = true;
          }
        }
        if (dirty) await _writeHostsAtomic(hosts);
      });
      for (final p in peers) {
        if (!p.canAutoConnect || p.state == PeerState.stale) continue;
        _addresses[p.deviceId] = (p.address, p.record.port);
        unawaited(mesh.reach(p.deviceId, p.address, p.record.port));
      }
    });
    _discovery =
        DiscoveryService(backend: backend, cache: cache, record: _record);
    await _discovery!.start();
  }

  DiscoveryRecord get _record => DiscoveryRecord(
        deviceId: me.deviceId,
        name: me.name,
        os: DeviceOs.values.byName(me.os),
        port: server.port,
        fingerprint: me.fp,
        capabilities: const ['clip.text', 'clip.image', 'file'],
      );

  Future<({String host, int port, TrustedDevice peer})> _resolvePeer(
      String peerId) async {
    final at = mesh.linkAddress(peerId);
    final peer = store.getByDeviceId(peerId);
    if (at == null || peer == null) {
      throw StateError('device is not connected');
    }
    final port = at.port ??
        _addresses[peerId]?.$2 ??
        _parseHostPort((await _withHostLock(_savedHosts))[peerId])?.$2;
    if (port == null) throw StateError('device is not connected');
    return (host: at.host, port: port, peer: peer);
  }

  /// `GET` [path] from paired [peerId] over pinned mTLS (e.g. a blob, §9.3).
  Future<Uint8List> _fetch(String peerId, String path) async {
    final target = await _resolvePeer(peerId);
    final client = await PinnedTransportClient.forIdentity(
        identity: ids, store: store, expectedFp: target.peer.fp);
    client.httpClient.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.httpClient.getUrl(Uri(
          scheme: 'https', host: target.host, port: target.port, path: path));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      if (res.contentLength > ProtocolConstants.clipboardMaxSize) {
        throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge, 'blob > 32 MiB');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res) {
        if (bytes.length + chunk.length > ProtocolConstants.clipboardMaxSize) {
          throw const ProtocolException(
              ProtocolErrorCode.payloadTooLarge, 'blob > 32 MiB');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  /// A computer offers files: paired computers are trusted, so they are
  /// taken (the computer's user chose to send them).
  Future<void> _offered(PeerMessage m) async {
    final p = m.envelope.payload;
    final rawTid = p['transfer_id'];
    final tid = rawTid is String && rawTid.isNotEmpty ? rawTid : '';
    var ok = false;
    try {
      if (tid.isEmpty) {
        throw const ProtocolException(
            ProtocolErrorCode.malformed, 'missing transfer_id');
      }
      final rawItems = p['items'] as List;
      if (rawItems.length > ProtocolConstants.maxItemsPerTransfer) {
        throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge, 'too many items in offer');
      }
      final items = [
        for (final j in rawItems)
          FileOfferItem.fromJson(j as Map<String, dynamic>)
      ];
      final free = _freeBytes;
      final receiver = StreamingFileReceiver(
          destinationRoot: received,
          transferId: tid,
          // Unknown free space: let the write fail (and clean up) instead.
          availableDiskBytes:
              free == null ? null : () async => await free() ?? 1 << 62);
      await receiver.validateOffer(items: items);
      final byId = {for (final i in items) i.itemId: i};
      _incoming[tid] = _Incoming(m.peerId, byId, receiver);
      ok = true;
    } on Object {
      ok = false;
    }
    await mesh.broadcast(
        _envelope(
            ok ? MessageType.fileAccept : MessageType.fileReject,
            ok
                ? {
                    'transfer_id': tid,
                    'accepted_items': [..._incoming[tid]!.items.keys],
                    'auto': true
                  }
                : {'transfer_id': tid, 'reason': 'invalid_offer'}),
        to: m.peerId);
  }

  /// `GET .../status`, `POST .../{item}`, `POST .../finish` from a computer
  /// sending files (§9); the same steps the desktop receiver serves.
  Future<Response> _route(Request r) async {
    final seg = r.url.pathSegments; // api v1 file <tid> <item|finish>[/status]
    if (seg.length < 5 || !r.url.path.startsWith('api/v1/file/')) {
      return Response.notFound(null);
    }
    final tid = seg[3];
    final t = _incoming[tid];
    final fp = r.context[kPeerFingerprintContextKey] as String?;
    if (t == null || store.getByFingerprint(fp ?? '')?.deviceId != t.peer) {
      return _json(404, {'error': 'unknown transfer'});
    }
    if (seg.length == 5 && seg[4] == 'finish') {
      if (r.method != 'POST') return Response(405);
      final missing = [
        for (final i in t.items.values)
          if (!t.completed.contains(i.itemId)) i.itemId
      ];
      if (missing.isNotEmpty) {
        _incoming.remove(tid);
        unawaited(mesh.broadcast(
            _envelope(MessageType.fileComplete, {
              'transfer_id': tid,
              'state': 'failed',
              'code': 'E_INCOMPLETE',
              'items': [
                for (final id in missing) {'item_id': id}
              ],
            }),
            to: t.peer));
        return _json(409, {'error': 'incomplete', 'missing': missing});
      }
      _incoming.remove(tid);
      unawaited(mesh.broadcast(
          _envelope(MessageType.fileComplete, {
            'transfer_id': tid,
            'state': 'complete',
            'items': const <Object>[]
          }),
          to: t.peer));
      return _json(200, {'state': 'complete'});
    }
    final item = t.items[seg[4]];
    if (item == null) return _json(404, {'error': 'unknown item'});
    final part = t.receiver.partFileFor(item);
    if (r.method == 'GET') {
      if (seg.length != 6 || seg[5] != 'status') return Response.notFound(null);
      if (t.completed.contains(item.itemId)) {
        return _json(200, {'offset': item.size, 'state': 'complete'});
      }
      // Start over: a broken upload resends from 0 (no resume on phones).
      if (await part.exists()) await part.delete();
      return _json(200, {'offset': 0, 'state': 'in_progress'});
    }
    if (seg.length != 5) return Response.notFound(null);
    if (r.method != 'POST') return Response(405);
    final rawOff = r.headers['x-offset'];
    var at = rawOff == null ? 0 : (int.tryParse(rawOff) ?? -1);
    if (at < 0) {
      const e =
          ProtocolException(ProtocolErrorCode.offsetMismatch, 'bad offset');
      return _json(e.httpStatus, e.toHttpJson());
    }
    if (at == 0 && await part.exists()) await part.delete();
    try {
      final buf = BytesBuilder(copy: false);
      Future<void> write(Uint8List chunk) async {
        final file =
            await t.receiver.appendChunk(item: item, offset: at, chunk: chunk);
        at += chunk.length;
        if (file != null) {
          t.completed.add(item.itemId);
          onFile(file, _nameOf(t.peer));
        }
      }

      await for (final data in r.read()) {
        var rest = data;
        while (rest.isNotEmpty) {
          final take = min(kStreamingChunkSize - buf.length, rest.length);
          buf.add(rest.sublist(0, take));
          rest = rest.sublist(take);
          if (buf.length == kStreamingChunkSize) await write(buf.takeBytes());
        }
      }
      if (buf.isNotEmpty || (item.size == 0 && at == 0)) {
        await write(buf.takeBytes());
      }
      final done = t.completed.contains(item.itemId);
      final state = done ? 'complete' : 'in_progress';
      return _json(200, {'received_bytes': at, 'state': state});
    } on ProtocolException catch (e) {
      return _json(e.httpStatus, e.toHttpJson());
    } on Object {
      // The disk is full, the folder went away, a name is blocked...: end
      // the transfer here, drop the half file and tell the computer, as
      // the desktop receiver does. Otherwise it would stay open for good.
      if (_incoming.remove(tid) != null) {
        for (final i in t.items.values) {
          try {
            final p = t.receiver.partFileFor(i);
            if (await p.exists()) await p.delete();
          } on Object {
            // Nothing more to clean.
          }
        }
        unawaited(mesh.broadcast(
            _envelope(MessageType.fileComplete, {
              'transfer_id': tid,
              'state': 'failed',
              'code': 'E_WRITE_FAILED',
              'items': [
                {'item_id': item.itemId}
              ],
            }),
            to: t.peer));
      }
      return _json(500, {'error': 'transfer_failed'});
    }
  }

  static Response _json(int status, Map<String, Object?> body) =>
      Response(status,
          body: jsonEncode(body),
          headers: const {'content-type': 'application/json'});

  HelloPayload get hello => HelloPayload(
      deviceId: me.deviceId,
      name: me.name,
      os: me.os,
      tier: _tier,
      appVersion: '1.0.9',
      capabilities: _tier == 3
          ? const ['clip.text', 'clip.image', 'file']
          : const ['clip.text', 'clip.push', 'clip.image', 'file'],
      tombstonesHash: '',
      tombstoneCount: 0);

  @override
  Stream<PairingHostEvent> get pairingEvents => pairing.events;

  @override
  Future<({String pin, String address, String qr})> openPairing() async {
    final ip = await _localIp();
    final s = pairing.open(ip: ip, port: server.port);
    return (
      pin: s.pin,
      address: '$ip:${server.port}',
      qr: jsonEncode(s.qr.toJson()),
    );
  }

  @override
  void confirmPairing(bool match) => pairing.confirm(match);

  /// Pairs with the peer at [host]:[port] using the PIN it shows (§5,
  /// manual IP + PIN), then connects to it.
  @override
  Future<TrustedDevice> pairWithQr(String scanned,
      Future<bool> Function(String sas, String hostName) confirm) async {
    final Map<String, dynamic> qr;
    try {
      qr = jsonDecode(scanned) as Map<String, dynamic>;
    } on Object {
      throw const PairingClientException(
          'E_PAIRING_INVALID', 'not a DropClip QR');
    }
    final d = await PairingClient.pairWithQr(
        qr: qr,
        me: me,
        store: store,
        confirmSas: confirm,
        tier: _tier,
        clientPort: server.port);
    return _connect(d, qr['ip'] as String, qr['port'] as int);
  }

  @override
  Future<TrustedDevice> pair(String host, int port, String pin,
      Future<bool> Function(String sas, String hostName) confirm) async {
    final d = await PairingClient.pairWithPin(
        host: host,
        port: port,
        pin: pin,
        me: me,
        store: store,
        confirmSas: confirm,
        tier: _tier,
        clientPort: server.port);
    return _connect(d, host, port);
  }

  /// Remembers where the peer is and dials it.
  Future<TrustedDevice> _connect(TrustedDevice d, String host, int port) async {
    if (d.certPem != null) server.addTrustedPeerCert(d.certPem!);
    _addresses[d.deviceId] = (host, port);
    await _updateHosts((hosts) => hosts[d.deviceId] = '$host:$port');
    trusted.value = store.activeDevices.toList();
    unawaited(mesh.reach(d.deviceId, host, port));
    return d;
  }

  /// Dials every paired peer at its last known address.
  ///
  /// Also starts a watchdog that redials any saved peer that is still
  /// offline: right after launch iOS may refuse local connections (network
  /// not up, Local Network permission pending) and a peer that was
  /// asleep comes back later; neither may be announced again over mDNS.
  Future<void> reconnect() async {
    _watchdog ??= Timer.periodic(watchdogEvery, (_) => unawaited(_redial()));
    await _redial(force: true);
  }

  /// How often [reconnect]'s watchdog checks for offline peers.
  static Duration watchdogEvery = const Duration(seconds: 10);

  static (String, int)? _parseHostPort(Object? raw) {
    if (raw is! String) return null;
    final at = raw.lastIndexOf(':');
    if (at <= 0) return null;
    final port = int.tryParse(raw.substring(at + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return (raw.substring(0, at), port);
  }

  Future<void> _redial({bool force = false}) async {
    for (final e in (await _withHostLock(_savedHosts)).entries) {
      if (!force && mesh.connected.contains(e.key)) continue;
      final parsed = _parseHostPort(e.value);
      if (parsed == null) continue;
      _addresses[e.key] = parsed;
      // A phone back from doze still holds a half-open socket that Dart has
      // not marked closed; force redials instead of trusting `isClosed`.
      unawaited(mesh.reach(e.key, parsed.$1, parsed.$2, force: force));
    }
  }

  @override

  /// 1-tap send (FR-03B): pushes [text] to every connected desktop.
  void sendText(String text) {
    final uri = Uri.tryParse(text.trim());
    final isUrl = uri != null && uri.hasScheme && uri.host.isNotEmpty;
    _engine.onLocalChange(
        LocalClip(isUrl ? ClipType.url : ClipType.text, utf8.encode(text)));
  }

  @override
  String get myName => me.name;

  @override
  Future<void> rename(String name) async {
    await ids.rename(name);
    _discovery?.updateRecord(_record);
  }

  @override
  Future<void> forget(String deviceId) async {
    try {
      await mesh.broadcast(
          _envelope(MessageType.deviceRevoked,
              {'reason': 'user_initiated', 'by': me.deviceId}),
          to: deviceId);
    } on Object {
      // Peer may already be offline; local revocation still finishes.
    }
    await mesh.drop(deviceId, VersionNegotiator.wsCloseNotPairedOrRevoked);
    _incoming.removeWhere((_, v) => v.peer == deviceId);
    _addresses.remove(deviceId);
    await store.removeByDeviceId(deviceId);
    await _updateHosts((hosts) => hosts.remove(deviceId));
    trusted.value = store.activeDevices.toList();
  }

  /// Same steps as the desktop sender (`file.offer` → `file.accept`, then
  /// `GET .../status`, `POST .../{item}`, `POST .../finish`, §9).
  @override
  Future<void> sendFile(String deviceId, String path,
      {void Function(int sent, int total)? onProgress}) async {
    final target = await _resolvePeer(deviceId);
    final file = File(path);
    final item = FileOfferItem(
      itemId: 'i0',
      path: file.uri.pathSegments.last,
      size: await file.length(),
      sha256: await computeFileSha256(file),
      mime: 'application/octet-stream',
      modifiedAt: (await file.lastModified()).millisecondsSinceEpoch,
    );
    final tid = _uuid();
    final reply = mesh.messages
        .where((m) =>
            m.peerId == deviceId &&
            m.envelope.payload['transfer_id'] == tid &&
            (m.envelope.type == MessageType.fileAccept ||
                m.envelope.type == MessageType.fileReject))
        .first
        // The computer's user may be reading the "receive?" dialog.
        .timeout(const Duration(seconds: 70));
    reply.ignore();
    await mesh.broadcast(
        _envelope(MessageType.fileOffer, {
          'transfer_id': tid,
          'items': [item.toJson()],
          'manifest': false,
          'total_size': item.size,
          'total_count': 1,
        }),
        to: deviceId);
    if ((await reply).envelope.type != MessageType.fileAccept) {
      throw StateError('the device declined the file');
    }
    final client = await PinnedTransportClient.forIdentity(
        identity: ids, store: store, expectedFp: target.peer.fp);
    client.httpClient.connectionTimeout = const Duration(seconds: 5);
    Uri url(String p) =>
        Uri(scheme: 'https', host: target.host, port: target.port, path: p);
    Future<String> call(String method, String p,
        {Stream<List<int>>? body,
        Map<String, String> headers = const {}}) async {
      final req = await client.httpClient.openUrl(method, url(p));
      headers.forEach(req.headers.set);
      if (body != null) await req.addStream(body);
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}: $text', uri: url(p));
      }
      return text;
    }

    try {
      final base = '/api/v1/file/$tid/${item.itemId}';
      final status = jsonDecode(await call('GET', '$base/status'));
      if (status is! Map<String, dynamic>) {
        throw const ProtocolException(
            ProtocolErrorCode.malformed, 'invalid transfer status');
      }
      if (status['state'] == 'complete') {
        onProgress?.call(item.size, item.size);
      } else {
        final rawOffset = status['offset'];
        if (rawOffset is! int || rawOffset < 0 || rawOffset > item.size) {
          throw const ProtocolException(
              ProtocolErrorCode.internal, 'invalid resume offset');
        }
        var sent = rawOffset;
        onProgress?.call(sent, item.size);
        await call('POST', base,
            headers: {'x-offset': '$rawOffset'},
            body: file.openRead(rawOffset).map((b) {
              sent += b.length;
              onProgress?.call(sent, item.size);
              return b;
            }));
      }
      await call('POST', '/api/v1/file/$tid/finish',
          body: Stream.value(utf8.encode('{}')));
    } finally {
      client.close(force: true);
    }
  }

  Envelope _envelope(MessageType type, Map<String, dynamic> payload) =>
      Envelope(
          type: type,
          msgId: _uuid(),
          origin: me.deviceId,
          hlc: Hlc.now(me.deviceId),
          ts: DateTime.now().millisecondsSinceEpoch,
          payload: payload);

  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<Map<String, dynamic>> _savedHosts() async {
    if (!await _hosts.exists()) return <String, dynamic>{};
    try {
      final raw = jsonDecode(await _hosts.readAsString());
      return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } on FormatException {
      // A torn write must not stop the app from starting: keep the bad file
      // for diagnosis and let discovery/pairing rebuild the list.
      try {
        await _hosts.rename('${_hosts.path}.corrupt');
      } on Object {
        // Best effort; starting beats reporting the rename failure.
      }
      return <String, dynamic>{};
    }
  }

  Future<void> _updateHosts(void Function(Map<String, dynamic>) edit) =>
      _withHostLock(() async {
        final hosts = await _savedHosts();
        edit(hosts);
        await _writeHostsAtomic(hosts);
      });

  Future<T> _withHostLock<T>(Future<T> Function() action) {
    final run = _hostOp.then<T>((_) => action());
    _hostOp = _swallow(run);
    return run;
  }

  static Future<void> _swallow(Future<Object?> future) async {
    try {
      await future;
    } on Object {
      // Errors stay on the caller's future without wedging the queue.
    }
  }

  /// Temp + rename: a kill mid-write must not leave a truncated hosts.json.
  Future<void> _writeHostsAtomic(Map<String, dynamic> hosts) async {
    final tmp = File('${_hosts.path}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(hosts), flush: true);
      await tmp.rename(_hosts.path);
    } on Object {
      try {
        if (await tmp.exists()) await tmp.delete();
      } on Object {
        // Best-effort cleanup before rethrowing.
      }
      rethrow;
    }
  }

  Future<void> close() async {
    _watchdog?.cancel();
    await _discovery?.stop();
    await _pairSub.cancel();
    await _sub.cancel();
    await _msgQueue;
    await _hostOp;
    _engine.dispose();
    await pairing.close();
    await mesh.close();
    await server.close(force: true);
  }
}
