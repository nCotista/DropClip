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

  /// Downloads a blob from [peer] (`GET /api/v1/blob/{id}`, §10.3 step 7).
  Future<Uint8List> fetchBlob(String peer, String blobId);

  /// Tells [peer] its update was rejected (`E_CHECKSUM_MISMATCH`,
  /// `E_MALFORMED`).
  void sendError(String peer, String code, ClipUpdate update);

  /// Writes wire bytes to the OS clipboard in native form (§11, §14.1).
  Future<void> writeClipboard(ClipType type, Uint8List raw);
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
  Timer? _persistDebounce;

  /// Tier 1–2 write received clips to the OS clipboard (`clip.push`);
  /// Tier 3 (iOS) only keeps them for the widget / foreground (§10.6).
  final bool canPush;

  ClipboardSyncEngine({
    required this.myId,
    required this.ports,
    required this.policy,
    Hlc? hlc,
    DateTime Function()? now,
    this.log,
    Random? random,
    this.canPush = true,
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

  /// §10.3 Inbound: a peer sent `clipboard.update`. Returns whether the
  /// update was accepted as the new head.
  Future<bool> onRemoteUpdate(ClipUpdate u, String sender) async {
    final nowMs = now().millisecondsSinceEpoch;

    // Step 1: a clock far in the future must not win LWW.
    if (u.hlc.l - nowMs > ProtocolConstants.maxClockDriftMs) {
      log?.call('clipboard.clock_drift_exceeded');
      return false;
    }
    // Step 2: merge the HLC first, always; persist debounced (≤ 1 s).
    _hlc = _hlc.merge(u.hlc, nowMs);
    _persistDebounce?.cancel();
    _persistDebounce =
        Timer(const Duration(seconds: 1), () => ports.persistHlc(_hlc));

    // Step 3: our own update coming back.
    if (u.origin == myId) return false;
    // Step 4: duplicate (reconnect / outbound queue resend).
    if (!seen.addIfAbsent(u.msgId)) return false;
    // Step 5: policy.
    if (!policy().allows(u.type) || u.isConcealed) return false;
    // Step 6: Last-Writer-Wins by HLC.
    if (_isStale(u)) {
      log?.call('clipboard.dropped_stale_hlc');
      return false;
    }

    // Step 7: the bytes, inline or from the sender's blob store.
    final Uint8List raw;
    if (u.blobId != null) {
      raw = await ports.fetchBlob(sender, u.blobId!);
      // A newer update may have won while we were downloading.
      if (_isStale(u)) return false;
    } else if (u.inline != null) {
      raw = u.inline!;
    } else {
      ports.sendError(sender, 'E_MALFORMED', u);
      return false;
    }

    // Step 8: integrity and image magic bytes (§11.3).
    if (sha256.convert(raw).toString() != u.hash) {
      ports.sendError(sender, 'E_CHECKSUM_MISMATCH', u);
      return false;
    }
    if (u.type == ClipType.image && !_isPngOrJpeg(raw)) {
      ports.sendError(sender, 'E_MALFORMED', u);
      return false;
    }

    _accept(u, raw);
    // Step 9: Tier 3 keeps it for the widget / foreground only.
    if (!canPush) return true;
    // Step 10–11: suppression first, then write (order matters).
    noteOwnWrite(u.hash);
    await ports.writeClipboard(u.type, raw);
    // Step 12: TTL.
    if (u.ttlSeconds != null) _scheduleClear(u.hash, u.ttlSeconds!);
    return true;
  }

  bool _isStale(ClipUpdate u) =>
      _head != null && u.hlc.compareTo(_head!.update.hlc) < 0;

  static bool _isPngOrJpeg(Uint8List b) =>
      (b.length >= 8 &&
          b[0] == 0x89 &&
          b[1] == 0x50 &&
          b[2] == 0x4E &&
          b[3] == 0x47 &&
          b[4] == 0x0D &&
          b[5] == 0x0A &&
          b[6] == 0x1A &&
          b[7] == 0x0A) ||
      (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF);

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
    // Flush a pending merge so the clock never goes backwards on restart.
    if (_persistDebounce?.isActive ?? false) {
      _persistDebounce!.cancel();
      ports.persistHlc(_hlc);
    }
  }
}
