import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_panel.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pixel = NearbyDevice('Pixel 8', 'Android · ready', PeerReach.online);
const _surface =
    NearbyDevice('Surface Laptop', 'Windows · ready', PeerReach.online);
const _iphone = NearbyDevice(
    'iPhone 15', 'iOS · open DropClip to receive', PeerReach.manual);
const _files = [
  DroppedItem('demo-recording.mov', 1600000000),
  DroppedItem('assets', 100000000, isFolder: true),
];

void main() {
  late List<(String, int)> sent;
  late int closed;

  setUp(() {
    sent = [];
    closed = 0;
  });

  Future<void> show(WidgetTester tester,
      {List<DroppedItem> items = _files,
      List<NearbyDevice> devices = const [_pixel, _surface, _iphone],
      bool dragging = false,
      bool canSend = true}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDropClipTheme(Brightness.dark),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 640,
          child: DropzonePanel(
            items: items,
            devices: devices,
            dragging: dragging,
            onClose: () => closed++,
            onSend: canSend ? (to, i) => sent.add((to.name, i.length)) : null,
          ),
        ),
      ),
    ));
  }

  group('DropzonePanel (T1.12, UI-02)', () {
    testWidgets('shows the drop, the devices and sends to the first one',
        (tester) async {
      await show(tester);
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('demo-recording.mov, assets/ · 1.7 GB'), findsOneWidget);
      expect(find.text('iOS · open DropClip to receive'), findsOneWidget);
      await tester.tap(find.text('Send to Pixel 8'));
      expect(sent, [('Pixel 8', 2)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('↑/↓ pick a device, Enter sends, Esc closes', (tester) async {
      await show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // stays last
      await tester.pump();
      expect(find.text('Send to iPhone 15'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(sent, [('Surface Laptop', 2)]);
      expect(closed, 1);
    });

    testWidgets('clicking a device picks it', (tester) async {
      await show(tester);
      await tester.tap(find.text('Surface Laptop'));
      await tester.pump();
      expect(find.text('Send to Surface Laptop'), findsOneWidget);
    });

    testWidgets('nothing dropped yet: prompt shown, Send disabled',
        (tester) async {
      await show(tester, items: const []);
      expect(find.text('Drop files or folders here'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.text('Send to Pixel 8'));
      expect(sent, isEmpty);
    });

    testWidgets('while dragging, the area says release', (tester) async {
      await show(tester, dragging: true);
      expect(find.text('Release to add'), findsOneWidget);
    });

    testWidgets('no devices nearby: message shown, cannot send',
        (tester) async {
      await show(tester, devices: const []);
      expect(find.text('No devices nearby'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sending unavailable keeps Send disabled', (tester) async {
      await show(tester, canSend: false);
      final button = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Send to Pixel 8'),
          matching: find.bySubtype<ButtonStyleButton>()));
      expect(button.onPressed, isNull);
    });
  });

  test('formatBytes uses 1000-based units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1500), '1.5 KB');
    expect(formatBytes(1700000000), '1.7 GB');
    expect(formatBytes(5 * 1000 * 1000 * 1000 * 1000 * 1000), '5000.0 TB');
  });
}
