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
  final Widget? banner;

  /// Wraps every page, e.g. with the Dropzone overlay.
  final TransitionBuilder? overlay;
  final VoidCallback? onOpenDropzone;

  const DropClipDesktopApp({
    super.key,
    required this.hiddenLaunch,
    required this.status,
    this.section,
    this.liveStatus,
    this.settingsPage,
    this.banner,
    this.overlay,
    this.onOpenDropzone,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
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
                banner: banner,
                onOpenDropzone: onOpenDropzone)
            : ValueListenableBuilder<ShellStatus>(
                valueListenable: liveStatus!,
                builder: (_, s, __) => DesktopShell(
                    status: s,
                    section: section,
                    settingsPage: settingsPage,
                    banner: banner,
                    onOpenDropzone: onOpenDropzone),
              ),
      );
}
