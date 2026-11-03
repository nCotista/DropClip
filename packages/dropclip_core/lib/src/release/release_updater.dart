import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../dropclip_core.dart';

/// Semantic Version `MAJOR.MINOR.PATCH` (`docs/05-RELEASE-AND-UPDATE-PLAN.md` §1).
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;

  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String raw) {
    final clean = raw.trim().replaceFirst(RegExp(r'^v'), '');
    final parts = clean.split('.');
    if (parts.length != 3) {
      throw FormatException('Invalid SemVer: $raw');
    }
    return SemanticVersion(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// Sparkle / WinSparkle AppCast release entry (`docs/05-RELEASE-AND-UPDATE-PLAN.md` §3.1, §3.2, §4.2).
class AppCastReleaseItem {
  final SemanticVersion version;
  final String platform;
  final String downloadUrl;
  final String sha256Hex;
  final String signatureBase64;
  final bool criticalUpdate;

  const AppCastReleaseItem({
    required this.version,
    required this.platform,
    required this.downloadUrl,
    required this.sha256Hex,
    required this.signatureBase64,
    this.criticalUpdate = false,
  });

  String get signingPayload =>
      'dropclip-release-v1:$platform:$version:${sha256Hex.toLowerCase()}:$criticalUpdate';
}

/// Enforces the Roll-Forward Auto-Update & Code Signing Verification Policy (`T4.5`, Release Plan §3–§4).
class RollForwardAutoUpdater {
  static const List<int> iosPhasedReleasePercentages = <int>[
    1,
    2,
    5,
    10,
    20,
    50,
    100,
  ];
  static const List<String> requiredMacEntitlements = <String>[
    'com.apple.security.network.server',
    'com.apple.security.network.client',
    'com.apple.security.application-groups',
  ];

  final SemanticVersion currentVersion;
  final Uint8List releaseAuthorityCertPem;

  const RollForwardAutoUpdater({
    required this.currentVersion,
    required this.releaseAuthorityCertPem,
  });

  /// Returns true iff [candidate] is strictly newer than [currentVersion] (Roll-Forward rule §4).
  bool isEligibleRollForward(SemanticVersion candidate) =>
      candidate.compareTo(currentVersion) > 0;

  /// Verifies Roll-Forward eligibility, SHA-256 digest, and cryptographic signature of [artifactBytes].
  Future<bool> verifyReleaseArtifact({
    required AppCastReleaseItem item,
    required Uint8List artifactBytes,
  }) async {
    if (!isEligibleRollForward(item.version)) {
      return false;
    }
    final actualSha = sha256.convert(artifactBytes).toString().toLowerCase();
    if (actualSha != item.sha256Hex.toLowerCase()) {
      return false;
    }
    return DeviceIdentityManager.verifyUtf8(
      certPem: releaseAuthorityCertPem,
      canonicalInput: item.signingPayload,
      signatureBase64: item.signatureBase64,
    );
  }

  /// Validates macOS Developer ID + Notarization + Stapled Ticket readiness (`T4.5` AC #1).
  static bool validateMacReleaseMetadata({
    required List<String> entitlements,
    required bool hardenedRuntime,
    required bool notarizedAndStapled,
  }) {
    if (!hardenedRuntime || !notarizedAndStapled) return false;
    return requiredMacEntitlements.every(entitlements.contains);
  }
}

/// Zero-Loss Storage Schema Migrator (`docs/05-RELEASE-AND-UPDATE-PLAN.md` §4.3).
/// Guarantees that Roll-Forward upgrades never delete Trusted Device Store or Keystore keys.
class StorageSchemaMigrator {
  static const int currentSchemaVersion = 1;

  static Map<String, dynamic> migrateDocument(Map<String, dynamic> doc) {
    final out = Map<String, dynamic>.from(doc);
    final version =
        (out['schema_version'] as int?) ?? (out['version'] as int?) ?? 1;
    if (version < 1) {
      throw StateError('Unsupported storage schema_version: $version');
    }
    out['schema_version'] = currentSchemaVersion;
    out['version'] ??= currentSchemaVersion;
    return out;
  }
}

/// Zero-Cloud Diagnostic Bundle & CycloneDX 1.5 SBOM Generator (`Release Plan` §5.4 & §6).
class DiagnosticBundleExporter {
  /// Masks the host octet of an IPv4 address (`192.168.1.42` -> `192.168.1.x/24`).
  static String maskIpv4Subnet(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return 'x.x.x.x/24';
    return '${parts[0]}.${parts[1]}.${parts[2]}.x/24';
  }

  /// Exports a scrubbed diagnostic JSON bundle stripping 100% of keys, certs, and clipboard data.
  static Map<String, dynamic> buildDiagnosticBundle({
    required String appVersion,
    required String osVersion,
    required String localIp,
    required List<String> rawLogLines,
  }) {
    final scrubbedLogs =
        rawLogLines.map((line) => LoggingScrubber.scrubText(line)).toList();
    return <String, dynamic>{
      'schema_version': 1,
      'app_version': appVersion,
      'os_version': osVersion,
      'masked_subnet': maskIpv4Subnet(localIp),
      'logs': scrubbedLogs,
    };
  }

  /// Generates a CycloneDX 1.5 Software Bill of Materials (`sbom-dropclip.json`, §6).
  static Map<String, dynamic> generateCycloneDxSbom({
    required String appVersion,
    required Map<String, String> packageVersions,
  }) {
    return <String, dynamic>{
      'bomFormat': 'CycloneDX',
      'specVersion': '1.5',
      'version': 1,
      'metadata': <String, dynamic>{
        'component': <String, dynamic>{
          'name': 'DropClip',
          'version': appVersion,
          'type': 'application',
        },
      },
      'components': packageVersions.entries
          .map(
            (e) => <String, dynamic>{
              'type': 'library',
              'name': e.key,
              'version': e.value,
              'purl': 'pkg:pub/${e.key}@${e.value}',
            },
          )
          .toList(),
    };
  }

  static String encodePrettyJson(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);
}
