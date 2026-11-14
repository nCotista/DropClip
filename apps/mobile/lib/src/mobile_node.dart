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

/// This phone on the network (Tier 2, T2.5): identity, Trusted Store, the
/// Control Plane to paired desktops (the phone always dials, §6.2) and text
/// clipboard sync through [ClipboardSyncEngine] (FR-03B).
class MobileNode implements MobilePeer {
  final DeviceIdentityManager ids;
  final TrustedDeviceStore store;
  final PeerMesh mesh;
  final File _hosts;
  final Future<void> Function(String text) writeClipboard;
  final void Function(String text, String from) onReceived;

  /// The mTLS server paired computers send files and images to (§9).
  final TlsTransportServer server;

  /// Where received files and images are saved.
  final Directory received;

  /// A file or image from [from] is saved at [file].
  final void Function(File file, String from) onFile;

  late final StreamingFileReceiver _receiver =
      StreamingFileReceiver(destinationRoot: received);
  final _incoming =
      <String, ({String peer, Map<String, FileOfferItem> items})>{};
  DiscoveryService? _discovery;
  @override
  final ValueNotifier<List<TrustedDevice>> trusted;
  late final ClipboardSyncEngine _engine;
  late final StreamSubscription<PeerMessage> _sub;

  /// Settings switch: off stops sending and receiving clips.
  final bool Function() syncEnabled;

