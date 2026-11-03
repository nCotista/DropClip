import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'sync_types.dart';

/// Everything the engine needs from the outside, so the algorithm is pure
/// and testable: transport (T1.5), blob store (T1.10), native clipboard
/// (T1.6/T1.7) and HLC persistence (`state.json`, §15.7).
abstract interface class SyncPorts {
  /// Sends to every connected peer; offline peers go to the outbound queue.
  void broadcast(ClipUpdate update);

  /// Stores > 32 KiB content for the Data Plane; returns its blob id.
  String putBlob(Uint8List raw, Duration ttl);

  /// Persists the HLC after every local tick (§10.1).
  void persistHlc(Hlc hlc);

  /// Clears the OS clipboard only if it still holds [hash] (TTL, §10.2).
  Future<void> clearIfStill(String hash);
}

/// Clipboard sync engine, Protocol Spec §10 (T1.9, FR-03A, FR-04, FR-05).
class ClipboardSyncEngine {
  final String myId;
  final SyncPorts ports;
  final SyncPolicy Function() policy;
  final DateTime Function() now;

  /// Called with log events. Content is never passed here (NFR-S02).
  final void Function(String event)? log;

  Hlc _hlc;
  ClipEntry? _head;
  String? _lastAppliedHash;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final SeenIds seen = SeenIds();
  final History history = History();
  final _ttlTimers = <Timer>[];
  final Random _random;

  ClipboardSyncEngine({
    required this.myId,
    required this.ports,
    required this.policy,
    Hlc? hlc,
    DateTime Function()? now,
    this.log,
    Random? random,
  })  : now = now ?? DateTime.now,
        _hlc = hlc ?? Hlc(l: 0, c: 0, d: myId),
        _random = random ?? Random.secure();

  Hlc get hlc => _hlc;
  ClipEntry? get head => _head;

  /// §10.2 Outbound: the local clipboard changed.
  void onLocalChange(LocalClip clip) {
    // Step 0: sync off or type not allowed.
    final p = policy();
    if (!p.allows(clip.type)) return;

    // Step 1: concealed content is dropped before hashing (§10.4).
    if (clip.isConcealed) {
      log?.call('clipboard.blocked_concealed type=${clip.type.name}');
      return;
    }

    final hash = sha256.convert(clip.raw).toString();

    // Step 2: our own write echoing back within the window (§10.5).
    if (now().isBefore(_suppressUntil) && hash == _lastAppliedHash) {
      log?.call('clipboard.suppressed_echo');
      return;
    }

    // Step 3: size routing.
    final size = clip.raw.length;
    if (size > ProtocolConstants.clipboardMaxSize) {
      log?.call('clipboard.too_large size=$size');
      return;
    }
    final useBlob = size > ProtocolConstants.clipboardInlineThreshold;
    final blobId =
        useBlob ? ports.putBlob(clip.raw, ProtocolConstants.blobTtl) : null;

    // Step 4: advance the HLC, persist it, accept and broadcast.
    final nowMs = now().millisecondsSinceEpoch;
    _hlc = _hlc.tick(nowMs);
    ports.persistHlc(_hlc);
    final update = ClipUpdate(
      msgId: _newMsgId(),
      origin: myId,
      hlc: _hlc,
      ts: nowMs,
      type: clip.type,
      hash: hash,
      size: size,
      ttlSeconds: p.ttlSeconds,
      inline: useBlob ? null : clip.raw,
      blobId: blobId,
    );
    seen.addIfAbsent(update.msgId);
    _accept(update, clip.raw);
    if (update.ttlSeconds != null) _scheduleClear(hash, update.ttlSeconds!);
    ports.broadcast(update);
  }

  /// Call right before writing [hash] content to the OS clipboard (§10.3
  /// step 10, order matters): the watcher's echo of our own write is then
  /// ignored for the next 800 ms, while a deliberate re-copy later is not.
  void noteOwnWrite(String hash) {
    _lastAppliedHash = hash;
    _suppressUntil = now().add(ProtocolConstants.suppressionWindow);
  }

  void _accept(ClipUpdate update, Uint8List raw) {
    final entry = ClipEntry(update, raw);
    _head = entry;
    history.add(entry);
  }

  void _scheduleClear(String hash, int seconds) {
    _ttlTimers.add(Timer(
        Duration(seconds: seconds), () => unawaited(ports.clearIfStill(hash))));
  }

  String _newMsgId() => [for (var i = 0; i < 16; i++) _random.nextInt(256)]
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Cancels pending TTL timers.
  void dispose() {
    for (final t in _ttlTimers) {
      t.cancel();
    }
    _ttlTimers.clear();
  }
}
