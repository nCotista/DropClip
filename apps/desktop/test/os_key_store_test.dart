@TestOn('windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_desktop/src/node/os_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DPAPI round trip; the file never holds the plaintext (NFR-S02)',
      () async {
    final dir = await Directory.systemTemp.createTemp('dc_dpapi_');
    addTearDown(() => dir.delete(recursive: true));
    final store = DpapiKeyStore(dir);
    final secret = Uint8List.fromList(List<int>.generate(64, (i) => i * 3));

    expect(await store.read('dropclip.identity.p256'), isNull);
    await store.write('dropclip.identity.p256', secret);
    expect(await store.read('dropclip.identity.p256'), secret);

    final onDisk = await dir.list().single as File;
    final bytes = await onDisk.readAsBytes();
    expect(bytes.length, greaterThan(secret.length));
    for (var i = 0; i + 8 <= bytes.length; i++) {
      expect(bytes.sublist(i, i + 8), isNot(secret.sublist(0, 8)));
    }

    await store.delete('dropclip.identity.p256');
    expect(await store.read('dropclip.identity.p256'), isNull);
  });
}
