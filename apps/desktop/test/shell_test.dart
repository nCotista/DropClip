import 'package:dropclip_desktop/src/app.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      const DropClipDesktopApp(hiddenLaunch: false, status: demoShellStatus));
}

/// Page heading text, i.e. the label that is not inside the sidebar.
Finder _heading(String label) => find.byWidgetPredicate((w) =>
    w is Text &&
    w.data == label &&
    (w.style?.fontWeight ?? FontWeight.normal) == FontWeight.w700);

void main() {
  group('DesktopShell (T1.12)', () {
    testWidgets('opens on Clipboard with all sections and counts',
        (tester) async {
      await _pumpApp(tester);

      for (final label in ['Clipboard', 'Transfers', 'Devices', 'Settings']) {
        expect(find.text(label), findsWidgets);
      }
      expect(_heading('Clipboard'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('selecting a section switches the page', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Devices'));
      await tester.pump();
      expect(_heading('Devices'), findsOneWidget);
      expect(_heading('Clipboard'), findsNothing);

      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(_heading('Settings'), findsOneWidget);
    });

    testWidgets('sidebar shows this device with a port in 53317–53417',
        (tester) async {
      await _pumpApp(tester);

      expect(find.text('Home-WiFi'), findsOneWidget);
      expect(find.text('3 devices verified (SAS)'), findsOneWidget);
      final port = int.parse(demoShellStatus.address.split(':').last);
      expect(port, inInclusiveRange(53317, 53417));
      expect(find.text(demoShellStatus.address), findsOneWidget);
    });

    testWidgets('follows the OS light/dark setting', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(tester);
      Color canvas() => Theme.of(tester.element(find.byType(Scaffold)))
          .scaffoldBackgroundColor;
      expect(canvas(), DropClipColors.light.canvas);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(canvas(), DropClipColors.dark.canvas);
    });

    testWidgets('small window does not overflow', (tester) async {
      tester.view.physicalSize = const Size(900, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const DropClipDesktopApp(
          hiddenLaunch: true, status: demoShellStatus));
      expect(tester.takeException(), isNull);
    });
  });
}
