library dropclip_core;

import 'dart:typed_data';

export 'src/logging_scrubber.dart';
export 'src/pairing/pairing_engine.dart';
export 'src/platform/android_service_bridge.dart';
export 'src/revocation/revocation_manager.dart';
export 'src/security/device_identity.dart';
export 'src/security/trusted_device_store.dart';
export 'src/test_cluster.dart';

/// Abstract interface for OS-level secure keystore operations (PROTO-DC-V2.0 §14.4)
abstract interface class SecureKeyStore {
  /// Reads a sensitive key from secure storage. Returns null if not found.
  Future<Uint8List?> read(String key);

  /// Writes a sensitive key to secure storage.
  Future<void> write(String key, Uint8List value);

  /// Deletes a key from secure storage.
  Future<void> delete(String key);
}
