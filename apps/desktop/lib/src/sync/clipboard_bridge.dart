import 'dart:async';
import 'dart:convert';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';

import '../node/desktop_node.dart';

/// The native watchers' channels (§14.1, dropclip_windows/_macos).
class FlutterClipboardChannel implements ClipboardChannel {
  static const _methods = MethodChannel('dropclip/clipboard');
  static const _events = EventChannel('dropclip/clipboard/events');

  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _methods.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      throw ClipboardChannelException(e.code, e.message);
    }
  }

  @override
  Stream<Object?> get events => _events.receiveBroadcastStream();
}

/// Wire bytes for a native snapshot (§11): PNG for images (Windows DIB and
/// macOS TIFF converted here, §14.1), UTF-8 for text. Null when nothing
/// syncable is on the clipboard.
LocalClip? localClipFrom(ClipSnapshot s) {
  if (s.isConcealed) {
    return LocalClip(ClipType.text, Uint8List(0),
        isConcealed: true, changeToken: s.changeToken);
  }
  for (final mime in ClipMime.preference) {
    final item = s.items.where((i) => i.mime == mime).firstOrNull;
    if (item == null) continue;
    final data = Uint8List.fromList(item.data);
    final (type, raw) = switch (mime) {
      ClipMime.png || ClipMime.jpeg => (ClipType.image, data),
      ClipMime.tiff => (ClipType.image, tiffToPng(data)),
      ClipMime.winDibV5 || ClipMime.winDib => (ClipType.image, dibToPng(data)),
      ClipMime.uriList => (ClipType.url, data),
      _ => (ClipType.text, data),
    };
    if (raw.isEmpty) return null;
    return LocalClip(type, raw, changeToken: s.changeToken);
  }
  return null;
}

List<ClipboardItem> clipboardItemsFor(ClipType type, Uint8List raw,
    {required bool windows}) {
  switch (type) {
    case ClipType.text:
      return [ClipboardItem(mime: ClipMime.text, data: raw)];
    case ClipType.url:
      return [
        ClipboardItem(mime: ClipMime.text, data: raw),
        ClipboardItem(mime: ClipMime.uriList, data: raw),
      ];
    case ClipType.image:
      return [
        ClipboardItem(mime: ClipMime.png, data: raw),
        // Most Windows apps paste only CF_DIBV5 / CF_DIB.
        if (windows)
          ClipboardItem(mime: ClipMime.winDibV5, data: pngToDibV5(raw)),
      ];
  }
}

typedef ClipEvent = ({ClipType type, String preview, String from});

/// Tier 1 clipboard sync (T1.9, FR-03A): native watcher → sync engine →
/// `clipboard.update` over the mesh; remote updates → OS clipboard, images
/// fetched from the sender's `GET /api/v1/blob/{id}` (§9.3).
class ClipboardBridge {
  final DesktopNode node;
  final PlatformClipboard native;
  final Stream<ClipSnapshot> changes;
  final bool windows;
  final void Function(ClipEvent event) onClip;
  late final TransportSyncAdapter adapter;
  late final ClipboardSyncEngine engine;
  final _subs = <StreamSubscription<Object?>>[];

  ClipboardBridge({
    required this.node,
    required this.native,
    required this.changes,
    required this.windows,
    required this.onClip,
    required SyncPolicy Function() policy,
  }) {
    adapter = TransportSyncAdapter(
      sendBroadcastEnvelope: (e) => unawaited(node.mesh.broadcast(e)),
      sendPeerEnvelope: (p, e) => unawaited(node.mesh.broadcast(e, to: p)),
      remoteBlobFetcher: (peer, id) => node.fetchFrom(peer, '/api/v1/blob/$id'),
      osWriteClipboard: (type, raw) =>
          native.write(clipboardItemsFor(type, raw, windows: windows)),
      osReadClipboardRaw: () async => (await _current())?.raw,
      osClearClipboard: native.clear,
    );
    engine = ClipboardSyncEngine(
        myId: node.me.deviceId, ports: adapter, policy: policy);
    node.routes['api/v1/blob/'] = _blob;
  }

  Future<void> start() async {
    _subs
      ..add(changes.listen((s) {
        final clip = localClipFrom(s);
        if (clip == null) return;
        engine.onLocalChange(clip);
        if (!clip.isConcealed) onClip(_event(clip.type, clip.raw, 'me'));
      }))
      ..add(node.mesh.messages
          .where((m) => m.envelope.type == MessageType.clipboardUpdate)
          .listen((m) async {
        final u = TransportSyncAdapter.envelopeToClipUpdate(m.envelope);
        if (await engine.onRemoteUpdate(u, m.peerId)) {
          final raw = u.inline ?? Uint8List(0);
          final from = node.trusted.value
                  .where((d) => d.deviceId == m.peerId)
                  .firstOrNull
                  ?.name ??
              m.peerId;
          onClip(_event(u.type, raw, from, size: u.size));
        }
      }));
    await native.start();
  }

  Future<void> sendNow() async {
    final clip = await _current();
    if (clip != null) engine.onLocalChange(LocalClip(clip.type, clip.raw));
  }

  Future<LocalClip?> _current() async {
    final items = await native.read();
    return items == null
        ? null
        : localClipFrom(ClipSnapshot(
            changeToken: 0, isConcealed: false, items: items, ts: 0));
  }

  Response _blob(Request r) {
    try {
      final id = r.url.pathSegments.last;
      return Response.ok(adapter.getLocalBlob(id),
          headers: const {'content-type': 'application/octet-stream'});
    } on ProtocolException catch (e) {
      return Response(e.httpStatus, body: jsonEncode(e.toHttpJson()));
    }
  }

  static ClipEvent _event(ClipType type, Uint8List raw, String from,
          {int? size}) =>
      (
        type: type,
        preview: type == ClipType.image
            ? 'Image · ${((size ?? raw.length) / 1024).ceil()} KB'
            : utf8.decode(raw, allowMalformed: true),
        from: from,
      );

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    engine.dispose();
    await native.stop();
  }
}
