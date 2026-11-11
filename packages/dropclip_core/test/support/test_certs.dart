import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Throwaway ECDSA P-256 self-signed cert for transport tests (in memory).
class TestCert {
  final Uint8List certPem;
  final Uint8List keyPem;
  final String fp;

  const TestCert(this.certPem, this.keyPem, this.fp);
}

/// Generates a P-256 cert with openssl in [dir]; temp files are deleted.
Future<TestCert> generateTestCert(Directory dir, String name) async {
  final key = '${dir.path}/$name.k';
  final crt = '${dir.path}/$name.crt';
  final der = '${dir.path}/$name.der';
  Future<void> run(List<String> args) async {
    final res = await Process.run('openssl', args);
    if (res.exitCode != 0) throw StateError('openssl failed: ${res.stderr}');
  }

  await run([
    'req', '-x509', '-newkey', 'ec', //
    '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes',
    '-keyout', key, '-out', crt, '-days', '1', '-subj', '/CN=dropclip-$name',
  ]);
  await run(['x509', '-in', crt, '-outform', 'DER', '-out', der]);
  final cert = TestCert(
    await File(crt).readAsBytes(),
    await File(key).readAsBytes(),
    sha256.convert(await File(der).readAsBytes()).toString(),
  );
  for (final f in [key, crt, der]) {
    await File(f).delete();
  }
  return cert;
}
