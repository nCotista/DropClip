import 'dart:collection';
import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:meta/meta.dart';

/// Clipboard content kinds (`config.sync_types`, Protocol Spec §15.6).
enum ClipType { text, url, image }

/// A local clipboard change from the native watcher (T1.6/T1.7), already
/// normalized to wire bytes (§11: UTF-8 text, PNG/JPEG).
class LocalClip {
  final ClipType type;

  /// Wire bytes. Native watchers MUST NOT read concealed content (§10.4),
  /// so this is empty when [isConcealed].
  final Uint8List raw;
  final bool isConcealed;

  LocalClip(this.type, this.raw, {this.isConcealed = false});
}

/// The fields of a `clipboard.update` message (§7, §10.2). JSON framing is
/// the protocol package's job (T0.2); the engine works on this value.
@immutable
class ClipUpdate {
  final String msgId;
  final String origin;
  final Hlc hlc;
  final int ts;
  final ClipType type;

  /// SHA-256 hex of the wire bytes.
  final String hash;
  final int size;
  final bool isConcealed;
  final int? ttlSeconds;

  /// Exactly one of [inline] (≤ 32 KiB) and [blobId] (Data Plane) is set.
  final Uint8List? inline;
  final String? blobId;

  const ClipUpdate({
    required this.msgId,
    required this.origin,
    required this.hlc,
    required this.ts,
    required this.type,
    required this.hash,
    required this.size,
    this.isConcealed = false,
    this.ttlSeconds,
    this.inline,
    this.blobId,
  });
}

/// The accepted head of the cluster clipboard (§10.1 `_head`).
class ClipEntry {
  final ClipUpdate update;
  final Uint8List raw;
  const ClipEntry(this.update, this.raw);
}

/// What the user allows (§15.6), read on every event so changes apply at
/// once.
class SyncPolicy {
  final bool enabled;
  final Set<ClipType> types;
  final int? ttlSeconds;
  const SyncPolicy(
      {this.enabled = true,
      this.types = const {ClipType.text, ClipType.url, ClipType.image},
      this.ttlSeconds});

  bool allows(ClipType t) => enabled && types.contains(t);
}

/// Set of the most recent [capacity] ids (§10.1 `_seenMsgIds`, LRU(200)).
class SeenIds {
  final int capacity;
  final _ids = <String>{};
  SeenIds([this.capacity = 200]);

  /// Adds [id]; false when it was already seen (a duplicate).
  bool addIfAbsent(String id) {
    if (!_ids.add(id)) return false;
    if (_ids.length > capacity) _ids.remove(_ids.first);
    return true;
  }

  int get length => _ids.length;
}

/// Last [capacity] accepted entries, newest last (§10.1 `_history`, Ring(20)).
class History {
  final int capacity;
  final _items = Queue<ClipEntry>();
  History([this.capacity = 20]);

  void add(ClipEntry e) {
    _items.addLast(e);
    if (_items.length > capacity) _items.removeFirst();
  }

  List<ClipEntry> get items => List.unmodifiable(_items);
}
