import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'src/bonsoir_backend.dart';
import 'src/mobile_app.dart';
import 'src/mobile_node.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final settingsFile = File('${dir.path}/settings.json');
  final settings = ValueNotifier(await MobileSettings.load(settingsFile));
  settings.addListener(() => settings.value.save(settingsFile));
  final received = ValueNotifier<List<ReceivedClip>>(const []);
  void add(ReceivedClip c) =>
      received.value = [c, ...received.value].take(30).toList();
  // Android: the app's own Download folder; iOS: Documents, which the Files
  // app shows under "On My iPhone › DropClip" (UIFileSharingEnabled).
  final saveTo = Directory(
      '${(Platform.isIOS ? null : await getDownloadsDirectory()) ?? (await getApplicationDocumentsDirectory()).path}/DropClip');
  Future<void> writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  final node = await MobileNode.start(
    dir: dir,
    keys: SecureStorageKeyStore(),
    name: Platform.isIOS ? 'iPhone' : 'Android phone',
    os: Platform.isIOS ? 'ios' : 'android',
    writeClipboard: writeClipboard,
    syncEnabled: () => settings.value.syncEnabled,
    onReceived: (text, from) => add((from: from, text: text, path: null)),
    received: saveTo,
    onFile: (file, from) =>
        add((from: from, text: file.uri.pathSegments.last, path: file.path)),
  );
  try {
    await node.reconnect();
  } on Object {
    // Start offline rather than never showing the UI; discovery and the
    // resume hook will try again.
  }
  try {
    await node.startDiscovery(BonsoirMdnsBackend());
  } on Object {
    // No multicast on this network: saved addresses still work.
  }
  // iOS pauses the app (its link and its file server) seconds after the
  // screen locks, so the computer could not send to it. Keep the screen on
  // while DropClip is open; the OS drops this once the app is left.
  try {
    await WakelockPlus.enable();
  } on Object {
    // Not supported here: the screen just locks as usual.
  }
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
    openFile: (path) => OpenFilex.open(path),
  ));
}
