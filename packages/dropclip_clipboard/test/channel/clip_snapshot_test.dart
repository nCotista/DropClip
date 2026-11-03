import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

Map<String, Object?> snap({
  Object? token = 7,
  Object? concealed = false,
  Object? items = const <Object?>[],
  Object? ts = 1757280000000,
}) =>
    {
      'change_token': token,
      'is_concealed': concealed,
      'items': items,
      'ts': ts
    };

Map<String, Object?> item(String mime, List<int> data) =>
    {'mime': mime, 'data': Uint8List.fromList(data)};

void main() {
  group('ClipSnapshot.fromMap', () {
    test('decodes a text change (happy path)', () {
      final s = ClipSnapshot.fromMap(snap(items: [
        item(ClipMime.text, [0xE0, 0xB8, 0x81]), // "ก" in UTF-8
      ]));
      expect(s.changeToken, 7);
      expect(s.isConcealed, isFalse);
      expect(s.ts, 1757280000000);
      expect(s.items, hasLength(1));
      expect(s.preferred!.mime, ClipMime.text);
      expect(s.preferred!.data, [0xE0, 0xB8, 0x81]);
    });

    test('concealed drops items even if native sent content', () {
      final s = ClipSnapshot.fromMap(snap(concealed: true, items: [
        item(ClipMime.text, [1, 2, 3])
      ]));
      expect(s.isConcealed, isTrue);
      expect(s.items, isEmpty);
      expect(s.preferred, isNull);
    });

    test('concealed ignores malformed items instead of reading them', () {
      final s = ClipSnapshot.fromMap(snap(concealed: true, items: 'garbage'));
      expect(s.isConcealed, isTrue);
      expect(s.items, isEmpty);
    });

    test('constructor also drops items when concealed', () {
      final s = ClipSnapshot(
          changeToken: 1,
          isConcealed: true,
          items: const [
            ClipboardItem(mime: ClipMime.text, data: [1])
          ],
          ts: 0);
      expect(s.items, isEmpty);
    });

    test('prefers PNG over DIB formats and DIBV5 over DIB', () {
      final s = ClipSnapshot.fromMap(snap(items: [
        item(ClipMime.winDib, [1]),
        item(ClipMime.winDibV5, [2]),
        item(ClipMime.png, [3]),
        item(ClipMime.text, [4]),
      ]));
      expect(s.preferred!.mime, ClipMime.png);

      final noPng = ClipSnapshot.fromMap(snap(items: [
        item(ClipMime.winDib, [1]),
        item(ClipMime.winDibV5, [2]),
      ]));
      expect(noPng.preferred!.mime, ClipMime.winDibV5);
    });

    test('prefers uri-list over plain text', () {
      final s = ClipSnapshot.fromMap(snap(items: [
        item(ClipMime.text, [1]),
        item(ClipMime.uriList, [2]),
      ]));
      expect(s.preferred!.mime, ClipMime.uriList);
    });

    test('skips unknown MIME types and keeps the rest', () {
      final s = ClipSnapshot.fromMap(snap(items: [
        item('application/x-secret-format', [9]),
        item(ClipMime.text, [1]),
      ]));
      expect(s.items.map((i) => i.mime), [ClipMime.text]);
    });

    test('only unknown items gives no preferred item', () {
      final s = ClipSnapshot.fromMap(snap(items: [
        item('x/y', [1])
      ]));
      expect(s.items, isEmpty);
      expect(s.preferred, isNull);
    });

    test('items are read-only', () {
      final s = ClipSnapshot.fromMap(snap(items: [
        item(ClipMime.text, [1])
      ]));
      expect(() => s.items.add(const ClipboardItem(mime: 'a', data: [])),
          throwsUnsupportedError);
    });

    final malformed = <String, Object?>{
      'not a map': 'hello',
      'null': null,
      'missing change_token': snap(token: null),
      'negative change_token': snap(token: -1),
      'string change_token': snap(token: '7'),
      'bad is_concealed': snap(concealed: 'false'),
      'bad ts': snap(ts: 1.5),
      'items not a list': snap(items: {'mime': 'text/plain'}),
      'item not a map': snap(items: ['text/plain']),
      'item mime missing': snap(items: [
        {'data': Uint8List(1)}
      ]),
      'item data not bytes': snap(items: [
        {'mime': ClipMime.text, 'data': 'hello'}
      ]),
    };
    malformed.forEach((name, raw) {
      test('throws FormatException: $name', () {
        expect(() => ClipSnapshot.fromMap(raw), throwsFormatException);
      });
    });

    test('FormatException message never contains clipboard content', () {
      try {
        ClipSnapshot.fromMap(snap(items: [
          {'mime': ClipMime.text, 'data': 'my-password-123'}
        ]));
        fail('expected FormatException');
      } on FormatException catch (e) {
        expect(e.toString(), isNot(contains('my-password-123')));
      }
    });
  });
}
