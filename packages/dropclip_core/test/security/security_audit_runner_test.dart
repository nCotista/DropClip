import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dropclip_t4_2_audit_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('T4.2 Comprehensive Security Audit & Penetration Testing', () {
    test(
      'blocks 100% of Path Traversal, Zip-Slip, Null Byte, Bidi & Collision vectors',
      () {
        final result = SecurityAuditRunner.runPathTraversalAudit();
        expect(result.total, equals(15));
        expect(result.blocked, equals(result.total));
      },
    );

    test(
      'blocks Active MITM Commit-then-Reveal substitution and Zero-PIN-on-Wire violations',
      () async {
        final result = await SecurityAuditRunner.runMitmAndZeroPinAudit(
          tempDir,
        );
        expect(result.mitmBlocked, isTrue);
        expect(result.zeroPinEnforced, isTrue);
      },
    );

    test(
      'verifies zero private key, PIN, or raw clipboard leaks in logs and disk storage',
      () async {
        final clean = await SecurityAuditRunner.runLogAndStorageLeakAudit(
          tempDir,
        );
        expect(clean, isTrue);
      },
    );

    test(
      'survives 100,000 malformed HTTP/WebSocket endpoint fuzz requests with 0 crashes',
      () async {
        final report = await SecurityAuditRunner.runFullAudit(
          storageDir: tempDir,
          fuzzIterations: 100000,
        );
        expect(report.passed, isTrue);
        expect(report.fuzzRequestsExecuted, equals(100000));
        expect(report.unhandledExceptions, equals(0));
      },
    );
  });
}
