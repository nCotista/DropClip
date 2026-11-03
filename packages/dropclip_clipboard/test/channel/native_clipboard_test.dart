import 'dart:async';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

/// Records calls and answers like the native side would.
class FakeChannel implements ClipboardChannel {
  final calls = <String>[];
  final args = <String, Map<String, Object?>?>{};
  final results = <String, Object?>{};
  final errors = <String, ClipboardChannelException>{};
  final eventsCtrl = StreamController<Object?>.broadcast();

  @override
  Stream<Object?> get events => eventsCtrl.stream;

  Future<void> close() => eventsCtrl.close();

  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? a]) async {
    calls.add(method);
    args[method] = a;
    final err = errors[method];
    if (err != null) throw err;
    return results[method];
  }
}

Map<String, Object?> event(int token,
        {bool concealed = false, List<Object?> items = const []}) =>
    {'change_token': token, 'is_concealed': concealed, 'items': items, 'ts': 1};

const lock = ClipboardChannelException(NativeClipboard.lockedCode);

void main() {
  late FakeChannel ch;
  late List<String> logs;
  late NativeClipboard clip;

  setUp(() {
    ch = FakeChannel();
    logs = [];
    clip = NativeClipboard(ch, log: logs.add);
  });

  tearDown(() async {
    await clip.dispose();
    await ch.close();
  });

  test('start listens and forwards native changes (happy path)', () async {
    await clip.start();
    expect(ch.calls, ['start']);
    final got = clip.changes.first;
    ch.eventsCtrl.add(event(42, items: [
      {
        'mime': ClipMime.text,
        'data': Uint8List.fromList([104, 105])
      }
    ]));
    final s = await got;
    expect(s.changeToken, 42);
    expect(s.preferred!.data, [104, 105]);
    expect(clip.changeToken(), 42);
  });

  test('start twice calls native once; stop then start works', () async {
    await clip.start();
    await clip.start();
    expect(ch.calls, ['start']);
    await clip.stop();
    await clip.stop();
    expect(ch.calls, ['start', 'stop']);
    await clip.start();
    expect(ch.calls, ['start', 'stop', 'start']);
  });

  test('failed start does not keep listening', () async {
    ch.errors['start'] = const ClipboardChannelException('NO_WINDOW');
    await expectLater(clip.start(), throwsA(isA<ClipboardChannelException>()));
    ch.errors.clear();
    await clip.start();
    expect(ch.calls, ['start', 'start']);
  });

  test('concealed event is forwarded without items and logged', () async {
    await clip.start();
    final got = clip.changes.first;
    ch.eventsCtrl.add(event(5, concealed: true, items: [
      {
        'mime': ClipMime.text,
        'data': Uint8List.fromList([1])
      }
    ]));
    final s = await got;
    expect(s.isConcealed, isTrue);
    expect(s.items, isEmpty);
    expect(logs, ['clipboard.blocked_concealed']);
  });

  test('malformed event is dropped and logged, stream keeps going', () async {
    await clip.start();
    final got = clip.changes.first;
    ch.eventsCtrl.add({'garbage': true});
    ch.eventsCtrl.add(event(9));
    expect((await got).changeToken, 9);
    expect(logs, ['clipboard.malformed_event']);
  });

  test('event stream error is logged, not thrown', () async {
    await clip.start();
    ch.eventsCtrl.addError(StateError('boom'));
    await Future<void>.delayed(Duration.zero);
    expect(logs, ['clipboard.event_error']);
  });

  group('read', () {
    test('returns items and updates the token', () async {
      ch.results['read'] = event(3, items: [
        {
          'mime': ClipMime.png,
          'data': Uint8List.fromList([0x89])
        }
      ]);
      final items = await clip.read();
      expect(items!.single.mime, ClipMime.png);
      expect(clip.changeToken(), 3);
    });

    test('null, empty and concealed all give null', () async {
      expect(await clip.read(), isNull);
      ch.results['read'] = event(1);
      expect(await clip.read(), isNull);
      ch.results['read'] = event(2, concealed: true);
      expect(await clip.read(), isNull);
    });

    test('CLIPBOARD_LOCKED becomes ClipboardLockedException', () async {
      ch.errors['read'] = lock;
      await expectLater(
          clip.read(),
          throwsA(isA<ClipboardLockedException>()
              .having((e) => e.method, 'method', 'read')));
      expect(logs, ['clipboard.locked']);
    });

    test('other native errors pass through unchanged', () async {
      ch.errors['read'] = const ClipboardChannelException('UNKNOWN');
      await expectLater(clip.read(), throwsA(isA<ClipboardChannelException>()));
    });
  });

  group('write', () {
    test('sends all items in one call and returns the token', () async {
      ch.results['write'] = {'change_token': 77};
      final token = await clip.write(const [
        ClipboardItem(mime: ClipMime.png, data: [1, 2]),
        ClipboardItem(mime: ClipMime.winDibV5, data: [3]),
      ]);
      expect(token, 77);
      expect(clip.changeToken(), 77);
      expect(ch.calls, ['write']);
      final sent = ch.args['write']!['items']! as List<Object?>;
      expect(sent, hasLength(2));
      final first = sent.first! as Map<String, Object?>;
      expect(first['mime'], ClipMime.png);
      expect(first['data'], isA<Uint8List>());
    });

    test('rejects empty list and unknown MIME without calling native',
        () async {
      await expectLater(clip.write(const []), throwsArgumentError);
      await expectLater(
          clip.write(const [
            ClipboardItem(mime: 'x/y', data: [1])
          ]),
          throwsArgumentError);
      expect(ch.calls, isEmpty);
    });

    test('bad native result is a FormatException', () async {
      ch.results['write'] = {'change_token': 'x'};
      await expectLater(
          clip.write(const [
            ClipboardItem(mime: ClipMime.text, data: [1])
          ]),
          throwsFormatException);
    });

    test('locked write becomes ClipboardLockedException', () async {
      ch.errors['write'] = lock;
      await expectLater(
          clip.write(const [
            ClipboardItem(mime: ClipMime.text, data: [1])
          ]),
          throwsA(isA<ClipboardLockedException>()));
    });
  });

  test('clear calls native', () async {
    await clip.clear();
    expect(ch.calls, ['clear']);
  });

  test('fetchChangeToken reads the live token', () async {
    ch.results['changeToken'] = 1234;
    expect(await clip.fetchChangeToken(), 1234);
    expect(clip.changeToken(), 1234);
    ch.results['changeToken'] = null;
    await expectLater(clip.fetchChangeToken(), throwsFormatException);
  });

  test('exceptions print their code, not content', () {
    expect(lock.toString(), 'ClipboardChannelException(CLIPBOARD_LOCKED)');
    expect(const ClipboardLockedException('read').toString(),
        'ClipboardLockedException(read)');
  });
}
