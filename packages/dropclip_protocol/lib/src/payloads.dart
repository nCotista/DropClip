import 'package:meta/meta.dart';

import 'constants.dart';
import 'errors.dart';
import 'path_sanitizer.dart';

/// `hello` and `hello.ack` payload (PROTO-DC-V2.0 §7.4.1).
@immutable
class HelloPayload {
  final String deviceId;
  final String name;
  final String os;
  final int tier;
  final int v;
  final int minV;
  final String appVersion;
  final List<String> capabilities;
  final String tombstonesHash;
  final int tombstoneCount;
  final Map<String, dynamic>? clipHead;

  const HelloPayload({
    required this.deviceId,
    required this.name,
    required this.os,
    required this.tier,
    this.v = ProtocolConstants.protocolVersion,
    this.minV = ProtocolConstants.minSupportedProtocolVersion,
    required this.appVersion,
    required this.capabilities,
    required this.tombstonesHash,
    required this.tombstoneCount,
    this.clipHead,
  });

  factory HelloPayload.fromJson(Map<String, dynamic> json) {
    if (json['device_id'] is! String ||
        json['name'] is! String ||
        json['os'] is! String ||
        json['tier'] is! int ||
        json['v'] is! int ||
        json['min_v'] is! int ||
        json['app_version'] is! String ||
        json['capabilities'] is! List ||
        json['tombstones_hash'] is! String ||
        json['tombstone_count'] is! int) {
      throw const ProtocolException(
          ProtocolErrorCode.malformed, 'invalid hello payload');
    }
    return HelloPayload(
      deviceId: json['device_id'] as String,
      name: json['name'] as String,
      os: json['os'] as String,
      tier: json['tier'] as int,
      v: json['v'] as int,
      minV: json['min_v'] as int,
      appVersion: json['app_version'] as String,
      capabilities:
          (json['capabilities'] as List).map((e) => e.toString()).toList(),
      tombstonesHash: json['tombstones_hash'] as String,
      tombstoneCount: json['tombstone_count'] as int,
      clipHead: json['clip_head'] is Map
          ? Map<String, dynamic>.from(json['clip_head'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'os': os,
        'tier': tier,
        'v': v,
        'min_v': minV,
        'app_version': appVersion,
        'capabilities': capabilities,
        'tombstones_hash': tombstonesHash,
        'tombstone_count': tombstoneCount,
        'clip_head': clipHead,
      };
}

/// `clipboard.update` payload (PROTO-DC-V2.0 §7.4.2 & §18.5).
@immutable
class ClipboardUpdatePayload {
  static const Set<String> allowedContentTypes = {
    'text/plain',
    'text/uri-list',
    'image/png',
    'image/jpeg',
  };

  final String contentType;
  final String hash;
  final int size;
  final bool isConcealed;
  final int? ttlSeconds;
  final String? inline;
  final String? blobId;
  final Map<String, dynamic> meta;

  ClipboardUpdatePayload({
    required this.contentType,
    required this.hash,
    required this.size,
    this.isConcealed = false,
    this.ttlSeconds,
    this.inline,
    this.blobId,
    this.meta = const {'width': null, 'height': null, 'dpi': null},
  }) {
    if (!allowedContentTypes.contains(contentType)) {
      throw const ProtocolException(
          ProtocolErrorCode.unsupportedType, 'unsupported content_type');
    }
    if (isConcealed ||
        size < 0 ||
        (ttlSeconds != null && (ttlSeconds! < 5 || ttlSeconds! > 3600))) {
      throw const ProtocolException(
          ProtocolErrorCode.malformed, 'invalid concealed, size, or ttl');
    }
    if (size > ProtocolConstants.clipboardMaxSize) {
      throw const ProtocolException(
          ProtocolErrorCode.payloadTooLarge, 'clipboard > 32 MiB');
    }
    final mustUseBlob = contentType.startsWith('image/') ||
        size > ProtocolConstants.clipboardInlineThreshold;
    if (mustUseBlob
        ? (blobId == null || inline != null)
        : (inline == null || blobId != null)) {
      throw const ProtocolException(
          ProtocolErrorCode.malformed, 'invalid inline/blob_id routing');
    }
  }

  factory ClipboardUpdatePayload.fromJson(Map<String, dynamic> json) {
    if (json['content_type'] is! String ||
        json['hash'] is! String ||
        json['size'] is! int ||
        json['is_concealed'] is! bool) {
      throw const ProtocolException(
          ProtocolErrorCode.malformed, 'invalid clipboard.update');
    }
    return ClipboardUpdatePayload(
      contentType: json['content_type'] as String,
      hash: json['hash'] as String,
      size: json['size'] as int,
      isConcealed: json['is_concealed'] as bool,
      ttlSeconds: json['ttl_seconds'] as int?,
      inline: json['inline'] as String?,
      blobId: json['blob_id'] as String?,
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : const {'width': null, 'height': null, 'dpi': null},
    );
  }

  Map<String, dynamic> toJson() => {
        'content_type': contentType,
        'hash': hash,
        'size': size,
        'is_concealed': isConcealed,
        'ttl_seconds': ttlSeconds,
        'inline': inline,
        'blob_id': blobId,
        'meta': meta,
      };
}

/// `file.offer` item (PROTO-DC-V2.0 §7.4.4).
@immutable
class FileOfferItem {
  final String itemId;
  final String path;
  final int size;
  final String sha256;
  final String mime;
  final int modifiedAt;

  FileOfferItem({
    required this.itemId,
    required String path,
    required this.size,
    required this.sha256,
    required this.mime,
    required this.modifiedAt,
  }) : path = _sanitizeOrThrow(path);

  static String _sanitizeOrThrow(String raw) {
    try {
      return PathSanitizer.sanitize(raw);
    } on InvalidPathException catch (e) {
      throw ProtocolException(ProtocolErrorCode.invalidPath, e.reason);
    }
  }

  factory FileOfferItem.fromJson(Map<String, dynamic> json) {
    if (json['item_id'] is! String ||
        json['path'] is! String ||
        json['size'] is! int ||
        json['sha256'] is! String ||
        json['mime'] is! String ||
        json['modified_at'] is! int) {
      throw const ProtocolException(
          ProtocolErrorCode.malformed, 'invalid file.offer item');
    }
    return FileOfferItem(
      itemId: json['item_id'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      sha256: json['sha256'] as String,
      mime: json['mime'] as String,
      modifiedAt: json['modified_at'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'path': path,
        'size': size,
        'sha256': sha256,
        'mime': mime,
        'modified_at': modifiedAt,
      };
}

/// Signed Cluster Revocation Token (PROTO-DC-V2.0 §7.4.10 & §13.2).
@immutable
class RevocationBroadcastToken {
  final String revokerId;
  final String revokedId;
  final String revokedFp;
  final int timestamp;
  final String signature;

  const RevocationBroadcastToken({
    required this.revokerId,
    required this.revokedId,
    required this.revokedFp,
    required this.timestamp,
    required this.signature,
  });

  String get signingInput =>
      'dropclip-revoke-v1:$revokerId:$revokedId:$revokedFp:$timestamp';

  factory RevocationBroadcastToken.fromJson(Map<String, dynamic> json) {
    if (json['revoker_id'] is! String ||
        json['revoked_id'] is! String ||
        json['revoked_fp'] is! String ||
        json['timestamp'] is! int ||
        json['signature'] is! String) {
      throw const ProtocolException(
          ProtocolErrorCode.malformed, 'invalid revocation_token');
    }
    return RevocationBroadcastToken(
      revokerId: json['revoker_id'] as String,
      revokedId: json['revoked_id'] as String,
      revokedFp: (json['revoked_fp'] as String).toLowerCase().trim(),
      timestamp: json['timestamp'] as int,
      signature: json['signature'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'revoker_id': revokerId,
        'revoked_id': revokedId,
        'revoked_fp': revokedFp,
        'timestamp': timestamp,
        'signature': signature,
      };
}
