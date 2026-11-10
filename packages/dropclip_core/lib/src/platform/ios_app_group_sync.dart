import 'dart:convert';
import 'dart:io';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../security/trusted_device_store.dart';

/// Cached trusted desktop endpoint stored in iOS App Group `group.com.dropclip.shared`
/// for the native Swift Share Extension (`T3.2`, PROTO §14.3).
class IosSharedPeerEndpoint {
  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final String fingerprint;
  final int updatedAtMs;

  const IosSharedPeerEndpoint({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'device_id': deviceId,
        'name': name,
        'ip': ip,
        'port': port,
        'fp': fingerprint.toLowerCase(),
        'updated_at': updatedAtMs,
      };

  factory IosSharedPeerEndpoint.fromJson(Map<String, dynamic> json) {
    return IosSharedPeerEndpoint(
      deviceId: json['device_id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      fingerprint: (json['fp'] as String).toLowerCase(),
      updatedAtMs: (json['updated_at'] as num).toInt(),
    );
  }
}

/// Enforces the `< 30 MB` Jetsam RAM budget inside the iOS Share Sheet Extension (`NFR-R03B`).
class IosExtensionMemoryGuard {
  static const int maxPeakRamBytes = 30 * 1024 * 1024;
  static const int safeAllocationBudgetBytes = 8 * 1024 * 1024;
  static const int chunkSizeBytes = ProtocolConstants.fileChunkSize;

  int _currentAllocatedBytes = 0;
  int _peakAllocatedBytes = 0;

  int get currentAllocatedBytes => _currentAllocatedBytes;
  int get peakAllocatedBytes => _peakAllocatedBytes;

  void acquireBuffer(int bytes) {
    if (bytes <= 0) {
      throw ArgumentError.value(bytes, 'bytes', 'Must be positive');
    }
    if (_currentAllocatedBytes + bytes > safeAllocationBudgetBytes) {
      throw StateError(
        'iOS Share Extension buffer budget exceeded (< 30 MB Jetsam limit)',
      );
    }
    _currentAllocatedBytes += bytes;
    if (_currentAllocatedBytes > _peakAllocatedBytes) {
      _peakAllocatedBytes = _currentAllocatedBytes;
    }
  }

  void releaseBuffer(int bytes) {
    _currentAllocatedBytes = (_currentAllocatedBytes - bytes).clamp(
      0,
      maxPeakRamBytes,
    );
  }

  /// Simulates streaming a file of [totalBytes] (e.g., 4 GB) in 1 MiB chunks (`Rule #5`).
  int simulateChunkedStream({required int totalBytes}) {
    var offset = 0;
    var chunksSent = 0;
    while (offset < totalBytes) {
      final remaining = totalBytes - offset;
      final chunkLen = remaining < chunkSizeBytes ? remaining : chunkSizeBytes;
      acquireBuffer(chunkLen);
      offset += chunkLen;
      chunksSent++;
      releaseBuffer(chunkLen);
    }
    return chunksSent;
  }
}

/// Synchronizes `group.com.dropclip.shared` container state (`active_peers.json`, `state.json`)
/// between the main iOS app and the native Swift Share Extension (`T3.2`, PROTO §14.3 & §15.7).
class IosAppGroupSync {
  static const String appGroupIdentifier = 'group.com.dropclip.shared';
  static const String keychainIdentityAccount = 'dropclip.identity.p256';
  static const String activePeersFileName = 'active_peers.json';
  static const String stateFileName = 'state.json';

  final Directory containerDirectory;
  final TrustedDeviceStore trustedStore;

  IosAppGroupSync({
    required this.containerDirectory,
    required this.trustedStore,
  });

  File get _peersFile =>
      File('${containerDirectory.path}/$activePeersFileName');
  File get _stateFile => File('${containerDirectory.path}/$stateFileName');

  Future<void> publishActivePeer(IosSharedPeerEndpoint endpoint) async {
    final activeFp = trustedStore.fingerprintOf(endpoint.deviceId);
    if (activeFp == null || activeFp != endpoint.fingerprint.toLowerCase()) {
      throw StateError(
        'Cannot publish untrusted or quarantined peer ${endpoint.deviceId}',
      );
    }
    if (!containerDirectory.existsSync()) {
      await containerDirectory.create(recursive: true);
    }
    await _peersFile.writeAsString(jsonEncode(endpoint.toJson()), flush: true);
  }

  Future<IosSharedPeerEndpoint?> readActivePeer() async {
    if (!_peersFile.existsSync()) return null;
    final map =
        jsonDecode(await _peersFile.readAsString()) as Map<String, dynamic>;
    final endpoint = IosSharedPeerEndpoint.fromJson(map);
    final activeFp = trustedStore.fingerprintOf(endpoint.deviceId);
    if (activeFp == null || activeFp != endpoint.fingerprint) return null;
    return endpoint;
  }

  Future<String> nextHlcHeader({
    required String deviceId,
    required int nowMs,
  }) async {
    var hlc = Hlc(l: nowMs, c: 0, d: deviceId);
    if (_stateFile.existsSync()) {
      final raw =
          jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
      final existing = Hlc.fromJson(raw['hlc'] as Map<String, dynamic>);
      hlc = existing.tick(nowMs);
    } else {
      hlc = hlc.tick(nowMs);
    }
    if (!containerDirectory.existsSync()) {
      await containerDirectory.create(recursive: true);
    }
    await _stateFile.writeAsString(
      jsonEncode(<String, dynamic>{'version': 2, 'hlc': hlc.toJson()}),
      flush: true,
    );
    return hlc.toString();
  }
}
