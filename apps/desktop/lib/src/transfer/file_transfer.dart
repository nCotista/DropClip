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

/// One accepted incoming transfer.
class _Incoming {
  final String peer, peerName, name;
  final Map<String, FileOfferItem> items;
  final int total;

  /// Bytes on disk per item, including finished ones.
  final received = <String, int>{};

  /// Items whose SHA-256 was verified and whose `.part` was renamed.
  final completed = <String>{};

  /// Created on acceptance; later Settings changes only affect new offers.
  final StreamingFileReceiver receiver;
  Timer? stall;

  _Incoming(this.peer, this.peerName, this.items, this.receiver)
      : name = items.length == 1
            ? items.values.single.path
            : '${items.length} files',
        total = items.values.fold(0, (s, i) => s + i.size);

  int get done => received.values.fold(0, (s, n) => s + n);
}

/// File transfer between paired devices (T1.10/T1.11, FR-07/08/09):
/// `file.offer` → `file.accept` over the mesh, then each item streams as
/// `POST /api/v1/file/{tid}/{item}` from the offset `GET .../status` reports,
/// and `POST .../finish` → `file.complete`. Nothing is held in memory whole.
class FileTransfers {
  final DesktopNode node;

  /// Where incoming files land. Settings can change it while the app runs.
  Directory _downloads;

  Directory get downloads => _downloads;

  /// Receiver: whether to take an offer (Auto-Accept or the user, SF-07).
  final Future<bool> Function(String peerName, List<FileOfferItem> items)
      decide;
  final void Function(TransferUpdate update) onUpdate;

  /// How long the receiver's answer may take (the user reads a dialog).
  final Duration offerTimeout;

  /// An incoming transfer with no data for this long is shown as failed.
  final Duration stallTimeout;

  final _incoming = <String, _Incoming>{};
  final _replies = StreamController<Envelope>.broadcast();
  StreamSubscription<PeerMessage>? _sub;

