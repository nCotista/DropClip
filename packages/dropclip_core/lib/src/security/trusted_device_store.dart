import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../dropclip_core.dart';

/// File name for encrypted trusted device store (§15.1 & §15.3).
const String kTrustedDevicesFileName = 'trusted_devices.json.enc';

/// Trusted peer record (`E-02`, PROTO-DC-V2.0 §15.3).
class TrustedDevice {
  final String deviceId;
  final String name;
  final String os;
  final int tier;
  final String fp;
  final Uint8List? certPem;
  final int pairedAt;
  final int lastSeenAt;
  final String status;

  const TrustedDevice({
    required this.deviceId,
    required this.name,
    required this.os,
    required this.tier,
    required this.fp,
    this.certPem,
    required this.pairedAt,
    required this.lastSeenAt,
    this.status = 'active',
  });

  TrustedDevice copyWith({
    String? name,
    int? lastSeenAt,
    String? status,
    Uint8List? certPem,
  }) =>
      TrustedDevice(
        deviceId: deviceId,
        name: name ?? this.name,
        os: os,
        tier: tier,
        fp: fp,
        certPem: certPem ?? this.certPem,
        pairedAt: pairedAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'device_id': deviceId,
        'name': name,
        'os': os,
        'tier': tier,
        'fp': fp.toLowerCase(),
        if (certPem != null) 'cert_pem': base64Encode(certPem!),
        'paired_at': pairedAt,
        'last_seen_at': lastSeenAt,
        'status': status,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
        deviceId: json['device_id'] as String,
        name: json['name'] as String,
        os: json['os'] as String,
        tier: json['tier'] as int,
        fp: (json['fp'] as String).toLowerCase(),
        certPem: json['cert_pem'] == null
            ? null
            : base64Decode(json['cert_pem'] as String),
        pairedAt: json['paired_at'] as int,
        lastSeenAt: json['last_seen_at'] as int,
        status: (json['status'] as String?) ?? 'active',
      );
}

/// Encrypted Trusted Device Store (`trusted_devices.json.enc`, §15.3 & T1.2).
/// Envelope layout: `nonce(12B) || ciphertext || tag(16B)` keyed by `dropclip.store.key`.
class TrustedDeviceStore {
  final Directory storageDir;
  final SecureKeyStore keyStore;
  final Map<String, TrustedDevice> _devicesById = <String, TrustedDevice>{};

  TrustedDeviceStore({required this.storageDir, required this.keyStore});

  List<TrustedDevice> get allDevices =>
      List<TrustedDevice>.unmodifiable(_devicesById.values);

  List<TrustedDevice> get activeDevices => List<TrustedDevice>.unmodifiable(
        _devicesById.values.where((d) => d.status == 'active'),
      );

  TrustedDevice? getByDeviceId(String deviceId) => _devicesById[deviceId];

  TrustedDevice? getByFingerprint(String fp) {
    final norm = fp.toLowerCase();
    for (final dev in _devicesById.values) {
      if (dev.fp == norm) return dev;
    }
    return null;
  }

  /// Returns true iff [fp] belongs to an active (non-quarantined) paired peer.
  bool isActiveFingerprint(String fp) {
    final dev = getByFingerprint(fp);
    return dev != null && dev.status == 'active';
  }

  /// Compatible with `TrustedFingerprintLookup` (`String? Function(String)`).
  String? fingerprintOf(String deviceId) {
    final dev = _devicesById[deviceId];
    if (dev == null || dev.status != 'active') return null;
    return dev.fp;
  }

  /// Loads and decrypts `trusted_devices.json.enc` if present on disk.
  Future<void> load() async {
    await storageDir.create(recursive: true);
    final file = File('${storageDir.path}/$kTrustedDevicesFileName');
    if (!await file.exists()) {
      _devicesById.clear();
      return;
    }
    final key = await _getOrCreateMasterKey();
    final rawBytes = await file.readAsBytes();
    final plaintext = _decryptEnvelope(key, rawBytes);
    final decoded = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    final list = (decoded['devices'] as List<dynamic>? ?? const <dynamic>[]);
    _devicesById.clear();
    for (final item in list) {
      final dev = TrustedDevice.fromJson(item as Map<String, dynamic>);
      _devicesById[dev.deviceId] = dev;
    }
  }

