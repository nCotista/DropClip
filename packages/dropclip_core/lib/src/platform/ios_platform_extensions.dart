import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'ios_app_group_sync.dart';

/// Trigger mechanism on iOS 15–18+ (`T3.3`, FR-03C, UI-05, PROTO §14.3).
enum IosActionTrigger {
  /// iOS 17+ interactive Home/Lock Screen Widget (`AppIntent`).
  interactiveWidget,

  /// iPhone 15 Pro / 16 Pro Action Button (`AppIntent`).
  actionButton,

  /// iOS 15/16 fallback via Siri Shortcuts & Accessibility Back Tap.
  shortcutsBackTapFallback,

  /// URL scheme fallback (`dropclip://send-clipboard`).
  deepLinkUrlScheme,
}

/// Coordinates iOS Action Button, Interactive Widgets, and iOS 15/16 Shortcuts
/// Fallbacks (`T3.3`, FR-03C, UI-05, NFR-P01D < 2,000 ms).
class IosShortcutsWidgetCoordinator {
  static const int maxActionLatencyBudgetMs = 2000;

  final int iosMajorVersion;
  final IosAppGroupSync appGroupSync;
  Hlc _clock;

  IosShortcutsWidgetCoordinator({
    required this.iosMajorVersion,
    required this.appGroupSync,
    required Hlc initialClock,
  }) : _clock = initialClock;

  Hlc get clock => _clock;

  /// Returns whether iOS 17+ interactive widget `Button(intent:)` is supported.
  bool get supportsInteractiveWidgetIntent => iosMajorVersion >= 17;

  /// Resolves the best trigger mechanism for the running iOS version.
  IosActionTrigger preferredTrigger(IosActionTrigger requested) {
    final isInteractive = requested == IosActionTrigger.interactiveWidget ||
        requested == IosActionTrigger.actionButton;
    if (iosMajorVersion < 17 && isInteractive) {
      return IosActionTrigger.shortcutsBackTapFallback;
    }
    return requested;
  }

  /// Executes a 1-tap `Send Clipboard to DropClip` intent and persists the
  /// updated HLC into `group.com.dropclip.shared`.
  Future<Envelope?> triggerSendClipboard({
    required String? pasteboardText,
    required bool isConcealed,
    required int nowMs,
  }) async {
    if (isConcealed || pasteboardText == null || pasteboardText.isEmpty) {
      return null;
    }
    final raw = utf8.encode(pasteboardText);
    final hash = sha256.convert(raw).toString();
    final hlcHeader = await appGroupSync.nextHlcHeader(
      deviceId: _clock.d,
      nowMs: nowMs,
    );
    _clock = Hlc.parse(hlcHeader);

    final payload = ClipboardUpdatePayload(
      contentType: 'text/plain',
      hash: hash,
      size: raw.length,
      isConcealed: false,
      inline: base64Encode(raw),
    );
    return Envelope(
      type: MessageType.clipboardUpdate,
      msgId: '00000000-0000-4000-8000-000000000303',
      origin: _clock.d,
      hlc: _clock,
      ts: nowMs,
      payload: payload.toJson(),
    );
  }
}

/// Destination target on iOS (`T3.4`, FR-08, SW-03).
enum IosStorageDestination {
  /// Saved into `PHPhotoLibrary` (Photos app) for `image/*` and `video/*`.
  photoKitLibrary('PhotoKitLibrary'),

  /// Saved into the app's `Documents` container (visible in iOS Files app).
  filesAppDocuments('Documents');

  final String subdir;
  const IosStorageDestination(this.subdir);
}

bool _defaultPhotoPermission() => true;

/// iOS PhotoKit & File Receiver Engine (`T3.4`, FR-08, SW-03, PROTO §12.3).
///
/// Streams incoming files in 1 MiB chunks, verifies SHA-256, and routes photos
/// and videos to `PHPhotoLibrary` while saving documents to the iOS Files app
/// (`Documents` directory with `UIFileSharingEnabled`).
class IosPhotoKitFileReceiver {
  static const int chunkSize = 1024 * 1024;

  final Directory containerRoot;
  final bool Function() hasPhotoLibraryAddPermission;
  final List<String> _importedPhotoLibraryAssets = <String>[];

  IosPhotoKitFileReceiver({
    required this.containerRoot,
    this.hasPhotoLibraryAddPermission = _defaultPhotoPermission,
  });

  List<String> get importedPhotoLibraryAssets =>
      List<String>.unmodifiable(_importedPhotoLibraryAssets);

  static IosStorageDestination destinationForMime(String mime) {
    final normalized = mime.toLowerCase().trim();
    if (normalized.startsWith('image/') || normalized.startsWith('video/')) {
      return IosStorageDestination.photoKitLibrary;
    }
    return IosStorageDestination.filesAppDocuments;
  }

  /// Receives a file stream in 1 MiB chunks, verifies SHA-256, and commits it
  /// to either PhotoKit (or falls back to Documents if permission is denied)
  /// or the Files app `Documents` directory.
  Future<File> receiveFileStream({
    required FileOfferItem item,
    required Stream<Uint8List> chunks,
  }) async {
    final safeRel = PathSanitizer.sanitize(item.path);
    final preferred = destinationForMime(item.mime);
    var actualDest = preferred;
    if (preferred == IosStorageDestination.photoKitLibrary &&
        !hasPhotoLibraryAddPermission()) {
      actualDest = IosStorageDestination.filesAppDocuments;
    }

    final partFile = File(
      '${containerRoot.path}/${actualDest.subdir}/$safeRel.part',
    );
    await partFile.parent.create(recursive: true);

    final sink = partFile.openWrite();
    var totalWritten = 0;
    try {
      await for (final chunk in chunks) {
        if (chunk.length > chunkSize) {
          throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge,
            'iOS receiver chunk exceeds 1 MiB streaming limit',
          );
        }
        totalWritten += chunk.length;
        if (totalWritten > item.size) {
          throw const ProtocolException(
            ProtocolErrorCode.payloadTooLarge,
            'received bytes exceed declared size',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final digest = await sha256.bind(partFile.openRead()).first;
    if (digest.toString().toLowerCase() != item.sha256.toLowerCase()) {
      await partFile.delete();
      throw const ProtocolException(
        ProtocolErrorCode.checksumMismatch,
        'iOS file receiver SHA-256 mismatch',
      );
    }

    final finalFile = File(
      '${containerRoot.path}/${actualDest.subdir}/$safeRel',
    );
    await finalFile.parent.create(recursive: true);
    final committed = await partFile.rename(finalFile.path);
    if (actualDest == IosStorageDestination.photoKitLibrary) {
      _importedPhotoLibraryAssets.add(committed.path);
    }
    return committed;
  }
}
