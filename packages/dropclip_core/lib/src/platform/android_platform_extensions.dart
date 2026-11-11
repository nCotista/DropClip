import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'android_service_bridge.dart';

/// Quick Settings Tile & Transient Focus Activity coordinator for Android 10–15
/// (`T2.2`, PROTO-DC-V2.0 §9.4 & §14.2, ADR-007).
///
/// On Android 14+ (API 34+), `TileService.startActivityAndCollapse` MUST be
/// invoked with a `PendingIntent` targeting the transparent transient-focus
/// `DropClipTileReaderActivity` so `onWindowFocusChanged(true)` grants
/// legitimate foreground clipboard access within < 1,500 ms (NFR-P01C).
class AndroidQuickSettingsTileCoordinator {
  static const int maxLatencyBudgetMs = 1500;

  final int sdkInt;
  final AndroidServiceBridge serviceBridge;
  final Future<Envelope> Function(ClipboardUpdatePayload payload, Hlc hlc)?
      onDispatchClipboard;

  Hlc _clock;
  int _pendingIntentLaunchCount = 0;
  int _lastActionLatencyMs = 0;

  AndroidQuickSettingsTileCoordinator({
    required this.sdkInt,
    required this.serviceBridge,
    required Hlc initialClock,
    this.onDispatchClipboard,
  }) : _clock = initialClock;

  /// Android 14 (API 34+) requires `PendingIntent` for `startActivity`.
  bool get requiresPendingIntent => sdkInt >= 34;
  int get pendingIntentLaunchCount => _pendingIntentLaunchCount;
  int get lastActionLatencyMs => _lastActionLatencyMs;
  Hlc get clock => _clock;

  /// Handles 1-click Quick Settings Tile tap: launches transient activity via
  /// `PendingIntent`, waits for window focus, reads clipboard (suppressing
  /// `EXTRA_IS_SENSITIVE`), and dispatches `clipboard.update`.
  Future<Envelope?> onTileTapped({
    required bool usedPendingIntent,
    required bool hasWindowFocus,
    required bool isSensitive,
    required String? clipboardText,
    required int startedAtMs,
    required int focusedAtMs,
  }) async {
    if (requiresPendingIntent && !usedPendingIntent) {
      throw StateError(
        'API $sdkInt requires PendingIntent for startActivityAndCollapse',
      );
    }
    if (!hasWindowFocus) {
      throw StateError(
        'Cannot read Android 10+ clipboard before onWindowFocusChanged(true)',
      );
    }
    _pendingIntentLaunchCount++;
    _lastActionLatencyMs = focusedAtMs - startedAtMs;

    final forwarded = serviceBridge.onQuickSettingsClipboardSample(
      text: clipboardText ?? '',
      isSensitive: isSensitive,
      timestampMs: focusedAtMs,
    );
    if (!forwarded || clipboardText == null || clipboardText.isEmpty) {
      return null;
    }

    final raw = utf8.encode(clipboardText);
    final hash = sha256.convert(raw).toString();
    _clock = _clock.send(focusedAtMs);
    final payload = ClipboardUpdatePayload(
      contentType: 'text/plain',
      hash: hash,
      size: raw.length,
      isConcealed: false,
      inline: base64Encode(raw),
    );
    if (onDispatchClipboard != null) {
      return onDispatchClipboard!(payload, _clock);
    }
    return Envelope(
      type: MessageType.clipboardUpdate,
      msgId: '00000000-0000-4000-8000-000000000202',
      origin: _clock.d,
      hlc: _clock,
      ts: focusedAtMs,
      payload: payload.toJson(),
    );
  }
}

/// Android Inbound Clipboard Receiver & Sync Manager (`T2.3`, FR-03B).
///
/// Receives `clipboard.update` from desktop/peer nodes while the Android
/// `connectedDevice` foreground service is active and writes to
/// `ClipboardManager.setPrimaryClip` with LWW HLC and echo suppression.
class AndroidClipboardInboundReceiver {
  static const int suppressionWindowMs = 800;

  final AndroidServiceBridge serviceBridge;
  final Future<Uint8List> Function(String blobId)? blobDownloader;
  Hlc _clock;
  String? _lastAppliedHash;
  int _suppressUntilMs = 0;
  Uint8List? _lastImagePng;

  AndroidClipboardInboundReceiver({
    required this.serviceBridge,
    required Hlc initialClock,
    this.blobDownloader,
  }) : _clock = initialClock;

  Hlc get clock => _clock;
  String? get lastAppliedHash => _lastAppliedHash;
  Uint8List? get lastImagePng => _lastImagePng;