  Future<void> upsert(TrustedDevice device) async {
    _devicesById[device.deviceId] = device;
    await _persist();
  }

  Future<bool> setStatus(String deviceId, String status) async {
    final existing = _devicesById[deviceId];
    if (existing == null) return false;
    _devicesById[deviceId] = existing.copyWith(status: status);
    await _persist();
    return true;
  }

  Future<bool> removeByDeviceId(String deviceId) async {
    final removed = _devicesById.remove(deviceId) != null;
    if (removed) await _persist();
    return removed;
  }

  Future<bool> removeByFingerprint(String fp) async {
    final dev = getByFingerprint(fp);
    if (dev == null) return false;
    return removeByDeviceId(dev.deviceId);
  }

  Future<void> _persist() async {
    await storageDir.create(recursive: true);
    final key = await _getOrCreateMasterKey();
    final payload = <String, dynamic>{
      'version': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'devices': _devicesById.values.map((d) => d.toJson()).toList(),
    };
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final encrypted = _encryptEnvelope(key, plaintext);
    final file = File('${storageDir.path}/$kTrustedDevicesFileName');
    await file.writeAsBytes(encrypted, flush: true);
  }

  Future<Uint8List> _getOrCreateMasterKey() async {
    final existing = await keyStore.read(kStoreMasterKeyStoreKey);
    if (existing != null && existing.length == 32) return existing;
    final rng = Random.secure();
    final generated =
        Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    await keyStore.write(kStoreMasterKeyStoreKey, generated);
    return generated;
  }

  static Uint8List _encryptEnvelope(Uint8List masterKey, Uint8List plaintext) {
    final rng = Random.secure();
    final nonce =
        Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
    final ciphertext = _xorKeystream(masterKey, nonce, plaintext);
    final tag = _computeTag(masterKey, nonce, ciphertext);
    final out = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(ciphertext)
      ..add(tag);
    return out.toBytes();
  }

  static Uint8List _decryptEnvelope(Uint8List masterKey, Uint8List envelope) {
    if (envelope.length < 28) {
      throw const FormatException('Encrypted store envelope truncated (<28B)');
    }
    final nonce = envelope.sublist(0, 12);
    final ciphertext = envelope.sublist(12, envelope.length - 16);
    final tag = envelope.sublist(envelope.length - 16);
    final expectedTag = _computeTag(masterKey, nonce, ciphertext);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= tag[i] ^ expectedTag[i];
    }
    if (diff != 0) {
      throw const FormatException('Encrypted store authentication tag invalid');
    }
    return _xorKeystream(masterKey, nonce, ciphertext);
  }

  static Uint8List _xorKeystream(
    Uint8List masterKey,
    Uint8List nonce,
    Uint8List input,
  ) {
    final encKey = Hmac(sha256, masterKey).convert(utf8.encode('enc')).bytes;
    final out = Uint8List(input.length);
    final hmac = Hmac(sha256, encKey);
    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      final blockIn = Uint8List(16)..setRange(0, 12, nonce);
      ByteData.sublistView(blockIn, 12, 16).setUint32(0, counter++);
      final streamBlock = hmac.convert(blockIn).bytes;
      final chunk = min(32, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        out[offset + i] = input[offset + i] ^ streamBlock[i];
      }
      offset += chunk;
    }
    return out;
  }

  static Uint8List _computeTag(
    Uint8List masterKey,
    Uint8List nonce,
    Uint8List ciphertext,
  ) {
    final macKey = Hmac(sha256, masterKey).convert(utf8.encode('mac')).bytes;
    final data = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(ciphertext);
    final digest = Hmac(sha256, macKey).convert(data.toBytes()).bytes;
    return Uint8List.fromList(digest.sublist(0, 16));
  }
}