  FileTransfers({
    required this.node,
    required Directory downloads,
    required this.decide,
    required this.onUpdate,
    this.offerTimeout = const Duration(seconds: 70),
    this.stallTimeout = const Duration(seconds: 60),
  }) : _downloads = downloads {
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

  /// Points new incoming transfers at [dir]; accepted ones keep theirs.
  void setDestination(Directory dir) {
    if (dir.path == _downloads.path) return;
    _downloads = dir;
  }

  /// Sends [files] to paired [peerId]; resolves when the peer has them all.
  /// Throws (after reporting `failed`) when the peer is not connected, does
  /// not answer, or the upload breaks.
  Future<void> send(String peerId, String peerName, List<File> files) async {
    final tid = _uuid();
    var total = 0, sent = 0;
    final name = files.length == 1
        ? files.single.uri.pathSegments.last
        : '${files.length} files';
    void update(int done, String state) => onUpdate((
          id: tid,
          name: name,
          peer: peerName,
          incoming: false,
          done: done,
          total: total,
          state: state,
        ));
    try {
      if (!node.mesh.connected.contains(peerId)) {
        throw StateError('$peerName is not connected');
      }
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
      total = items.fold<int>(0, (s, i) => s + i.size);
      update(0, 'in_progress');
      final reply = _replies.stream
          .firstWhere((e) => e.payload['transfer_id'] == tid)
          .timeout(offerTimeout);
      // If the offer itself fails, nobody awaits the reply any more.
      reply.ignore();
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
      for (var i = 0; i < items.length; i++) {
        final base = '/api/v1/file/$tid/${items[i].itemId}';
        final status = jsonDecode(
            utf8.decode(await node.fetchFrom(peerId, '$base/status')));
        final rawOffset = status['offset'];
        final offset =
            rawOffset is int ? rawOffset.clamp(0, items[i].size).toInt() : 0;
        sent += offset;
        // Already verified: a body would trip the offset check. An empty
        // file is only complete once its empty body has created it.
        if (status['state'] == 'complete') continue;
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
    final String tid;
    final List<FileOfferItem> items;
    try {
      tid = p['transfer_id'] as String;
      final rawItems = p['items'] as List;
      if (rawItems.length > ProtocolConstants.maxItemsPerTransfer) {
        throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge, 'too many items in file.offer');
      }
      items = [
        for (final j in rawItems)
          FileOfferItem.fromJson(j as Map<String, dynamic>)
      ];
    } on Object {
      // A malformed offer must not escape as an unhandled async error.
      final replyTid = p['transfer_id'];
      await _sendTo(m.peerId, MessageType.fileReject, {
        'transfer_id': replyTid is String ? replyTid : '',
        'reason': 'malformed',
      });
      return;
    }
    final name = node.trusted.value
            .where((d) => d.deviceId == m.peerId)
            .firstOrNull
            ?.name ??
        m.peerId;
    var ok = false;
    final receiver = StreamingFileReceiver(destinationRoot: _downloads);
    try {
      await receiver.validateOffer(items: items);
      ok = await decide(name, items);
    } on ProtocolException {
      ok = false;
    }
    if (ok) {
      final t = _incoming[tid] = _Incoming(
          m.peerId, name, {for (final i in items) i.itemId: i}, receiver);
      _report(tid, t, 'in_progress');
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

  /// Tells the Transfers page where incoming [t] stands and (re)arms its
  /// stall timer: a sender that vanished must not leave it "in progress".
  void _report(String tid, _Incoming t, String state) {
    t.stall?.cancel();
    if (state == 'in_progress') {
      t.stall = Timer(stallTimeout, () {
        if (identical(_incoming[tid], t)) {
          _incoming.remove(tid);
          _report(tid, t, 'failed');
        }
      });
    }
    onUpdate((
      id: tid,
      name: t.name,
      peer: t.peerName,
      incoming: true,
      done: state == 'complete' ? t.total : t.done,
      total: t.total,
      state: state,
    ));
  }

  Future<Response> _route(Request r) async {
    final seg = r.url.pathSegments; // api v1 file <tid> <item>[/status]
    final tid = seg.length > 3 ? seg[3] : '';
    final t = _incoming[tid];
    final fp = r.context[kPeerFingerprintContextKey] as String?;
    if (t == null ||
        node.store.getByFingerprint(fp ?? '')?.deviceId != t.peer) {
      return _json(404, {'error': 'unknown transfer'});
    }
    if (seg.length == 5 && seg[4] == 'finish') {
      // "finish" is not proof the bytes arrived: require every item (including
      // 0-byte items) to be uploaded, verified, and renamed onto disk.
      final missing = [
        for (final i in t.items.values)
          if (!t.completed.contains(i.itemId)) i.itemId
      ];
      if (missing.isNotEmpty) {
        _incoming.remove(tid);
        _report(tid, t, 'failed');
        unawaited(_sendTo(t.peer, MessageType.fileComplete, {
          'transfer_id': tid,
          'state': 'failed',
          'code': 'E_INCOMPLETE',
          'items': [
            for (final id in missing) {'item_id': id}
          ],
        }));
        return _json(409, {'error': 'incomplete', 'missing': missing});
      }
      _incoming.remove(tid);
      _report(tid, t, 'complete');
      unawaited(_sendTo(t.peer, MessageType.fileComplete, {
        'transfer_id': tid,
        'state': 'complete',
        'items': const <Object>[]
      }));
      return _json(200, {'state': 'complete'});
    }
    final item = seg.length > 4 ? t.items[seg[4]] : null;
    if (item == null) return _json(404, {'error': 'unknown item'});
    final part = t.receiver.partFileFor(item);
    final have = await part.exists() ? await part.length() : 0;
    if (r.method == 'GET') {
      if (t.completed.contains(item.itemId)) {
        return _json(200, {'offset': item.size, 'state': 'complete'});
      }
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
    var saved = item.path;
    try {
      final buf = BytesBuilder(copy: false);
      Future<void> write(Uint8List chunk) async {
        final file =
            await t.receiver.appendChunk(item: item, offset: at, chunk: chunk);
        at += chunk.length;
        if (file != null) {
          saved = file.uri.pathSegments.last;
          t.completed.add(item.itemId);
        }
        t.received[item.itemId] = at;
        if (identical(_incoming[tid], t)) _report(tid, t, 'in_progress');
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
      // The tail, or the whole of an empty file (which has no bytes to
      // trigger a write but must still be created).
      if (buf.isNotEmpty || (item.size == 0 && at == 0)) {
        await write(buf.takeBytes());
      }
      return _json(200,
          {'received_bytes': at, 'state': 'complete', 'saved_path': saved});
    } on ProtocolException catch (e) {
      if (_incoming.remove(tid) != null) _report(tid, t, 'failed');
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
    for (final t in _incoming.values) {
      t.stall?.cancel();
    }
    _incoming.clear();
    await _sub?.cancel();
    await _replies.close();
  }
}
