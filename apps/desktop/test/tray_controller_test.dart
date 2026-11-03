import 'dart:async';

import 'package:dropclip_desktop/src/l10n/strings.dart';
import 'package:dropclip_desktop/src/shell.dart';
import 'package:dropclip_desktop/src/tray_controller.dart';
import 'package:dropclip_desktop/src/tray_menu.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHost implements DesktopHost {
  final controller = StreamController<HostEvent>.broadcast();
  final calls = <String>[];
  List<(TrayAction, String)>? menu;

  @override
  Stream<HostEvent> get events => controller.stream;

  @override
  Future<void> init(
      {required String tooltip,
      required List<(TrayAction, String)> menu}) async {
    calls.add('init $tooltip');
    this.menu = menu;
  }

  @override
  Future<void> setMenu(List<(TrayAction, String)> menu) async {
    calls.add('menu');
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
      expect(host.menu, [
        for (final a in TrayAction.values) (a, a.labelIn(const EnStrings())),
      ]);
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

  group('native tray menu language (NFR-L01)', () {
    List<String> labels() => [for (final (_, l) in host.menu!) l];

    test('starts in the configured language', () async {
      await tray.start(hidden: true, strings: const ThStrings());
      expect(labels(), [
        for (final a in TrayAction.values) a.labelIn(const ThStrings()),
      ]);
      expect(labels(), isNot(contains('Quit DropClip')));
    });

    test('switching language rebuilds the menu once', () async {
      await tray.start(hidden: true);
      host.calls.clear();
      await tray.setStrings(const ThStrings());
      await tray.setStrings(const ThStrings());
      expect(host.calls, ['menu']);
      expect(labels().last, const ThStrings().trayQuit);
    });

    test('a change before start is used at start, not sent early', () async {
      await tray.setStrings(const ThStrings());
      expect(host.calls, isEmpty);
      await tray.start(hidden: true, strings: const ThStrings());
      expect(host.calls, ['init DropClip', 'hide']);
    });

    test('after stop, a language change is not sent', () async {
      await tray.start(hidden: true);
      await tray.stop();
      host.calls.clear();
      await tray.setStrings(const ThStrings());
      expect(host.calls, isEmpty);
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
