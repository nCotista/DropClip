import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
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

  MobileNode._(this.ids, this.store, this.mesh, this._hosts,
      this.writeClipboard, this.onReceived)
      : trusted = ValueNotifier(store.activeDevices.toList()) {
    _engine = ClipboardSyncEngine(
      myId: me.deviceId,
      policy: () => const SyncPolicy(types: {ClipType.text, ClipType.url}),
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
        writeClipboard, onReceived);
  }

  HelloPayload get hello => HelloPayload(
      deviceId: me.deviceId,
      name: me.name,
      os: me.os,
      tier: 2,
      appVersion: '1.0.0',
      capabilities: const ['clip.text', 'clip.push'],
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
        qr: qr, me: me, store: store, confirmSas: confirm);
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
        tier: 2);
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

  Future<Map<String, dynamic>> _savedHosts() async => await _hosts.exists()
      ? jsonDecode(await _hosts.readAsString()) as Map<String, dynamic>
      : <String, dynamic>{};

  Future<void> close() async {
    await _sub.cancel();
    _engine.dispose();
    await mesh.close();
  }
}
