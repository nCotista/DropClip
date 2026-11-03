import 'dart:async';

import 'tray_menu.dart';

/// OS events the desktop host reports.
sealed class HostEvent {
  const HostEvent();
}

/// Left click on the tray / menubar icon.
class TrayClicked extends HostEvent {
  const TrayClicked();
}

/// An item of the tray's native right-click menu.
class TrayMenuSelected extends HostEvent {
  final TrayAction action;

  const TrayMenuSelected(this.action);
}

/// The window's close button was pressed.
class WindowCloseRequested extends HostEvent {
  const WindowCloseRequested();
}

/// Tray icon + main window, kept behind an interface so [TrayController] is
/// testable and the plugin can be swapped (see `native_host.dart`).
abstract interface class DesktopHost {
  Stream<HostEvent> get events;

  /// Creates the tray icon with [tooltip] and a right-click menu of [menu].
  Future<void> init({required String tooltip, required List<TrayAction> menu});

  Future<void> showWindow();
  Future<void> hideWindow();

  /// Removes the tray icon and ends the app.
  Future<void> quit();
}

/// Tray behavior for T1.12 / NFR-U03: start hidden at login, closing the
/// window keeps DropClip running in the tray, and only Quit ends it.
class TrayController {
  final DesktopHost host;

  /// Called for tray actions that open a screen (e.g. Settings).
  final void Function(TrayAction action)? onAction;

  StreamSubscription<HostEvent>? _events;

  TrayController(this.host, {this.onAction});

  Future<void> start({required bool hidden}) async {
    await host.init(tooltip: 'DropClip', menu: TrayAction.values);
    _events ??= host.events.listen(_onEvent);
    await (hidden ? host.hideWindow() : host.showWindow());
  }

  Future<void> _onEvent(HostEvent event) async {
    switch (event) {
      case TrayClicked():
        await host.showWindow();
      case WindowCloseRequested():
        await host.hideWindow();
      case TrayMenuSelected(action: TrayAction.quit):
        await stop();
        await host.quit();
      case TrayMenuSelected(:final action):
        await host.showWindow();
        onAction?.call(action);
    }
  }

  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
  }
}