  MobileNode._(
      this.ids,
      this.store,
      this.mesh,
      this._hosts,
      this.writeClipboard,
      this.onReceived,
      this.syncEnabled,
      this.server,
      this.received,
      this.onFile)
      : trusted = ValueNotifier(store.activeDevices.toList()) {
    String? sender;
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
          // shortcut: images are saved and listed, not put on the phone
          // clipboard (Flutter's clipboard is text only); add a plugin for
          // that when it is needed.
          final f = await StreamingFileReceiver.freeNameFor(File(
              '${received.path}/image-${DateTime.now().millisecondsSinceEpoch}.png'));
          await f.parent.create(recursive: true);
          await f.writeAsBytes(raw);
          onFile(f, sender ?? '');
        },
      ),
    );
    _sub = mesh.messages.listen((m) async {
      final type = m.envelope.type;
      if (type == MessageType.deviceRevoked) {
        // The desktop removed this phone: forget it too (§13.1).
        await store.removeByDeviceId(m.peerId);
        await mesh.drop(m.peerId, VersionNegotiator.wsCloseNotPairedOrRevoked);
        trusted.value = store.activeDevices.toList();
        return;
      }
      if (type == MessageType.fileOffer) return _offered(m);
      if (type != MessageType.clipboardUpdate) return;
      try {
        final u = TransportSyncAdapter.envelopeToClipUpdate(m.envelope);
        sender = _nameOf(m.peerId);
        if (await _engine.onRemoteUpdate(u, m.peerId) &&
            u.inline != null &&
            u.type != ClipType.image) {
          onReceived(utf8.decode(u.inline!), _nameOf(m.peerId));
        }
      } on Object {
        // An image the computer no longer has, or a malformed frame.
      }
    });
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
  }) async {
    final ids = DeviceIdentityManager(
        storageDir: Directory('${dir.path}/identity'), keyStore: keys);
    await ids.loadOrCreate(deviceName: name, os: os);
    final store = TrustedDeviceStore(
        storageDir: Directory('${dir.path}/trust'), keyStore: keys);
    await store.load();
    late MobileNode node;
    final mesh = PeerMesh(identity: ids, store: store, hello: () => node.hello);
    final server = await TlsTransportServer.bindForIdentity(
      identity: ids,
      store: store,
      pinnedHandler: (r) => node._route(r),
      webSocket: (r, fp) => unawaited(mesh.accept(r, fp)),
    );
    return node = MobileNode._(
        ids,
        store,
        mesh,
        File('${dir.path}/hosts.json'),
        writeClipboard,
        onReceived,
        syncEnabled ?? () => true,
        server,
        received ?? Directory('${dir.path}/received'),
        onFile ?? (_, __) {});
  }

  /// Finds paired computers on the Wi-Fi and announces this phone, so it
  /// reconnects after the computer's address changes and shows up in the
  /// computer's Dropzone (§3).
  Future<void> startDiscovery(MdnsBackend backend) async {
    final cache = PeerCache(
        localDeviceId: me.deviceId, trustedFingerprint: store.fingerprintOf);
    cache.changes.listen((peers) async {
      for (final p in peers) {
        if (!p.canAutoConnect || p.state == PeerState.stale) continue;
        final hosts = await _savedHosts();
        final at = '${p.address}:${p.record.port}';
        if (hosts[p.deviceId] != at) {
          hosts[p.deviceId] = at;
          await _saveHosts(hosts);
        }
        unawaited(mesh.reach(p.deviceId, p.address, p.record.port));
      }
    });
    _discovery = DiscoveryService(
      backend: backend,
      cache: cache,
      record: DiscoveryRecord(
        deviceId: me.deviceId,
        name: me.name,
        os: DeviceOs.values.byName(me.os),
        port: server.port,
        fingerprint: me.fp,
        capabilities: const ['clip.text', 'clip.image', 'file'],
      ),
    );
    await _discovery!.start();
  }

  /// `GET` [path] from paired [peerId] over pinned mTLS (e.g. a blob, §9.3).
  Future<Uint8List> _fetch(String peerId, String path) async {
    final at = mesh.linkAddress(peerId);
    final peer = store.getByDeviceId(peerId);
    if (at == null || at.port == null || peer == null) {
      throw StateError('computer is not connected');
    }
    final client = await PinnedTransportClient.forIdentity(
        identity: ids, store: store, expectedFp: peer.fp);
    client.httpClient.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.httpClient.getUrl(
          Uri(scheme: 'https', host: at.host, port: at.port, path: path));
      final res = await req.close();
      final bytes = await res.fold<BytesBuilder>(
          BytesBuilder(copy: false), (b, d) => b..add(d));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }

  /// A computer offers files: paired computers are trusted, so they are
  /// taken (the computer's user chose to send them).
  Future<void> _offered(PeerMessage m) async {
    final p = m.envelope.payload;
    final tid = p['transfer_id'] as String;
    var ok = false;
    try {
      final items = [
        for (final j in p['items'] as List)
          FileOfferItem.fromJson(j as Map<String, dynamic>)
      ];
      await _receiver.validateOffer(items: items);
      _incoming[tid] =
          (peer: m.peerId, items: {for (final i in items) i.itemId: i});
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
    if (seg.length < 5 || seg[2] != 'file') return Response.notFound(null);
    final t = _incoming[seg[3]];
    final fp = r.context[kPeerFingerprintContextKey] as String?;
    if (t == null || store.getByFingerprint(fp ?? '')?.deviceId != t.peer) {
      return _json(404, {'error': 'unknown transfer'});
    }
    if (seg[4] == 'finish') {
      _incoming.remove(seg[3]);
      unawaited(mesh.broadcast(
          _envelope(MessageType.fileComplete, {
            'transfer_id': seg[3],
            'state': 'complete',
            'items': const <Object>[]
          }),
          to: t.peer));
      return _json(200, {'state': 'complete'});
    }
    final item = t.items[seg[4]];
    if (item == null) return _json(404, {'error': 'unknown item'});
    final part = _receiver.partFileFor(item);
    if (r.method == 'GET') {
      // Start over: a broken upload resends from 0 (no resume on phones).
      if (await part.exists()) await part.delete();
      return _json(200, {'offset': 0, 'state': 'in_progress'});
    }
    var at = 0;
    try {
      final buf = BytesBuilder(copy: false);
      Future<void> write(Uint8List chunk) async {
        final file =
            await _receiver.appendChunk(item: item, offset: at, chunk: chunk);
        at += chunk.length;
        if (file != null) onFile(file, _nameOf(t.peer));
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
      return _json(200, {'received_bytes': at, 'state': 'complete'});
    } on ProtocolException catch (e) {
      return _json(e.httpStatus, e.toHttpJson());
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
      appVersion: '1.0.3',
      capabilities: _tier == 3
          ? const ['clip.text', 'clip.image', 'file']
          : const ['clip.text', 'clip.push', 'clip.image', 'file'],
      tombstonesHash: '',
      tombstoneCount: 0);

  /// Pairs with the desktop at [host]:[port] using the PIN it shows (§5,
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
        qr: qr, me: me, store: store, confirmSas: confirm, tier: _tier);
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
        tier: _tier);
    return _connect(d, host, port);
  }

  /// Remembers where the desktop is and dials it.
  Future<TrustedDevice> _connect(TrustedDevice d, String host, int port) async {
    if (d.certPem != null) server.addTrustedPeerCert(d.certPem!);
    final hosts = await _savedHosts();
    hosts[d.deviceId] = '$host:$port';
    // Temp + rename: a kill mid-write must not leave a truncated hosts.json.
    final tmp = File('${_hosts.path}.tmp');
    await tmp.writeAsString(jsonEncode(hosts), flush: true);
    await tmp.rename(_hosts.path);
    trusted.value = store.activeDevices.toList();
    unawaited(mesh.reach(d.deviceId, host, port));
    return d;
  }

  /// Dials every paired desktop at its last known address.
  Future<void> reconnect() async {
    for (final e in (await _savedHosts()).entries) {
      final addr = e.value;
      if (addr is! String) continue;
      final at = addr.lastIndexOf(':');
      if (at <= 0) continue;
      final port = int.tryParse(addr.substring(at + 1));
      if (port == null) continue;
      // A phone back from doze still holds a half-open socket that Dart has
      // not marked closed; force redials instead of trusting `isClosed`.
      unawaited(mesh.reach(e.key, addr.substring(0, at), port, force: true));
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
  Future<void> forget(String deviceId) async {
    await mesh.broadcast(
        _envelope(MessageType.deviceRevoked,
            {'reason': 'user_initiated', 'by': me.deviceId}),
        to: deviceId);
    await mesh.drop(deviceId, VersionNegotiator.wsCloseNotPairedOrRevoked);
    await store.removeByDeviceId(deviceId);
    final hosts = await _savedHosts()
      ..remove(deviceId);
    await _saveHosts(hosts);
    trusted.value = store.activeDevices.toList();
  }

  /// Same steps as the desktop sender (`file.offer` → `file.accept`, then
  /// `GET .../status`, `POST .../{item}`, `POST .../finish`, §9).
  @override
  Future<void> sendFile(String deviceId, String path,
      {void Function(int sent, int total)? onProgress}) async {
    final at = mesh.linkAddress(deviceId);
    final peer = store.getByDeviceId(deviceId);
    if (at == null || at.port == null || peer == null) {
      throw StateError('computer is not connected');
    }
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
      throw StateError('the computer declined the file');
    }
    final client = await PinnedTransportClient.forIdentity(
        identity: ids, store: store, expectedFp: peer.fp);
    client.httpClient.connectionTimeout = const Duration(seconds: 5);
    Uri url(String p) =>
        Uri(scheme: 'https', host: at.host, port: at.port, path: p);
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
      final offset = (jsonDecode(await call('GET', '$base/status'))
          as Map<String, dynamic>)['offset'] as int;
      var sent = offset;
      onProgress?.call(sent, item.size);
      await call('POST', base,
          headers: {'x-offset': '$offset'},
          body: file.openRead(offset).map((b) {
            sent += b.length;
            onProgress?.call(sent, item.size);
            return b;
          }));
      await call('POST', '/api/v1/file/$tid/finish',
          body: Stream.value(utf8.encode('{}')));
    } finally {
      client.close();
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

  /// Temp + rename, like `_connect`: a kill mid-write must not leave a
  /// truncated hosts.json.
  Future<void> _saveHosts(Map<String, dynamic> hosts) async {
    final tmp = File('${_hosts.path}.tmp');
    await tmp.writeAsString(jsonEncode(hosts), flush: true);
    await tmp.rename(_hosts.path);
  }

  Future<void> close() async {
    await _discovery?.stop();
    await _sub.cancel();
    _engine.dispose();
    await mesh.close();
    await server.close(force: true);
  }
}
