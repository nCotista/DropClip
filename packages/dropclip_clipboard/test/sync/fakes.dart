import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

/// Records every port call so tests can assert on them.
class FakePorts implements SyncPorts {
  final sent = <ClipUpdate>[];
  final blobs = <String, Uint8List>{};
  final persisted = <Hlc>[];
  final cleared = <String>[];

  @override
  void broadcast(ClipUpdate update) => sent.add(update);

  @override
  String putBlob(Uint8List raw, Duration ttl) {
    final id = 'blob-${blobs.length}';
    blobs[id] = raw;
    return id;
  }

  @override
  void persistHlc(Hlc hlc) => persisted.add(hlc);

  @override
  Future<void> clearIfStill(String hash) async => cleared.add(hash);

  final blobsByPeer = <String, Uint8List>{};
  final errors = <String>[];
  final written = <Uint8List>[];

  @override
  Future<Uint8List> fetchBlob(String peer, String blobId) async =>
      blobsByPeer[blobId] ?? Uint8List(0);

  @override
  void sendError(String peer, String code, ClipUpdate update) =>
      errors.add(code);

  @override
  Future<void> writeClipboard(ClipType type, Uint8List raw) async =>
      written.add(raw);
}
