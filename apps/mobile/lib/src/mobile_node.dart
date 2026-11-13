import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  @override
  final ValueNotifier<List<TrustedDevice>> trusted;
  late final ClipboardSyncEngine _engine;
  late final StreamSubscription<PeerMessage> _sub;

  /// Settings switch: off stops sending and receiving clips.
  final bool Function() syncEnabled;

  MobileNode._(this.ids, this.store, this.mesh, this._hosts,
      this.writeClipboard, this.onReceived, this.syncEnabled)
      : trusted = ValueNotifier(store.activeDevices.toList()) {
    _engine = ClipboardSyncEngine(
      myId: me.deviceId,
      policy: () => SyncPolicy(
          enabled: syncEnabled(), types: const {ClipType.text, ClipType.url}),
      ports: TransportSyncAdapter(
        sendBroadcastEnvelope: (e) => unawaited(mesh.broadcast(e)),
        osWriteClipboard: (_, raw) => writeClipboard(utf8.decode(raw)),
      ),
    );
    _sub = mesh.messages.listen((m) async {
      if (m.envelope.type == MessageType.deviceRevoked) {
        // The desktop removed this phone: forget it too (§13.1).
        await store.removeByDeviceId(m.peerId);
        await mesh.drop(m.peerId, VersionNegotiator.wsCloseNotPairedOrRevoked);
        trusted.value = store.activeDevices.toList();
        return;
      }
      if (m.envelope.type != MessageType.clipboardUpdate) return;
      final u = TransportSyncAdapter.envelopeToClipUpdate(m.envelope);
      if (u.inline != null && await _engine.onRemoteUpdate(u, m.peerId)) {
        final from = trusted.value.where((d) => d.deviceId == m.peerId);
        onReceived(
            utf8.decode(u.inline!), from.isEmpty ? m.peerId : from.first.name);
      }
    });
  }

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
  }) async {
    final ids = DeviceIdentityManager(
        storageDir: Directory('${dir.path}/identity'), keyStore: keys);
    await ids.loadOrCreate(deviceName: name, os: os);
    final store = TrustedDeviceStore(
        storageDir: Directory('${dir.path}/trust'), keyStore: keys);
    await store.load();
    late MobileNode node;
    final mesh = PeerMesh(identity: ids, store: store, hello: () => node.hello);
    return node = MobileNode._(ids, store, mesh, File('${dir.path}/hosts.json'),
        writeClipboard, onReceived, syncEnabled ?? () => true);
  }

  HelloPayload get hello => HelloPayload(
      deviceId: me.deviceId,
      name: me.name,
      os: me.os,
      tier: _tier,
      appVersion: '1.0.0',
      capabilities:
          _tier == 3 ? const ['clip.text'] : const ['clip.text', 'clip.push'],
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
    final hosts = await _savedHosts();
    hosts[d.deviceId] = '$host:$port';
    await _hosts.writeAsString(jsonEncode(hosts));
    trusted.value = store.activeDevices.toList();
    unawaited(mesh.reach(d.deviceId, host, port));
    return d;
  }

  /// Dials every paired desktop at its last known address.
  Future<void> reconnect() async {
    for (final e in (await _savedHosts()).entries) {
      final addr = e.value as String;
      final at = addr.lastIndexOf(':');
      unawaited(mesh.reach(
          e.key, addr.substring(0, at), int.parse(addr.substring(at + 1))));
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
    await _hosts.writeAsString(jsonEncode(hosts));
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

  Future<Map<String, dynamic>> _savedHosts() async => await _hosts.exists()
      ? jsonDecode(await _hosts.readAsString()) as Map<String, dynamic>
      : <String, dynamic>{};

  Future<void> close() async {
    await _sub.cancel();
    _engine.dispose();
    await mesh.close();
  }
}
