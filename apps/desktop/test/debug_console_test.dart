import 'dart:async';

import 'package:dropclip_desktop/src/debug/debug_console.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Feed implements LogFeed {
  @override
  final List<String> recent;
  // ignore: close_sinks, closed in tearDown
  final controller = StreamController<String>.broadcast(sync: true);

  _Feed(this.recent);

  @override
  Stream<String> get lines => controller.stream;
}

String _line(String msg, {String level = 'INFO'}) =>
    '{"ts":"2026-11-03T12:00:03.000Z","level":"$level",'
    '"component":"discovery","device_id":"d1","msg":"$msg"}';

void main() {
  test('formatLogLine shows time, level, component, message and data', () {
    expect(formatLogLine(_line('peer found')),
        '12:00:03 INFO  discovery  peer found');
    expect(
        formatLogLine('{"ts":"2026-11-03T01:02:03Z","level":"WARN",'
            '"component":"x","msg":"m","data":{"size":3}}'),
        '01:02:03 WARN  x  m {size: 3}');
    expect(formatLogLine('not json'), 'not json');
    expect(formatLogLine('[1, 2]'), '[1, 2]');
  });

  group('DebugConsoleHost (T0.3)', () {
    late _Feed feed;

    Future<void> pump(WidgetTester tester, {int maxLines = 500}) async {
      // Mounted in MaterialApp.builder, above the Navigator and its Overlay,
      // exactly as main.dart does; nothing focused, like the real app.
      await tester.pumpWidget(MaterialApp(
        theme: buildDropClipTheme(Brightness.dark),
        builder: (_, child) =>
            DebugConsoleHost(feed: feed, maxLines: maxLines, child: child!),
        home: const Text('app'),
      ));
    }

    Future<void> toggle(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    setUp(() => feed = _Feed([_line('started')]));
    tearDown(() => feed.controller.close());

    testWidgets('Ctrl+Shift+D shows kept lines and follows new ones',
        (tester) async {
      await pump(tester);
      expect(find.textContaining('started'), findsNothing);
      await toggle(tester);
      expect(find.text('12:00:03 INFO  discovery  started'), findsOneWidget);
      feed.controller.add(_line('peer lost', level: 'WARN'));
      await tester.pump();
      expect(find.text('12:00:03 WARN  discovery  peer lost'), findsOneWidget);
      expect(find.text('Debug console · 2 lines'), findsOneWidget);
    });

    testWidgets('closing stops following; reopening starts fresh',
        (tester) async {
      await pump(tester);
      await toggle(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(feed.controller.hasListener, isFalse);
      expect(find.textContaining('started'), findsNothing);
      await toggle(tester);
      expect(find.text('Debug console · 1 lines'), findsOneWidget);
    });

    testWidgets('keeps at most maxLines', (tester) async {
      await pump(tester, maxLines: 2);
      await toggle(tester);
      feed.controller
        ..add(_line('a'))
        ..add(_line('b'));
      await tester.pump();
      expect(find.text('Debug console · 2 lines'), findsOneWidget);
      expect(find.textContaining('started'), findsNothing);
    });

    testWidgets('no lines yet shows a note', (tester) async {
      feed = _Feed([]);
      await pump(tester);
      await toggle(tester);
      expect(find.text('No log lines yet'), findsOneWidget);
    });
  });
}
