import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/mobile_app.dart';
import 'src/mobile_node.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final settingsFile = File('${dir.path}/settings.json');
  final settings = ValueNotifier(await MobileSettings.load(settingsFile));
  settings.addListener(() => settings.value.save(settingsFile));
  final received = ValueNotifier<List<ReceivedClip>>(const []);
  Future<void> writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  final node = await MobileNode.start(
    dir: dir,
    keys: SecureStorageKeyStore(),
    name: Platform.isIOS ? 'iPhone' : 'Android phone',
    os: Platform.isIOS ? 'ios' : 'android',
    writeClipboard: writeClipboard,
    syncEnabled: () => settings.value.syncEnabled,
    onReceived: (text, from) => received.value =
        [(from: from, text: text), ...received.value].take(20).toList(),
  );
  await node.reconnect();
  // Back from the background: the socket is usually dead by then.
  AppLifecycleListener(onResume: node.reconnect);
  runApp(DropClipMobileApp(
    node: node,
    received: received,
    settings: settings,
    readClipboard: () async =>
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
    writeClipboard: writeClipboard,
    pickFile: () async => (await FilePicker.pickFiles()).firstOrNull?.path,
  ));
}