  /// Applies an inbound `clipboard.update` envelope if its HLC wins LWW.
  Future<bool> onInboundClipboardEnvelope(
    Envelope envelope, {
    required int nowMs,
  }) async {
    if (envelope.type != MessageType.clipboardUpdate) {
      return false;
    }
    final payload = ClipboardUpdatePayload.fromJson(envelope.payload);
    if (payload.isConcealed) {
      return false;
    }
    if (envelope.hlc.compareTo(_clock) <= 0 && _lastAppliedHash != null) {
      return false;
    }
    _clock = _clock.receive(envelope.hlc, nowMs);

    final Uint8List rawBytes;
    if (payload.inline != null) {
      rawBytes = Uint8List.fromList(base64Decode(payload.inline!));
    } else if (payload.blobId != null && blobDownloader != null) {
      rawBytes = await blobDownloader!(payload.blobId!);
    } else {
      return false;
    }

    final actualHash = sha256.convert(rawBytes).toString();
    if (actualHash.toLowerCase() != payload.hash.toLowerCase()) {
      throw const ProtocolException(
        ProtocolErrorCode.checksumMismatch,
        'inbound Android clipboard SHA-256 mismatch',
      );
    }

    _lastAppliedHash = actualHash;
    _suppressUntilMs = nowMs + suppressionWindowMs;

    if (payload.contentType == 'text/plain' ||
        payload.contentType == 'text/uri-list') {
      await serviceBridge.applyInboundClipboard(utf8.decode(rawBytes));
    } else if (payload.contentType == 'image/png' ||
        payload.contentType == 'image/jpeg') {
      _lastImagePng = rawBytes;
    }
    return true;
  }

  bool isEchoSuppressed(String candidateHash, int nowMs) =>
      nowMs < _suppressUntilMs && candidateHash == _lastAppliedHash;
}

/// Destination collection in Android Scoped Storage (`T2.4`, SW-03).
enum AndroidMediaCollection {
  images('Pictures/DropClip'),
  videos('Movies/DropClip'),
  downloads('Download/DropClip');

  final String relativeFolder;
  const AndroidMediaCollection(this.relativeFolder);
}

/// Android Scoped Storage (`MediaStore` / `Downloads`) & Share Target Engine
/// (`T2.4`, FR-07, FR-08, SW-03, PROTO-DC-V2.0 §12.3 & §14.2).
///
/// Saves incoming files without `MANAGE_EXTERNAL_STORAGE` by routing images
/// and videos to `MediaStore` collections and general documents to `Downloads`
/// in 1 MiB streaming chunks.
class AndroidMediaStoreEngine {
  static const int chunkSize = 1024 * 1024;
  final Directory scopedStorageRoot;

  const AndroidMediaStoreEngine({required this.scopedStorageRoot});

  /// Classifies MIME type into the appropriate Android Scoped Storage bucket.
  static AndroidMediaCollection collectionForMime(String mime) {
    final normalized = mime.toLowerCase().trim();
    if (normalized.startsWith('image/')) {
      return AndroidMediaCollection.images;
    }
    if (normalized.startsWith('video/')) {
      return AndroidMediaCollection.videos;
    }
    return AndroidMediaCollection.downloads;
  }

  /// Streams an incoming file in 1 MiB chunks into the scoped storage bucket
  /// and verifies SHA-256 before publishing (`IS_PENDING = 0` equivalent).
  Future<File> saveIncomingStream({
    required FileOfferItem item,
    required Stream<List<int>> byteStream,
  }) async {
    final safeRel = PathSanitizer.sanitize(item.path);
    final collection = collectionForMime(item.mime);
    final dirPath = '${scopedStorageRoot.path}/${collection.relativeFolder}';
    final pendingFile = File('$dirPath/.$safeRel.pending');
    await pendingFile.parent.create(recursive: true);

    final sink = pendingFile.openWrite();
    var written = 0;
    try {
      await for (final block in byteStream) {
        if (block.length > chunkSize) {
          throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge,
            'chunk exceeds 1 MiB streaming limit',
          );
        }
        written += block.length;
        if (written > item.size) {
          throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge,
            'stream exceeds declared file size',
          );
        }
        sink.add(block);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final digest = await sha256.bind(pendingFile.openRead()).first;
    if (digest.toString().toLowerCase() != item.sha256.toLowerCase()) {
      await pendingFile.delete();
      throw const ProtocolException(
        ProtocolErrorCode.checksumMismatch,
        'MediaStore file SHA-256 verification failed',
      );
    }

    final publishedFile = File(
      '${scopedStorageRoot.path}/${collection.relativeFolder}/$safeRel',
    );
    await publishedFile.parent.create(recursive: true);
    return pendingFile.rename(publishedFile.path);
  }
}
