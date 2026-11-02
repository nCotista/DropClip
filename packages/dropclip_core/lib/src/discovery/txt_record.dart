import 'dart:convert';

import 'package:dropclip_protocol/dropclip_protocol.dart';

/// Operating systems that may advertise a DropClip node (PROTO-DC-V2.0 §3.2).
enum DeviceOs {
  macos(1),
  windows(1),
  android(2),
  ios(3);

  const DeviceOs(this.tier);

  /// Capability tier that MUST accompany this OS (PROTO-DC-V2.0 §2.2).
  final int tier;

  static DeviceOs? tryParse(String? value) {
    for (final os in values) {
      if (os.name == value) return os;
    }
    return null;
  }
}

/// mDNS/DNS-SD TXT record of a DropClip node (T1.1, FR-01, PROTO-DC-V2.0 §3.2).
///
/// Every field is public: the TXT record MUST NOT carry any secret.
class DiscoveryRecord {
  static const String serviceType = '_dropclip._tcp';
  static const int maxNameBytes = 64;

  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final RegExp _fingerprint = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _decimal = RegExp(r'^[0-9]{1,5}$');

  final int version;
  final int minVersion;
  final String deviceId;
  final String name;
  final DeviceOs os;
  final int port;
  final String fingerprint;
  final List<String> capabilities;

  /// Creates a record; [name] is truncated to [maxNameBytes] UTF-8 bytes on a
  /// code point boundary, and [deviceId]/[fingerprint] are lower-cased.
  DiscoveryRecord({
    this.version = ProtocolConstants.protocolVersion,
    this.minVersion = ProtocolConstants.minSupportedProtocolVersion,
    required String deviceId,
    required String name,
    required this.os,
    required this.port,
    required String fingerprint,
    this.capabilities = const [],
  })  : deviceId = deviceId.toLowerCase(),
        fingerprint = fingerprint.toLowerCase(),
        name = truncateName(name);

  int get tier => os.tier;

  /// Encodes the record as DNS-SD TXT key/value pairs.
  Map<String, String> toTxt() => {
        'v': '$version',
        'min_v': '$minVersion',
        'id': deviceId,
        'name': base64.encode(utf8.encode(name)),
        'os': os.name,
        'tier': '$tier',
        'port': '$port',
        'fp': fingerprint,
        if (capabilities.isNotEmpty) 'cap': capabilities.join(','),
      };

  /// Parses TXT key/value pairs, returning `null` for any malformed record so
  /// the caller can drop it silently (PROTO-DC-V2.0 §3.3).
  static DiscoveryRecord? tryParse(Map<String, String?> txt) {
    final version = _parseInt(txt['v']);
    final minVersion = _parseInt(txt['min_v']);
    final id = txt['id']?.toLowerCase();
    final os = DeviceOs.tryParse(txt['os']);
    final tier = _parseInt(txt['tier']);
    final port = _parseInt(txt['port']);
    final fp = txt['fp']?.toLowerCase();
    final name = _decodeName(txt['name']);

    if (version == null || version < 1) return null;
    if (minVersion == null || minVersion < 1 || minVersion > version) {
      return null;
    }
    if (id == null || !_uuidV4.hasMatch(id)) return null;
    if (os == null || tier != os.tier) return null;
    if (port == null ||
        port < ProtocolConstants.portRangeStart ||
        port > ProtocolConstants.portRangeEnd) {
      return null;
    }
    if (fp == null || !_fingerprint.hasMatch(fp)) return null;
    if (name == null) return null;

    final cap = txt['cap'];
    return DiscoveryRecord(
      version: version,
      minVersion: minVersion,
      deviceId: id,
      name: name,
      os: os,
      port: port,
      fingerprint: fp,
      capabilities: cap == null
          ? const []
          : cap.split(',').where((c) => c.isNotEmpty).toList(),
    );
  }

  /// Truncates [name] to at most [maxNameBytes] UTF-8 bytes without splitting
  /// a Unicode code point.
  static String truncateName(String name) {
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in name.runes) {
      final char = String.fromCharCode(rune);
      final size = utf8.encode(char).length;
      if (bytes + size > maxNameBytes) break;
      bytes += size;
      buffer.write(char);
    }
    return buffer.toString();
  }

  static int? _parseInt(String? value) {
    if (value == null || !_decimal.hasMatch(value)) return null;
    return int.parse(value);
  }

  static String? _decodeName(String? value) {
    if (value == null) return null;
    try {
      final bytes = base64.decode(value);
      if (bytes.isEmpty || bytes.length > maxNameBytes) return null;
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}
