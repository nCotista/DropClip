import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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
  // Android: the app's own Download folder (visible in Files); iOS: Documents.
  final saveTo = Directory(
      '${(await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory()).path}/DropClip');
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
  await node.reconnect();
  try {
    await node.startDiscovery(BonsoirMdnsBackend());
  } on Object {
    // No multicast on this network: saved addresses still work.
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
