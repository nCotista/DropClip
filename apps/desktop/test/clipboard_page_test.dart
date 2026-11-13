import 'dart:io';

import 'package:dropclip_desktop/src/clipboard_page.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _github = 'https://github.com/nCotista/DropClip/pull/42';

Future<void> _pump(
  WidgetTester tester, {
  ShellStatus status = demoShellStatus,
  ValueChanged<ClipItem>? onCopy,
  VoidCallback? onSendClipboard,
  void Function(String path, {bool reveal})? onOpenFile,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildDropClipTheme(Brightness.dark),
    home: Scaffold(
      body: ClipboardPage(
          status: status,
          onCopy: onCopy,
          onSendClipboard: onSendClipboard,
          onOpenFile: onOpenFile),
    ),
  ));
}

void main() {
  test('Explorer gets backslashes; reveal selects the file', () {
    const p = r'C:\Users\me/Downloads/DropClip/report.pdf';
    const win = r'C:\Users\me\Downloads\DropClip\report.pdf';
    final open = openCommand(p, reveal: false, macOS: false);
    expect(open.$1, 'explorer.exe');
    expect(open.$2, [win]);
    expect(openCommand(p, reveal: true, macOS: false).$2, ['/select,', win]);
    expect(openCommand('/Users/me/x.pdf', reveal: true, macOS: true).$2,
        ['-R', '/Users/me/x.pdf']);
    expect(
        openCommand('/tmp/a/x.pdf', reveal: false, macOS: false,
            windows: false),
        ('xdg-open', ['/tmp/a/x.pdf']));
    expect(
        openCommand('/tmp/a/x.pdf', reveal: true, macOS: false, windows: false),
        ('xdg-open', ['/tmp/a']));
    expect(openCommand('-bad.pdf', reveal: false, macOS: true),
        ('open', ['./-bad.pdf']));
  });

  test('runOpenWithSystem guards missing files, shell flags, and failures',
      () async {
    final tmp = await Directory.systemTemp.createTemp('dc_open_');
    addTearDown(() => tmp.delete(recursive: true));

    var calls = 0;
    final missing = await runOpenWithSystem(
      '${tmp.path}/gone.pdf',
      run: (exe, args, {required bool runInShell}) async {
        calls++;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(missing, isFalse);
    expect(calls, 0);

    final weird = File('${tmp.path}/a & calc | b.txt');
    await weird.writeAsString('hi');
    late String gotExe;
    late List<String> gotArgs;
    late bool gotShell;
    final ok = await runOpenWithSystem(
      weird.path,
      macOS: false,
      windows: false,
      run: (exe, args, {required bool runInShell}) async {
        gotExe = exe;
        gotArgs = args;
        gotShell = runInShell;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(ok, isTrue);
    expect(gotExe, 'xdg-open');
    expect(gotArgs, [weird.path]);
    expect(gotShell, isFalse);

    final boom = await runOpenWithSystem(
      weird.path,
      macOS: true,
      windows: false,
      run: (_, __, {required bool runInShell}) =>
          Future.error(const ProcessException('open', [])),
    );
    expect(boom, isFalse);
  });

  group('ClipboardPage (T1.12, FR-04, SF-03)', () {
    testWidgets('a received file opens from its row', (tester) async {
      final opened = <String>[];
      final copied = <ClipItem>[];
      await _pump(tester,
          status: const ShellStatus(
            networkName: '',
            address: '',
            verifiedDevices: 1,
            activeTransfers: 0,
            deviceCount: 1,
            clips: [
              ClipItem(ClipKind.text, '📎 report.pdf',
                  sourceDevice: 'Laptop',
                  age: '10:00',
                  path: '/downloads/report.pdf'),
              ClipItem(ClipKind.text, 'plain text',
                  sourceDevice: 'Laptop', age: '10:01'),
            ],
          ),
          onCopy: copied.add,
          onOpenFile: (p, {bool reveal = false}) =>
              opened.add(reveal ? 'reveal $p' : p));

      // Only the file row gets the open button; text keeps "copy again".
      expect(find.byKey(const Key('clip-open-file')), findsOneWidget);
      await tester.tap(find.text('📎 report.pdf'));
      await tester.tap(find.byKey(const Key('clip-open-file')));
      await tester.tap(find.byKey(const Key('clip-show-in-folder')));
      expect(opened, [
        '/downloads/report.pdf',
        '/downloads/report.pdf',
        'reveal /downloads/report.pdf'
      ]);
      expect(copied, isEmpty);
    });

    testWidgets('lists recent clips with source and age', (tester) async {
      await _pump(tester);

      expect(find.text('Live sync across 3 devices · text, links, PNG/JPEG'),
          findsOneWidget);
      expect(find.byType(Card), findsNWidgets(4));
      expect(find.text(_github), findsOneWidget);
      expect(find.text('From Pixel 8 · 2 min ago'), findsOneWidget);
    });

    testWidgets('filter chips narrow the list by kind', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Links'));
      await tester.pump();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text(_github), findsOneWidget);

      await tester.tap(find.text('Text'));
      await tester.pump();
      expect(find.byType(Card), findsNWidgets(2));

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.byType(Card), findsNWidgets(4));
    });

    testWidgets('search is case-insensitive and shows an empty state',
        (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'rtm TABLE');
      await tester.pump();
      expect(find.byType(Card), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pump();
      expect(find.byType(Card), findsNothing);
      expect(find.text('No clips match'), findsOneWidget);
    });

    testWidgets('copy again uses the callback when given', (tester) async {
      final copied = <ClipItem>[];
      await _pump(tester, onCopy: copied.add);

      await tester.tap(find.byTooltip('Copy again').at(1));
      await tester.pump();
      expect(copied.single.preview, _github);
      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('copy again writes text to the system clipboard by default',
        (tester) async {
      final writes = <Object?>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') writes.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester);

      await tester.tap(find.byTooltip('Copy again').at(1));
      await tester.tap(find.byTooltip('Copy again').at(2)); // image: skipped
      await tester.pump();
      expect(writes, [
        {'text': _github}
      ]);
    });

    testWidgets('auto-sync toggles and send calls back', (tester) async {
      var sent = 0;
      await _pump(tester, onSendClipboard: () => sent++);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Send clipboard'));
      expect(sent, 1);
    });

    testWidgets('suppressed password-manager clips are only counted',
        (tester) async {
      await _pump(tester);
      expect(find.textContaining('1 item from a password manager not synced'),
          findsOneWidget);

      await _pump(tester,
          status: const ShellStatus(
              networkName: 'n',
              address: 'a',
              verifiedDevices: 1,
              activeTransfers: 0,
              deviceCount: 1));
      expect(find.textContaining('password manager'), findsNothing);
      expect(find.text('No clips match'), findsOneWidget);
    });
  });
}
