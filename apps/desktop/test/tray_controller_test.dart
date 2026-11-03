import 'dart:async';

import 'package:dropclip_desktop/src/shell.dart';
import 'package:dropclip_desktop/src/tray_controller.dart';
import 'package:dropclip_desktop/src/tray_menu.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHost implements DesktopHost {
  final controller = StreamController<HostEvent>.broadcast();
  final calls = <String>[];
  List<TrayAction>? menu;

  @override
  Stream<HostEvent> get events => controller.stream;

  @override
  Future<void> init(
      {required String tooltip, required List<TrayAction> menu}) async {
    calls.add('init $tooltip');
    this.menu = menu;
  }

  @override
  Future<void> showWindow() async => calls.add('show');

  @override
  Future<void> hideWindow() async => calls.add('hide');

  @override
  Future<void> quit() async => calls.add('quit');

  Future<void> emit(HostEvent e) async {
    controller.add(e);
    await pumpEventQueue();
  }
}

void main() {
  late _FakeHost host;
  late List<TrayAction> opened;
  late TrayController tray;

  setUp(() {
    host = _FakeHost();
    opened = [];
    tray = TrayController(host, onAction: opened.add);
  });

  tearDown(() async {
    await tray.stop();
    await host.controller.close();
  });

  group('TrayController (T1.12, NFR-U03)', () {
    test('normal launch creates the tray and shows the window', () async {
      await tray.start(hidden: false);
      expect(host.calls, ['init DropClip', 'show']);
      expect(host.menu, TrayAction.values);
    });

    test('--hidden launch keeps the window hidden', () async {
      await tray.start(hidden: true);
      expect(host.calls, ['init DropClip', 'hide']);
    });

    test('closing the window hides it to the tray instead of quitting',
        () async {
      await tray.start(hidden: false);
      host.calls.clear();
      await host.emit(const WindowCloseRequested());
      expect(host.calls, ['hide']);
    });

    test('tray click brings the window back', () async {
      await tray.start(hidden: true);
      host.calls.clear();
      await host.emit(const TrayClicked());
      expect(host.calls, ['show']);
    });

    test('menu actions show the window and open their screen', () async {
      await tray.start(hidden: true);
      host.calls.clear();
      await host.emit(const TrayMenuSelected(TrayAction.settings));
      expect(host.calls, ['show']);
      expect(opened, [TrayAction.settings]);
    });

    test('Quit stops listening and ends the app', () async {
      await tray.start(hidden: false);
      host.calls.clear();
      await host.emit(const TrayMenuSelected(TrayAction.quit));
      await host.emit(const TrayClicked());
      expect(host.calls, ['quit']);
      expect(opened, isEmpty);
    });

    test('start twice subscribes once', () async {
      await tray.start(hidden: false);
      await tray.start(hidden: false);
      host.calls.clear();
      await host.emit(const TrayClicked());
      expect(host.calls, ['show']);
    });
  });

  test('tray actions map to shell sections', () {
    expect(sectionForTrayAction(TrayAction.settings), ShellSection.settings);
    expect(
        sectionForTrayAction(TrayAction.trustedDevices), ShellSection.devices);
    expect(
        sectionForTrayAction(TrayAction.openDropzone), ShellSection.clipboard);
  });
}
