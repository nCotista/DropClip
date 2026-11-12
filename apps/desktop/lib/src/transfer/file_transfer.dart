import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:shelf/shelf.dart';

import '../node/desktop_node.dart';

/// Progress of one transfer for the Transfers page (both directions).
typedef TransferUpdate = ({
  String id,
  String name,
  String peer,
  bool incoming,
  int done,
  int total,
  String state, // in_progress | complete | failed | rejected
});

/// File transfer between paired devices (T1.10/T1.11, FR-07/08/09):
/// `file.offer` → `file.accept` over the mesh, then each item streams as
/// `POST /api/v1/file/{tid}/{item}` from the offset `GET .../status` reports,
/// and `POST .../finish` → `file.complete`. Nothing is held in memory whole.
class FileTransfers {
  final DesktopNode node;
  final Directory downloads;

  /// Receiver: whether to take an offer (Auto-Accept or the user, SF-07).
  final Future<bool> Function(String peerName, List<FileOfferItem> items)
      decide;
  final void Function(TransferUpdate update) onUpdate;

  final _incoming =
      <String, ({String peer, Map<String, FileOfferItem> items})>{};
  final _replies = StreamController<Envelope>.broadcast();
  late final StreamingFileReceiver _receiver =
      StreamingFileReceiver(destinationRoot: downloads);
  StreamSubscription<PeerMessage>? _sub;

  FileTransfers(
      {required this.node,
      required this.downloads,
      required this.decide,
      required this.onUpdate}) {
    node.routes['api/v1/file/'] = _route;
    _sub = node.mesh.messages.listen((m) => switch (m.envelope.type) {
          MessageType.fileOffer => unawaited(_offered(m)),
          MessageType.fileAccept ||
          MessageType.fileReject ||
          MessageType.fileComplete =>
            _replies.add(m.envelope),
          _ => null,
        });
  }

  /// Sends [files] to paired [peerId]; resolves when the peer has them all.
  Future<void> send(String peerId, String peerName, List<File> files) async {
    final tid = _uuid();
    final items = [
      for (var i = 0; i < files.length; i++)
        FileOfferItem(
          itemId: 'i$i',
          path: files[i].uri.pathSegments.last,
          size: await files[i].length(),
          sha256: await computeFileSha256(files[i]),
          mime: 'application/octet-stream',
          modifiedAt: (await files[i].lastModified()).millisecondsSinceEpoch,
        ),
    ];
    final total = items.fold<int>(0, (s, i) => s + i.size);
    void update(int done, String state) => onUpdate((
          id: tid,
          name: items.length == 1 ? items.single.path : '${items.length} files',
          peer: peerName,
          incoming: false,
          done: done,
          total: total,
          state: state,
        ));
    update(0, 'in_progress');
    final reply = _replies.stream
        .firstWhere((e) => e.payload['transfer_id'] == tid)
        .timeout(const Duration(seconds: 70));
    await _sendTo(peerId, MessageType.fileOffer, {
      'transfer_id': tid,
      'items': [for (final i in items) i.toJson()],
      'manifest': false,
      'total_size': total,
      'total_count': items.length,
    });
    if ((await reply).type != MessageType.fileAccept) {
      return update(0, 'rejected');
    }
    var sent = 0;
    try {
      for (var i = 0; i < items.length; i++) {
        final base = '/api/v1/file/$tid/${items[i].itemId}';
        final status = jsonDecode(
            utf8.decode(await node.fetchFrom(peerId, '$base/status')));
        final offset = status['offset'] as int;
        sent += offset;
        await node.postTo(peerId, base, files[i].openRead(offset),
            headers: {'x-offset': '$offset'}, onSent: (n) {
          sent += n;
          update(sent, 'in_progress');
        });
      }
      await node.postTo(
          peerId, '/api/v1/file/$tid/finish', Stream.value(utf8.encode('{}')));
      update(total, 'complete');
    } on Object {
      update(sent, 'failed');
      rethrow;
    }
  }

