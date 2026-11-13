import 'package:dropclip_desktop/src/clipboard_aside.dart';
import 'package:dropclip_desktop/src/clipboard_page.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ShellStatus _status({List<int> latency = const [400, 412]}) => ShellStatus(
      networkName: 'n',
      address: 'a',
      verifiedDevices: 2,
      activeTransfers: 0,
      deviceCount: 3,
      nearby: demoShellStatus.nearby,
      latencyP95Ms: latency,
    );

Future<void> _pump(WidgetTester tester, Widget child, {double width = 1200}) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(MaterialApp(
    theme: buildDropClipTheme(Brightness.dark),
    home: Scaffold(body: child),
  ));
}

void main() {
  group('ClipboardAside (T1.12)', () {
    testWidgets('lists nearby devices with online/manual status',
        (tester) async {
      await _pump(tester, ClipboardAside(status: _status()));

      expect(find.text('2 online'), findsOneWidget);
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('iOS · Share Sheet'), findsOneWidget);
      expect(find.text('Online'), findsNWidgets(2));
      expect(find.text('Manual'), findsOneWidget);
    });

    testWidgets('link web, pair and dropzone call back', (tester) async {
      var pair = 0, drop = 0, web = 0;
      await _pump(
          tester,
          ClipboardAside(
              status: _status(),
              onPair: () => pair++,
              onOpenDropzone: () => drop++,
              onLinkWeb: () => web++));

      // Linking a phone browser is the first thing on the home screen.
      await tester.tap(find.byKey(const Key('home-link-web')));
      await tester.tap(find.text('Pair new device'));
      await tester.tap(find.text('Drop files to send'));
      expect((web, pair, drop), (1, 1, 1));
    });

    testWidgets('latency shows the latest p95 under the 1,000 ms target',
        (tester) async {
      await _pump(tester, ClipboardAside(status: _status()));

      expect(find.textContaining('412'), findsOneWidget);
      expect(find.text('Under 1,000 ms target'), findsOneWidget);
      expect(find.byKey(const ValueKey('latency-bar-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('latency-bar-2')), findsNothing);
    });

    testWidgets('latency at or over target is flagged', (tester) async {
      await _pump(tester,
          ClipboardAside(status: _status(latency: [300, latencyTargetMs])));
      expect(find.text('Over 1,000 ms target'), findsOneWidget);
    });

    testWidgets('empty state: no devices and no latency card', (tester) async {
      await _pump(
          tester,
          const ClipboardAside(
              status: ShellStatus(
                  networkName: 'n',
                  address: 'a',
                  verifiedDevices: 0,
                  activeTransfers: 0,
                  deviceCount: 0)));

      expect(find.text('0 online'), findsOneWidget);
      expect(find.text('No devices nearby'), findsOneWidget);
      expect(find.text('Sync latency · p95'), findsNothing);
    });

    testWidgets('Clipboard page hides the panel on narrow windows',
        (tester) async {
      await _pump(tester, ClipboardPage(status: _status()));
      expect(find.byType(ClipboardAside), findsOneWidget);

      await _pump(tester, ClipboardPage(status: _status()),
          width: asideMinPageWidth - 1);
      expect(find.byType(ClipboardAside), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
