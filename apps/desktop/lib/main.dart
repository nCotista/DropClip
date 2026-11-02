import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/demo_data.dart';
import 'src/native_host.dart';
import 'src/shell.dart';
import 'src/tray_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // `--hidden` is passed by the login item / Run key (T1.12, NFR-U03).
  final hidden = args.contains('--hidden');
  final section = ValueNotifier(ShellSection.clipboard);

  final tray = TrayController(
    NativeDesktopHost(isMacOS: defaultTargetPlatform == TargetPlatform.macOS),
    onAction: (a) => section.value = sectionForTrayAction(a),
  );
  await tray.start(hidden: hidden);

  runApp(DropClipDesktopApp(
    hiddenLaunch: hidden,
    status: demoShellStatus,
    section: section,
  ));
}
