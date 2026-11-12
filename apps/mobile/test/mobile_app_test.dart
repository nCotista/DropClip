import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_mobile/src/mobile_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePeer implements MobilePeer {
  @override
  final ValueNotifier<List<TrustedDevice>> trusted = ValueNotifier(const []);
  @override
  Stream<Set<String>> get connectedChanges => const Stream.empty();
  @override
  Set<String> get connected => const {};
  final sent = <String>[];
  String? pairedWith;

  @override
  Future<TrustedDevice> pair(String host, int port, String pin,
      Future<bool> Function(String sas, String hostName) confirm) async {
    pairedWith = '$host:$port/$pin';
    if (!await confirm('639589', 'Office PC')) throw StateError('mismatch');
    const d = TrustedDevice(
        deviceId: 'd',
        name: 'Office PC',
        os: 'windows',
        tier: 1,
        fp: '',
        pairedAt: 0,
        lastSeenAt: 0);
    trusted.value = [d];
    return d;
  }

  @override
  void sendText(String text) => sent.add(text);
}

void main() {
  testWidgets('pair by IP + PIN with SAS, then send the clipboard',
      (tester) async {
    final peer = _FakePeer();
    await tester.pumpWidget(DropClipMobileApp(
        node: peer,
        received: ValueNotifier(const ['Office PC: hello']),
        readClipboard: () async => 'from phone'));
    expect(find.text('No paired computers yet'), findsOneWidget);
    expect(find.text('Office PC: hello'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pair')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('host')), '192.168.1.5');
    await tester.enterText(find.byKey(const Key('pin')), '482910');
    await tester.tap(find.byKey(const Key('go')));
    await tester.pump();
    expect(find.text('639589'), findsOneWidget);
    await tester.tap(find.byKey(const Key('match')));
    await tester.pumpAndSettle();
    expect(peer.pairedWith, '192.168.1.5:53317/482910');
    expect(find.text('Paired with Office PC'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);

    await tester.tap(find.byKey(const Key('send-clipboard')));
    await tester.pump();
    expect(peer.sent, ['from phone']);
  });
}