  Future<void> _offered(PeerMessage m) async {
    final p = m.envelope.payload;
    final tid = p['transfer_id'] as String;
    final items = [
      for (final j in p['items'] as List)
        FileOfferItem.fromJson(j as Map<String, dynamic>)
    ];
    final name = node.trusted.value
            .where((d) => d.deviceId == m.peerId)
            .firstOrNull
            ?.name ??
        m.peerId;
    var ok = false;
    try {
      await _receiver.validateOffer(items: items);
      ok = await decide(name, items);
    } on ProtocolException {
      ok = false;
    }
    if (ok) {
      _incoming[tid] =
          (peer: m.peerId, items: {for (final i in items) i.itemId: i});
      onUpdate((
        id: tid,
        name: items.length == 1 ? items.single.path : '${items.length} files',
        peer: name,
        incoming: true,
        done: 0,
        total: items.fold(0, (s, i) => s + i.size),
        state: 'in_progress',
      ));
    }
    await _sendTo(
        m.peerId,
        ok ? MessageType.fileAccept : MessageType.fileReject,
        ok
            ? {
                'transfer_id': tid,
                'accepted_items': [for (final i in items) i.itemId],
                'auto': false
              }
            : {'transfer_id': tid, 'reason': 'user_declined'});
  }

  Future<Response> _route(Request r) async {
    final seg = r.url.pathSegments; // api v1 file <tid> <item>[/status]
    final t = seg.length > 3 ? _incoming[seg[3]] : null;
    final fp = r.context[kPeerFingerprintContextKey] as String?;
    if (t == null ||
        node.store.getByFingerprint(fp ?? '')?.deviceId != t.peer) {
      return _json(404, {'error': 'unknown transfer'});
    }
    if (seg.length == 5 && seg[4] == 'finish') {
      unawaited(_sendTo(t.peer, MessageType.fileComplete, {
        'transfer_id': seg[3],
        'state': 'complete',
        'items': const <Object>[]
      }));
      return _json(200, {'state': 'complete'});
    }
    final item = seg.length > 4 ? t.items[seg[4]] : null;
    if (item == null) return _json(404, {'error': 'unknown item'});
    final part = _receiver.partFileFor(item);
    final have = await part.exists() ? await part.length() : 0;
    if (r.method == 'GET') {
      // §9.7: round down to the chunk boundary and drop the tail.
      final offset = have - have % kStreamingChunkSize;
      if (offset != have) {
        final raf = await part.open(mode: FileMode.append);
        await raf.truncate(offset);
        await raf.close();
      }
      return _json(200, {'offset': offset, 'state': 'in_progress'});
    }
    var at = int.tryParse(r.headers['x-offset'] ?? '') ?? -1;
    if (at == 0 && have > 0) await part.delete();
    try {
      final buf = BytesBuilder(copy: false);
      Future<void> flush() async {
        if (buf.isEmpty) return;
        final chunk = buf.takeBytes();
        await _receiver.writeChunk(item: item, offset: at, chunk: chunk);
        at += chunk.length;
      }

      await for (final data in r.read()) {
        var rest = data;
        while (rest.isNotEmpty) {
          final take = min(kStreamingChunkSize - buf.length, rest.length);
          buf.add(rest.sublist(0, take));
          rest = rest.sublist(take);
          if (buf.length == kStreamingChunkSize) await flush();
        }
      }
      await flush();
      return _json(200,
          {'received_bytes': at, 'state': 'complete', 'saved_path': item.path});
    } on ProtocolException catch (e) {
      return _json(e.httpStatus, e.toHttpJson());
    }
  }

  Future<void> _sendTo(
          String peer, MessageType type, Map<String, dynamic> body) =>
      node.mesh.broadcast(
          Envelope(
              type: type,
              msgId: _uuid(),
              origin: node.me.deviceId,
              hlc: Hlc.now(node.me.deviceId),
              ts: DateTime.now().millisecondsSinceEpoch,
              payload: body),
          to: peer);

  static Response _json(int status, Map<String, dynamic> body) =>
      Response(status,
          body: jsonEncode(body),
          headers: const {'content-type': 'application/json'});

  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _replies.close();
  }
}
