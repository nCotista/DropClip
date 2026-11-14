import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../dropclip_core.dart';

/// Keychain / Keystore identifier for ECDSA P-256 private key (§14.4).
const String kIdentityKeyStoreKey = 'dropclip.identity.p256';

/// Keychain / Keystore identifier for 256-bit Trusted Store master key (§14.4).
const String kStoreMasterKeyStoreKey = 'dropclip.store.key';

/// File name for public device identity metadata (§15.1–§15.2).
const String kIdentityFileName = 'identity.json';

/// In-memory [SecureKeyStore] implementation for unit tests & ephemeral nodes.
class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, Uint8List> _store = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async {
    final bytes = _store[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    _store[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

/// Public device identity record (`E-01`, PROTO-DC-V2.0 §4.1 & §15.2).
/// Private key bytes are NEVER stored in this object or in `identity.json`.
class DeviceIdentity {
  final int version;
  final String deviceId;
  final String name;
  final String os;
  final Uint8List certDer;
  final Uint8List certPem;
  final String fp;
  final int createdAt;

  const DeviceIdentity({
    this.version = 1,
    required this.deviceId,
    required this.name,
    required this.os,
    required this.certDer,
    required this.certPem,
    required this.fp,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'device_id': deviceId,
        'name': name,
        'os': os,
        'cert_der': base64Encode(certDer),
        'cert_pem': base64Encode(certPem),
        'fp': fp,
        'created_at': createdAt,
      };

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) {
    final certDer = base64Decode(json['cert_der'] as String);
    final certPem = base64Decode(json['cert_pem'] as String);
    final computedFp = sha256.convert(certDer).toString();
    final storedFp = (json['fp'] as String).toLowerCase();
    if (computedFp != storedFp) {
      throw const FormatException(
        'Identity fingerprint mismatch against cert_der',
      );
    }
    return DeviceIdentity(
      version: (json['version'] as int?) ?? 1,
      deviceId: json['device_id'] as String,
      name: json['name'] as String,
      os: json['os'] as String,
      certDer: certDer,
      certPem: certPem,
      fp: storedFp,
      createdAt: json['created_at'] as int,
    );
  }
}

/// Manages per-device ECDSA P-256 identity generation, reload, and signing (§4.1, T1.2).
class DeviceIdentityManager {
  final Directory storageDir;
  final SecureKeyStore keyStore;
  DeviceIdentity? _identity;

  DeviceIdentityManager({required this.storageDir, required this.keyStore});

  DeviceIdentity get identity {
    final current = _identity;
    if (current == null) {
      throw StateError('DeviceIdentityManager.loadOrCreate() not called');
    }
    return current;
  }

  /// Loads existing identity from [storageDir] & [keyStore], or generates a new
  /// ECDSA P-256 (`prime256v1`) keypair and 10-year self-signed X.509 v3 cert.
  Future<DeviceIdentity> loadOrCreate({
    required String deviceName,
    required String os,
    String? deviceId,
  }) async {
    await storageDir.create(recursive: true);
    final identityFile = File('${storageDir.path}/$kIdentityFileName');
    final existingKey = await keyStore.read(kIdentityKeyStoreKey);

    if (await identityFile.exists() && existingKey != null) {
      final raw =
          jsonDecode(await identityFile.readAsString()) as Map<String, dynamic>;
      return _identity = DeviceIdentity.fromJson(raw);
    }

    final resolvedId = deviceId ?? _generateUuidV4();
    final created = await _generateP256Certificate(
      deviceId: resolvedId,
      deviceName: deviceName,
      os: os,
    );

    await keyStore.write(kIdentityKeyStoreKey, created.keyPem);
    await identityFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(created.identity.toJson()),
      flush: true,
    );
    return _identity = created.identity;
  }

  /// Changes this device's display name (what peers and discovery show).
  /// The key, certificate and device id stay the same, so pairings remain.
  Future<DeviceIdentity> rename(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'is empty');
    final old = identity;
    if (clean == old.name) return old;
    final next = DeviceIdentity(
      version: old.version,
      deviceId: old.deviceId,
      name: clean,
      os: old.os,
      certDer: old.certDer,
      certPem: old.certPem,
      fp: old.fp,
      createdAt: old.createdAt,
    );
    final file = File('${storageDir.path}/$kIdentityFileName');
    // Temp + rename: a kill mid-write must not lose the identity.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(next.toJson()),
        flush: true);
    await tmp.rename(file.path);
    return _identity = next;
  }

  /// Reads the envelope-protected ECDSA P-256 private key PEM from [keyStore].
  Future<Uint8List> loadPrivateKeyPem() async {
    final keyBytes = await keyStore.read(kIdentityKeyStoreKey);
    if (keyBytes == null) {
      throw StateError('ECDSA P-256 private key missing from SecureKeyStore');
    }
    return keyBytes;
  }

  /// Signs [canonicalInput] (UTF-8) with the device's ECDSA P-256 private key
  /// using SHA-256 (`ECDSA_P256_SHA256`), returning a Base64-encoded signature.
  Future<String> signUtf8(String canonicalInput) async {
    final keyPem = await loadPrivateKeyPem();
    try {
      return base64Encode(P256.sign(keyPem, utf8.encode(canonicalInput)));
    } finally {
      keyPem.fillRange(0, keyPem.length, 0);
    }
  }

  /// Verifies a Base64-encoded ECDSA P-256 SHA-256 signature against [certPem].
  static Future<bool> verifyUtf8({
    required String canonicalInput,
    required String signatureBase64,
    required Uint8List certPem,
  }) async {
    final Uint8List sigBytes;
    try {
      sigBytes = base64Decode(signatureBase64);
    } on FormatException {
      return false;
    }
    return P256.verify(certPem, utf8.encode(canonicalInput), sigBytes);
  }

  /// A new key and self-signed certificate (§4.1), in pure Dart.
  static Future<({DeviceIdentity identity, Uint8List keyPem})>
      _generateP256Certificate({
    required String deviceId,
    required String deviceName,
    required String os,
  }) async {
    final made = P256.generate(commonName: 'dropclip-$deviceId');
    return (
      identity: DeviceIdentity(
        deviceId: deviceId,
        name: deviceName,
        os: os,
        certDer: made.certDer,
        certPem: made.certPem,
        fp: sha256.convert(made.certDer).toString(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
      keyPem: made.keyPem,
    );
  }

  static String _generateUuidV4() {
    final rng = Random.secure();
    final b =
        Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int s, int e) =>
        b.sublist(s, e).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }
}
