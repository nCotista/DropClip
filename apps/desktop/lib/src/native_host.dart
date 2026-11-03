import 'dart:async';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'tray_controller.dart';
import 'tray_menu.dart';

/// [DesktopHost] backed by tray_manager and window_manager 0.5.x. Those use
/// platform channels; 0.6+ moved to nativeapi, whose build hook compiles C++
/// during `flutter test` (needs a compiler on every CI runner) and which does
/// not deliver window close requests yet.
///
/// Not unit-tested: it needs a real Windows/macOS session.
class NativeDesktopHost
    with TrayListener, WindowListener
    implements DesktopHost {
  /// Placeholder icons until the design provides tray artwork.
  static const _windowsIcon = 'assets/tray/tray_icon.ico';
  static const _macIcon = 'assets/tray/tray_icon.png';

  final bool isMacOS;
  final _events = StreamController<HostEvent>.broadcast();

  NativeDesktopHost({required this.isMacOS});

  @override
  Stream<HostEvent> get events => _events.stream;

  @override
  Future<void> init({
    required String tooltip,
    required List<(TrayAction, String)> menu,
  }) async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    trayManager.addListener(this);
    await trayManager.setIcon(isMacOS ? _macIcon : _windowsIcon);
    await trayManager.setToolTip(tooltip);
    await setMenu(menu);
  }

  @override
  Future<void> setMenu(List<(TrayAction, String)> menu) =>
      trayManager.setContextMenu(Menu(items: [
        for (final (a, label) in menu) ...[
          if (a == TrayAction.quit) MenuItem.separator(),
          MenuItem(key: a.name, label: label),
        ],
      ]));

  @override
  void onTrayIconMouseDown() => _events.add(const TrayClicked());

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    for (final a in TrayAction.values) {
      if (a.name == menuItem.key) _events.add(TrayMenuSelected(a));
    }
  }

  @override
  void onWindowClose() => _events.add(const WindowCloseRequested());

  @override
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hideWindow() => windowManager.hide();

  @override
  Future<void> quit() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await _events.close();
    await windowManager.destroy();
  }
}
