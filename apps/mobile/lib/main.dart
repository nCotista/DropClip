import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/mobile_app.dart';
import 'src/mobile_node.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final received = ValueNotifier<List<String>>(const []);
  final node = await MobileNode.start(
    dir: await getApplicationSupportDirectory(),
    keys: SecureStorageKeyStore(),
    name: Platform.isIOS ? 'iPhone' : 'Android phone',
    os: Platform.isIOS ? 'ios' : 'android',
    writeClipboard: (text) => Clipboard.setData(ClipboardData(text: text)),
    onReceived: (text, from) =>
        received.value = ['$from: $text', ...received.value].take(20).toList(),
  );
  await node.reconnect();
  runApp(DropClipMobileApp(
    node: node,
    received: received,
    readClipboard: () async =>
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
  ));
}
