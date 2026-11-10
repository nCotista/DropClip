import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late InMemorySecureKeyStore keyStore;
  late DeviceIdentityManager identityManager;
  late DeviceIdentity releaseSigner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dropclip_t4_5_release_');
    keyStore = InMemorySecureKeyStore();
    identityManager = DeviceIdentityManager(
      storageDir: tempDir,
      keyStore: keyStore,
    );
    releaseSigner = await identityManager.loadOrCreate(
      deviceName: 'DropClip Release Authority',
      os: 'macos',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('T4.5 Binary Packaging, Code Signing & Roll-Forward Auto-Updater', () {
    test(
      'verifies signed Roll-Forward release artifact and blocks downgrades or tampering',
      () async {
        final updater = RollForwardAutoUpdater(
          currentVersion: SemanticVersion.parse('1.0.1'),
          releaseAuthorityCertPem: releaseSigner.certPem,
        );
        final binaryBytes = Uint8List.fromList(
          utf8.encode('DropClip-1.0.2-Universal.dmg-binary'),
        );
        final shaHex = sha256.convert(binaryBytes).toString();
        final candidateVersion = SemanticVersion.parse('1.0.2');

        final unsignedItem = AppCastReleaseItem(
          version: candidateVersion,
          platform: 'macos',
          downloadUrl: 'https://github.com/nCotista/DropClip/releases/v1.0.2',
          sha256Hex: shaHex,
          signatureBase64: '',
          criticalUpdate: true,
        );
        final sig = await identityManager.signUtf8(unsignedItem.signingPayload);
        final signedItem = AppCastReleaseItem(
          version: candidateVersion,
          platform: 'macos',
          downloadUrl: unsignedItem.downloadUrl,
          sha256Hex: shaHex,
          signatureBase64: sig,
          criticalUpdate: true,
        );

        expect(
          await updater.verifyReleaseArtifact(
            item: signedItem,
            artifactBytes: binaryBytes,
          ),
          isTrue,
        );

        // Downgrade (v1.0.0 < v1.0.1) MUST be rejected by Roll-Forward rule (§4).
        final downgradeItem = AppCastReleaseItem(
          version: SemanticVersion.parse('1.0.0'),
          platform: 'macos',
          downloadUrl: unsignedItem.downloadUrl,
          sha256Hex: shaHex,
          signatureBase64: sig,
        );
        expect(
          await updater.verifyReleaseArtifact(
            item: downgradeItem,
            artifactBytes: binaryBytes,
          ),
          isFalse,
        );

        // Tampered binary bytes MUST be rejected.
        final tamperedBytes = Uint8List.fromList(
          utf8.encode('Tampered-Installer'),
        );
        expect(
          await updater.verifyReleaseArtifact(
            item: signedItem,
            artifactBytes: tamperedBytes,
          ),
          isFalse,
        );
      },
    );

    test(
      'validates macOS entitlements, notarization, phased release & Zero-Loss schema migration',
      () {
        expect(
          RollForwardAutoUpdater.validateMacReleaseMetadata(
            entitlements: RollForwardAutoUpdater.requiredMacEntitlements,
            hardenedRuntime: true,
            notarizedAndStapled: true,
          ),
          isTrue,
        );
        expect(
          RollForwardAutoUpdater.validateMacReleaseMetadata(
            entitlements: <String>['com.apple.security.network.client'],
            hardenedRuntime: true,
            notarizedAndStapled: true,
          ),
          isFalse,
        );
        expect(
          RollForwardAutoUpdater.iosPhasedReleasePercentages,
          equals(<int>[1, 2, 5, 10, 20, 50, 100]),
        );

        final migrated =
            StorageSchemaMigrator.migrateDocument(<String, dynamic>{
          'version': 1,
          'devices': <Map<String, dynamic>>[
            <String, dynamic>{'device_id': 'peer-1', 'status': 'active'},
          ],
        });
        expect(migrated['schema_version'], equals(1));
        expect((migrated['devices'] as List<dynamic>), hasLength(1));
      },
    );

    test(
      'exports Zero-Cloud Diagnostic Bundle with masked subnet, scrubbed logs and CycloneDX 1.5 SBOM',
      () {
        const pemHead = '-----BEGIN EC '
            'PRIVATE KEY-----';
        const pemTail = '-----END EC '
            'PRIVATE KEY-----';
        final bundle = DiagnosticBundleExporter.buildDiagnosticBundle(
          appVersion: '1.0.2',
          osVersion: 'macOS 15.1',
          localIp: '192.168.1.42',
          rawLogLines: <String>[
            'Connected peer on 192.168.1.42',
            'Key leak attempt: $pemHead\nSECRET\n$pemTail',
          ],
        );

        expect(bundle['masked_subnet'], equals('192.168.1.x/24'));
        final logs = (bundle['logs'] as List<String>).join('\n');
        expect(logs.contains(pemHead), isFalse);
        expect(logs.contains('[REDACTED_PRIVATE_KEY]'), isTrue);

        final sbom = DiagnosticBundleExporter.generateCycloneDxSbom(
          appVersion: '1.0.2',
          packageVersions: <String, String>{
            'dropclip_protocol': '0.1.0',
            'dropclip_core': '0.1.0',
          },
        );
        expect(sbom['bomFormat'], equals('CycloneDX'));
        expect(sbom['specVersion'], equals('1.5'));
        expect((sbom['components'] as List<dynamic>), hasLength(2));
      },
    );
  });
}
