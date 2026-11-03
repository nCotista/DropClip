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
    final tmp = await Directory.systemTemp.createTemp('dc_sign_');
    try {
      final keyPath = '${tmp.path}/key.pem';
      final msgPath = '${tmp.path}/msg.bin';
      final sigPath = '${tmp.path}/sig.bin';
      await File(keyPath).writeAsBytes(keyPem, flush: true);
      await File(msgPath)
          .writeAsBytes(utf8.encode(canonicalInput), flush: true);

      final args =
          'dgst -sha256 -sign $keyPath -out $sigPath $msgPath'.split(' ');
      final res = await Process.run(_resolveOpenSsl(), args);
      if (res.exitCode != 0) {
        throw StateError('ECDSA P-256 sign failed: ${res.stderr}');
      }
      return base64Encode(await File(sigPath).readAsBytes());
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
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
    final tmp = await Directory.systemTemp.createTemp('dc_verify_');
    try {
      final certPath = '${tmp.path}/cert.pem';
      final pubPath = '${tmp.path}/pub.pem';
      final msgPath = '${tmp.path}/msg.bin';
      final sigPath = '${tmp.path}/sig.bin';
      await File(certPath).writeAsBytes(certPem, flush: true);
      await File(msgPath)
          .writeAsBytes(utf8.encode(canonicalInput), flush: true);
      await File(sigPath).writeAsBytes(sigBytes, flush: true);

      final pubArgs = 'x509 -in $certPath -pubkey -noout'.split(' ');
      final pubRes = await Process.run(_resolveOpenSsl(), pubArgs);
      if (pubRes.exitCode != 0) return false;
      await File(pubPath).writeAsString(pubRes.stdout as String, flush: true);

      final verArgs =
          'dgst -sha256 -verify $pubPath -signature $sigPath $msgPath'
              .split(' ');
      final verifyRes = await Process.run(_resolveOpenSsl(), verArgs);
      return verifyRes.exitCode == 0;
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  static Future<({DeviceIdentity identity, Uint8List keyPem})>
      _generateP256Certificate({
    required String deviceId,
    required String deviceName,
    required String os,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('dc_idgen_');
    try {
      final keyPath = '${tmp.path}/key.pem';
      final certPemPath = '${tmp.path}/cert.pem';
      final certDerPath = '${tmp.path}/cert.der';
      final openssl = _resolveOpenSsl();

      final reqArgs =
          'req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 '
                  '-nodes -keyout $keyPath -out $certPemPath -days 3650 '
                  '-subj /CN=dropclip-$deviceId'
              .split(' ');
      final reqRes = await Process.run(openssl, reqArgs);
      if (reqRes.exitCode != 0) {
        throw StateError('openssl req failed: ${reqRes.stderr}');
      }
      final derArgs =
          'x509 -in $certPemPath -outform DER -out $certDerPath'.split(' ');
      final derRes = await Process.run(openssl, derArgs);
      if (derRes.exitCode != 0) {
        throw StateError('openssl x509 DER failed: ${derRes.stderr}');
      }

      final keyPem = await File(keyPath).readAsBytes();
      final certPem = await File(certPemPath).readAsBytes();
      final certDer = await File(certDerPath).readAsBytes();
      return (
        identity: DeviceIdentity(
          deviceId: deviceId,
          name: deviceName,
          os: os,
          certDer: certDer,
          certPem: certPem,
          fp: sha256.convert(certDer).toString(),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
        keyPem: keyPem,
      );
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  static String _resolveOpenSsl() {
    for (final c in const <String>[
      '/opt/homebrew/bin/openssl',
      '/usr/bin/openssl'
    ]) {
      if (File(c).existsSync()) return c;
    }
    return 'openssl';
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
