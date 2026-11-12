import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'shell.dart';

class DropClipDesktopApp extends StatelessWidget {
  /// Started at login with `--hidden`: stay in the tray, no window (NFR-U03).
  /// The window itself is hidden by `TrayController`.
  final bool hiddenLaunch;
  final ShellStatus status;
  final ValueNotifier<ShellSection>? section;

  /// When set, replaces [status] and rebuilds the shell on every change
  /// (e.g. live mDNS discovery).
  final ValueListenable<ShellStatus>? liveStatus;
  final Widget? settingsPage;
  final Widget? transfersPage;
  final Widget? devicesPage;
  final Widget? banner;

  /// Wraps every page, e.g. with the Dropzone overlay.
  final TransitionBuilder? overlay;
  final VoidCallback? onOpenDropzone;
  final VoidCallback? onSendClipboard;
  final VoidCallback? onPair;

  /// "Copy again" on a history item.
  final ValueChanged<ClipItem>? onCopyClip;

  /// Lets callbacks outside the widget tree open dialogs.
  final GlobalKey<NavigatorState>? navigatorKey;

  const DropClipDesktopApp({
    super.key,
    required this.hiddenLaunch,
    required this.status,
    this.section,
    this.liveStatus,
    this.settingsPage,
    this.transfersPage,
    this.devicesPage,
    this.banner,
    this.overlay,
    this.onOpenDropzone,
    this.onSendClipboard,
    this.onPair,
    this.navigatorKey,
    this.onCopyClip,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        title: DropClipThemeTokens.appName,
        debugShowCheckedModeBanner: false,
        theme: buildDropClipTheme(Brightness.light),
        darkTheme: buildDropClipTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        builder: overlay,
        home: liveStatus == null
            ? DesktopShell(
                status: status,
                section: section,
                settingsPage: settingsPage,
                transfersPage: transfersPage,
                devicesPage: devicesPage,
                banner: banner,
                onOpenDropzone: onOpenDropzone,
                onSendClipboard: onSendClipboard,
                onPair: onPair,
                onCopyClip: onCopyClip)
            : ValueListenableBuilder<ShellStatus>(
                valueListenable: liveStatus!,
                builder: (_, s, __) => DesktopShell(
                    status: s,
                    section: section,
                    settingsPage: settingsPage,
                    transfersPage: transfersPage,
                    devicesPage: devicesPage,
                    banner: banner,
                    onOpenDropzone: onOpenDropzone,
                    onSendClipboard: onSendClipboard,
                    onPair: onPair,
                    onCopyClip: onCopyClip),
              ),
      );
}
