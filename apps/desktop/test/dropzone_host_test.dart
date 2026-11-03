import 'dart:io';

import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_controller.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_host.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_panel.dart';
import 'package:dropclip_desktop/src/shell.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropzoneController (T1.12, UI-02)', () {
    late Directory dir;
    late DropzoneController dz;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dropzone');
      dz = DropzoneController();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String file(String rel, int bytes) {
      final f = File('${dir.path}/$rel')..createSync(recursive: true);
      f.writeAsBytesSync(List.filled(bytes, 1));
      return f.path;
    }

    test('measures dropped files and whole folders', () async {
      final mov = file('demo.mov', 1500);
      file('assets/a.png', 300);
      file('assets/deep/b.png', 200);
      await dz.addDropped([
        (name: 'demo.mov', path: mov, isFolder: false),
        (name: 'assets', path: '${dir.path}/assets', isFolder: true),
      ]);
      expect(dz.open, isTrue);
      expect([
        for (final i in dz.items) (i.name, i.bytes, i.isFolder)
      ], [
        ('demo.mov', 1500, false),
        ('assets', 500, true),
      ]);
    });

    test('skips missing paths and the same path dropped twice', () async {
      final a = file('a.txt', 10);
      await dz.addDropped([(name: 'a.txt', path: a, isFolder: false)]);
      await dz.addDropped([
        (name: 'a.txt', path: a, isFolder: false),
        (name: 'gone', path: '${dir.path}/gone', isFolder: false),
        (name: 'gone/', path: '${dir.path}/nope', isFolder: true),
      ]);
      expect(dz.items, hasLength(1));
    });

    test('drag enter opens, leave keeps it open, close clears', () async {
      dz.dragEntered();
      expect([dz.open, dz.dragging], [true, true]);
      dz.dragLeft();
      expect([dz.open, dz.dragging], [true, false]);
      await dz.addDropped([(name: 'a', path: file('a', 1), isFolder: false)]);
      dz.close();
      expect([dz.open, dz.dragging, dz.items.isEmpty], [false, false, true]);
    });
  });

  group('DropzoneHost (T1.12, UI-02)', () {
    const pixel = NearbyDevice('Pixel 8', 'Android', PeerReach.online);
    late DropzoneController dz;
    late ValueNotifier<List<NearbyDevice>> devices;

    setUp(() {
      dz = DropzoneController();
      devices = ValueNotifier(const []);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildDropClipTheme(Brightness.dark),
        builder: (_, child) => DropzoneHost(
          controller: dz,
          devices: devices,
          nativeDrop: false,
          child: child!,
        ),
        // No focused widget, like the real app at start: the shortcut must
        // still work.
        home: const Scaffold(body: Text('app')),
      ));
    }

    testWidgets('closed at start; Ctrl+Alt+D opens it', (tester) async {
      await pump(tester);
      expect(find.byType(DropzonePanel), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byType(DropzonePanel), findsOneWidget);
    });

    testWidgets('shows live devices and sends the drop', (tester) async {
      await pump(tester);
      dz.show();
      await tester.pump();
      expect(find.text('No devices nearby'), findsOneWidget);
      devices.value = const [pixel];
      await dz.addDropped([]);
      await tester.pump();
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clicking outside or Esc closes it', (tester) async {
      await pump(tester);
      dz.show();
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(dz.open, isFalse);
      dz.show();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(DropzonePanel), findsNothing);
    });

    testWidgets('the shell\'s drop card opens it', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildDropClipTheme(Brightness.dark),
        home: DesktopShell(status: demoShellStatus, onOpenDropzone: dz.show),
      ));
      await tester.tap(find.text('Drop files to send'));
      expect(dz.open, isTrue);
    });
  });
}
