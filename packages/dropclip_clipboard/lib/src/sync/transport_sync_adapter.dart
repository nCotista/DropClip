import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'sync_engine.dart';
import 'sync_types.dart';

/// Connects [ClipboardSyncEngine] to the WebSocket Control Plane (T1.5),
/// HTTP Data Plane blob cache (T1.10), and OS Clipboard (T1.6/T1.7) to
/// complete T1.9 end-to-end transport wiring.
class TransportSyncAdapter implements SyncPorts {
  final void Function(Envelope envelope) sendBroadcastEnvelope;
  final void Function(String peerId, Envelope envelope)? sendPeerEnvelope;
  final Future<Uint8List> Function(String peerId, String blobId)?
      remoteBlobFetcher;
  final Future<void> Function(ClipType type, Uint8List raw)? osWriteClipboard;
  final Future<Uint8List?> Function()? osReadClipboardRaw;
  final Future<void> Function()? osClearClipboard;
  final void Function(Hlc hlc)? onPersistHlc;
  final int Function() _nowMs;

  final Map<String, _StoredBlob> _blobs = <String, _StoredBlob>{};
  Hlc? _lastPersistedHlc;
  int _blobCounter = 0;

  TransportSyncAdapter({
    required this.sendBroadcastEnvelope,
    this.sendPeerEnvelope,
    this.remoteBlobFetcher,
    this.osWriteClipboard,
    this.osReadClipboardRaw,
    this.osClearClipboard,
    this.onPersistHlc,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  Hlc? get lastPersistedHlc => _lastPersistedHlc;

  /// Converts a [ClipUpdate] to a normative `clipboard.update` [Envelope].
  static Envelope clipUpdateToEnvelope(ClipUpdate update) {
    final contentType = switch (update.type) {
      ClipType.text => 'text/plain',
      ClipType.url => 'text/uri-list',
      ClipType.image => 'image/png',
    };
    final payload = ClipboardUpdatePayload(
      contentType: contentType,
      hash: update.hash,
      size: update.size,
      isConcealed: update.isConcealed,
      ttlSeconds: update.ttlSeconds,
      inline: update.inline != null ? base64Encode(update.inline!) : null,
      blobId: update.blobId,
    );
    return Envelope(
      type: MessageType.clipboardUpdate,
      msgId: update.msgId,
      origin: update.origin,
      hlc: update.hlc,
      ts: update.ts,
      payload: payload.toJson(),
    );
  }

  /// Parses a `clipboard.update` [Envelope] into a [ClipUpdate].
  static ClipUpdate envelopeToClipUpdate(Envelope env) {
    if (env.type != MessageType.clipboardUpdate) {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'expected clipboard.update envelope',
      );
    }
    final parsed = ClipboardUpdatePayload.fromJson(env.payload);
    final clipType = switch (parsed.contentType) {
      'text/plain' => ClipType.text,
      'text/uri-list' => ClipType.url,
      'image/png' || 'image/jpeg' => ClipType.image,
      _ => throw const ProtocolException(
          ProtocolErrorCode.unsupportedType,
          'unsupported clipboard content_type',
        ),
    };
    return ClipUpdate(
      msgId: env.msgId,
      origin: env.origin,
      hlc: env.hlc,
      ts: env.ts,
      type: clipType,
      hash: parsed.hash,
      size: parsed.size,
      isConcealed: parsed.isConcealed,
      ttlSeconds: parsed.ttlSeconds,
      inline: parsed.inline != null
          ? Uint8List.fromList(base64Decode(parsed.inline!))
          : null,
      blobId: parsed.blobId,
    );
  }

  @override
  void broadcast(ClipUpdate update) {
    sendBroadcastEnvelope(clipUpdateToEnvelope(update));
  }

  @override
  String putBlob(Uint8List raw, Duration ttl) {
    if (raw.length > ProtocolConstants.clipboardMaxSize) {
      throw const ProtocolException(
        ProtocolErrorCode.payloadTooLarge,
        'clipboard blob exceeds 32 MiB quota',
      );
    }
    _blobCounter++;
    final id = 'blob-${_nowMs()}-$_blobCounter';
    _blobs[id] = _StoredBlob(
      bytes: Uint8List.fromList(raw),
      expiresAtMs: _nowMs() + ttl.inMilliseconds,
    );
    return id;
  }

  /// Serves a locally cached blob for `GET /api/v1/blob/{id}`.
  Uint8List getLocalBlob(String blobId) {
    final entry = _blobs[blobId];
    if (entry == null || _nowMs() > entry.expiresAtMs) {
      _blobs.remove(blobId);
      throw const ProtocolException(
        ProtocolErrorCode.blobExpired,
        'requested clipboard blob is missing or expired',
      );
    }
    return entry.bytes;
  }

  @override
  void persistHlc(Hlc hlc) {
    _lastPersistedHlc = hlc;
    onPersistHlc?.call(hlc);
  }

  @override
  Future<void> clearIfStill(String hash) async {
    if (osReadClipboardRaw == null || osClearClipboard == null) return;
    final current = await osReadClipboardRaw!();
    if (current == null) return;
    final currentHash = sha256.convert(current).toString();
    if (currentHash == hash) {
      await osClearClipboard!();
    }
  }

  @override
  Future<Uint8List> fetchBlob(String peer, String blobId) async {
    if (remoteBlobFetcher != null) {
      return remoteBlobFetcher!(peer, blobId);
    }
    return getLocalBlob(blobId);
  }

  @override
  void sendError(String peer, String code, ClipUpdate update) {
    if (sendPeerEnvelope == null) return;
    final errCode =
        ProtocolErrorCode.tryFromCode(code) ?? ProtocolErrorCode.malformed;
    final ex = ProtocolException(
      errCode,
      'clipboard update rejected: $code',
      refMsgId: update.msgId,
    );
    final env = Envelope(
      type: MessageType.error,
      msgId: update.msgId,
      origin: update.origin,
      hlc: update.hlc,
      ts: _nowMs(),
      payload: ex.toWsPayload(),
    );
    sendPeerEnvelope!(peer, env);
  }

  @override
  Future<void> writeClipboard(ClipType type, Uint8List raw) async {
    if (osWriteClipboard != null) {
      await osWriteClipboard!(type, raw);
    }
  }
}

class _StoredBlob {
  final Uint8List bytes;
  final int expiresAtMs;

  const _StoredBlob({required this.bytes, required this.expiresAtMs});
}

