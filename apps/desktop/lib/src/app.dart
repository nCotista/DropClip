import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'shell.dart';

class DropClipDesktopApp extends StatelessWidget {
  /// Started at login with `--hidden`: stay in the tray, no window (NFR-U03).
  /// The window itself is hidden by `TrayController`.
  final bool hiddenLaunch;
  final ShellStatus status;
  final ValueNotifier<ShellSection>? section;

  const DropClipDesktopApp({
    super.key,
    required this.hiddenLaunch,
    required this.status,
    this.section,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: DropClipThemeTokens.appName,
        debugShowCheckedModeBanner: false,
        theme: buildDropClipTheme(Brightness.light),
        darkTheme: buildDropClipTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: DesktopShell(status: status, section: section),
      );
}
