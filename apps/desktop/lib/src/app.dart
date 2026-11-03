import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'shell.dart';

class DropClipDesktopApp extends StatelessWidget {
  /// Started at login with `--hidden`: stay in the tray, no window (NFR-U03).
  /// Hiding the window needs the tray integration (next T1.12 PR).
  final bool hiddenLaunch;
  final ShellStatus status;

  const DropClipDesktopApp({
    super.key,
    required this.hiddenLaunch,
    required this.status,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: DropClipThemeTokens.appName,
        debugShowCheckedModeBanner: false,
        theme: buildDropClipTheme(Brightness.light),
        darkTheme: buildDropClipTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: DesktopShell(status: status),
      );
}
