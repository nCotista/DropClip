import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dropclip/clipboard');
  tearDownAll(() => channel.invokeMethod<void>('clear'));

  Future<void> write(String text) => channel.invokeMethod<void>('write', {
        'items': [
          {'mime': 'text/plain', 'data': Uint8List.fromList(utf8.encode(text))},
        ],
      });

  Future<String?> read() async {
    final snapshot = await channel.invokeMapMethod<String, dynamic>('read');
    if (snapshot == null) return null;
    final items = snapshot['items'] as List;
    return utf8.decode((items.single as Map)['data'] as Uint8List);
  }

  testWidgets('registered native plugin writes and reads test text', (_) async {
    await write('hello world');
    expect(await read(), 'hello world');
  }, skip: !Platform.isMacOS);

  testWidgets('native channel preserves Thai and emoji', (_) async {
    await write('ทดสอบ 📋');
    expect(await read(), 'ทดสอบ 📋');
  }, skip: !Platform.isMacOS);

  testWidgets('clear returns an empty clipboard snapshot', (_) async {
    await write('test-only content');
    await channel.invokeMethod<void>('clear');
    expect(await read(), isNull);
  }, skip: !Platform.isMacOS);

  testWidgets('malformed writes are rejected without replacing content', (
    _,
  ) async {
    await write('retained test fixture');
    for (final bad in [
      null,
      <String, dynamic>{},
      {'items': 'bad'},
    ]) {
      await expectLater(
        channel.invokeMethod<void>('write', bad),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'BAD_ARGS'),
        ),
      );
      expect(await read(), 'retained test fixture');
    }
  }, skip: !Platform.isMacOS);
}
