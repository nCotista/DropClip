import 'dart:convert';
import 'dart:io';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:meta/meta.dart';

import 'streaming_file_engine.dart';

/// Normative 64 MiB checkpoint interval (PROTO-DC-V2.0 §9.7 & §12.4, T1.11).
const int kCheckpointIntervalBytes = 64 * 1024 * 1024;

/// Maximum age of an inactive `.part` file before garbage collection (24h).
const int kPartFileMaxAgeMs = 24 * 60 * 60 * 1000;

/// Persistent checkpoint metadata for a resumable transfer item (§12.4).
@immutable
class ResumableTransferCheckpoint {
  final String transferId;
  final String itemId;
  final String relativePath;
  final int totalBytes;
  final int checkpointOffset;
  final String checkpointSha256;
  final String expectedFileSha256;
  final int updatedAtMs;

  const ResumableTransferCheckpoint({
    required this.transferId,
    required this.itemId,
    required this.relativePath,
    required this.totalBytes,
    required this.checkpointOffset,
    required this.checkpointSha256,
    required this.expectedFileSha256,
    required this.updatedAtMs,
  });

  factory ResumableTransferCheckpoint.fromJson(Map<String, dynamic> json) {
    return ResumableTransferCheckpoint(
      transferId: json['transfer_id'] as String,
      itemId: json['item_id'] as String,
      relativePath: json['relative_path'] as String,
      totalBytes: json['total_bytes'] as int,
      checkpointOffset: json['checkpoint_offset'] as int,
      checkpointSha256: json['checkpoint_sha256'] as String,
      expectedFileSha256: json['expected_file_sha256'] as String,
      updatedAtMs: json['updated_at_ms'] as int,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'transfer_id': transferId,
        'item_id': itemId,
        'relative_path': relativePath,
        'total_bytes': totalBytes,
        'checkpoint_offset': checkpointOffset,
        'checkpoint_sha256': checkpointSha256,
        'expected_file_sha256': expectedFileSha256,
        'updated_at_ms': updatedAtMs,
      };
}

/// Manages 64 MiB transfer checkpoints in `transfers.json`, re-hashes `.part`
/// files on resume (§12.4), and purges stale `.part` files > 24 hours (T1.11).
class ResumableCheckpointStore {
  final Directory stateDirectory;
  final Directory downloadDirectory;
  final int checkpointIntervalBytes;
  final int Function() _nowMs;

  final Map<String, ResumableTransferCheckpoint> _checkpoints =
      <String, ResumableTransferCheckpoint>{};

  ResumableCheckpointStore({
    required this.stateDirectory,
    required this.downloadDirectory,
    this.checkpointIntervalBytes = kCheckpointIntervalBytes,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  File get stateFile => File('${stateDirectory.path}/transfers.json');

  String _key(String transferId, String itemId) => '$transferId::$itemId';

  List<ResumableTransferCheckpoint> get allCheckpoints =>
      _checkpoints.values.toList(growable: false);

  ResumableTransferCheckpoint? getCheckpoint(
    String transferId,
    String itemId,
  ) =>
      _checkpoints[_key(transferId, itemId)];

  Future<void> load() async {
    _checkpoints.clear();
    if (!await stateFile.exists()) return;
    final raw = await stateFile.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['checkpoints'] is! List) return;
    for (final entry in decoded['checkpoints'] as List<dynamic>) {
      if (entry is Map) {
        final cp = ResumableTransferCheckpoint.fromJson(
          Map<String, dynamic>.from(entry),
        );
        _checkpoints[_key(cp.transferId, cp.itemId)] = cp;
      }
    }
  }

  Future<void> _save() async {
    await stateDirectory.create(recursive: true);
    final tmp = File('${stateFile.path}.tmp');
    final body = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'checkpoints': _checkpoints.values.map((e) => e.toJson()).toList(),
    });
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(stateFile.path);
  }

  /// Records a checkpoint when `bytesWritten` crosses a multiple of
  /// [checkpointIntervalBytes] (default 64 MiB).
  Future<ResumableTransferCheckpoint?> recordProgressIfBoundary({
    required String transferId,
    required FileOfferItem item,
    required int bytesWritten,
  }) async {
    if (bytesWritten <= 0 ||
        bytesWritten >= item.size ||
        bytesWritten % checkpointIntervalBytes != 0) {
      return null;
    }
    final safeRel = PathSanitizer.sanitize(item.path);
    final partFile = File('${downloadDirectory.path}/$safeRel.part');
    if (!await partFile.exists()) return null;

    final prefixSha = await computeFileSha256(
      partFile,
      maxBytes: bytesWritten,
    );
    final cp = ResumableTransferCheckpoint(
      transferId: transferId,
      itemId: item.itemId,
      relativePath: safeRel,
      totalBytes: item.size,
      checkpointOffset: bytesWritten,
      checkpointSha256: prefixSha,
      expectedFileSha256: item.sha256,
      updatedAtMs: _nowMs(),
    );
    _checkpoints[_key(transferId, item.itemId)] = cp;
    await _save();
    return cp;
  }

  /// Verifies the existing `.part` file on disk by streaming SHA-256 up to the
  /// last recorded checkpoint (`checkpointOffset`), truncating any unaligned
  /// tail bytes per PROTO-DC-V2.0 §12.4. Returns the safe resume offset (or 0).
  Future<int> prepareResumeOffset({
    required String transferId,
    required FileOfferItem item,
  }) async {
    final cp = getCheckpoint(transferId, item.itemId);
    final safeRel = PathSanitizer.sanitize(item.path);
    final partFile = File('${downloadDirectory.path}/$safeRel.part');
    if (cp == null || !await partFile.exists()) {
      return 0;
    }
    final diskLen = await partFile.length();
    if (diskLen < cp.checkpointOffset) {
      await clearCheckpoint(transferId, item.itemId, deletePartFile: true);
      return 0;
    }
    if (diskLen > cp.checkpointOffset) {
      final raf = await partFile.open(mode: FileMode.append);
      try {
        await raf.truncate(cp.checkpointOffset);
      } finally {
        await raf.close();
      }
    }
    final actualPrefixSha = await computeFileSha256(
      partFile,
      maxBytes: cp.checkpointOffset,
    );
    if (actualPrefixSha.toLowerCase() != cp.checkpointSha256.toLowerCase()) {
      await clearCheckpoint(transferId, item.itemId, deletePartFile: true);
      return 0;
    }
    return cp.checkpointOffset;
  }

  Future<void> clearCheckpoint(
    String transferId,
    String itemId, {
    bool deletePartFile = false,
  }) async {
    final removed = _checkpoints.remove(_key(transferId, itemId));
    if (deletePartFile && removed != null) {
      final partFile =
          File('${downloadDirectory.path}/${removed.relativePath}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }
    }
    await _save();
  }

  /// Deletes `.part` files and checkpoints older than [maxAgeMs] (default 24h).
  Future<int> purgeExpiredPartFiles({int maxAgeMs = kPartFileMaxAgeMs}) async {
    final now = _nowMs();
    final expiredKeys = <String>[];
    for (final entry in _checkpoints.entries) {
      if (now - entry.value.updatedAtMs > maxAgeMs) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      final cp = _checkpoints.remove(key)!;
      final partFile =
          File('${downloadDirectory.path}/${cp.relativePath}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }
    }
    if (expiredKeys.isNotEmpty) {
      await _save();
    }
    return expiredKeys.length;
  }
}

