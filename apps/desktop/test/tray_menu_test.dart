import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/tray_menu.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  ShellStatus status = demoShellStatus,
  bool sync = true,
  ValueChanged<bool>? onSync,
  ValueChanged<TrayAction>? onAction,
  TargetPlatform platform = TargetPlatform.windows,
}) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(MaterialApp(
    theme: buildDropClipTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: TrayMenu(
          status: status,
          syncEnabled: sync,
          onSyncChanged: onSync ?? (_) {},
          onAction: onAction ?? (_) {},
          platform: platform,
        ),
      ),
    ),
  ));
}

void main() {
  group('TrayMenu (T1.12, UI-01)', () {
    testWidgets('header shows network and online devices', (tester) async {
      await _pump(tester);

      expect(find.text('Connected · Home-WiFi'), findsOneWidget);
      expect(find.text('ONLINE DEVICES'), findsOneWidget);
      for (final d in demoShellStatus.nearby) {
        expect(find.text(d.name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('every action is listed and reported when tapped',
        (tester) async {
      final tapped = <TrayAction>[];
      await _pump(tester, onAction: tapped.add);

      for (final a in TrayAction.values) {
        await tester.tap(find.text(a.label));
      }
      expect(tapped, TrayAction.values);
    });

    testWidgets('Windows shows Ctrl shortcuts', (tester) async {
      await _pump(tester);
      expect(find.text('Ctrl+Alt+D'), findsOneWidget);
      expect(find.text('Ctrl+,'), findsOneWidget);
      expect(find.text('⌘Q'), findsNothing);
    });

    testWidgets('macOS shows ⌘ shortcuts', (tester) async {
      await _pump(tester, platform: TargetPlatform.macOS);
      expect(find.text('⌥⌘D'), findsOneWidget);
      expect(find.text('⌘Q'), findsOneWidget);
      expect(find.text('Ctrl+Alt+D'), findsNothing);
    });

    testWidgets('sync switch reports the new value', (tester) async {
      final values = <bool>[];
      await _pump(tester, sync: true, onSync: values.add);

      await tester.tap(find.byType(Switch));
      expect(values, [false]);
    });

    testWidgets('no devices shows an empty state', (tester) async {
      await _pump(tester,
          status: const ShellStatus(
              networkName: 'Office',
              address: 'a',
              verifiedDevices: 0,
              activeTransfers: 0,
              deviceCount: 0));
      expect(find.text('No devices nearby'), findsOneWidget);
      expect(find.text('Connected · Office'), findsOneWidget);
    });

    test('shortcut labels per platform', () {
      expect(TrayAction.quit.shortcutFor(TargetPlatform.windows), isNull);
      expect(TrayAction.pair.shortcutFor(TargetPlatform.macOS), isNull);
      expect(TrayAction.settings.shortcutFor(TargetPlatform.macOS), '⌘,');
    });
  });
}
