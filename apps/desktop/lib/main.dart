import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/demo_data.dart';

void main(List<String> args) {
  // `--hidden` is passed by the login item / Run key (T1.12, NFR-U03).
  runApp(DropClipDesktopApp(
    hiddenLaunch: args.contains('--hidden'),
    status: demoShellStatus,
  ));
}
