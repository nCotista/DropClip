import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/pairing/pairing_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _peer = TrustedDevice(
    deviceId: '00000000-0000-4000-8000-000000000002',
    name: 'Office PC',
    os: 'windows',
    tier: 1,
    fp: '',
    pairedAt: 0,
    lastSeenAt: 0);

Future<void> _show(WidgetTester tester, Widget dialog) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));

void main() {
  testWidgets('Host shows the PIN, then asks about the SAS', (tester) async {
    final events = StreamController<PairingHostEvent>.broadcast();
    addTearDown(events.close);
    final answers = <bool>[];
    await _show(
        tester,
        HostPairingDialog(
            open: () async =>
                (pin: '482910', address: '192.168.1.5:53317', qr: '{}'),
            events: events.stream,
            confirm: answers.add));
    await tester.pump();
    expect(find.text('482 910'), findsOneWidget);
    expect(find.text('192.168.1.5:53317'), findsOneWidget);
    expect(find.byKey(const Key('pair-qr')), findsOneWidget);

    events.add(const PairingSasReady('639589', 'Office PC', 'windows'));
    await tester.pump();
    expect(find.text('639 589'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sas-yes')));
    await tester.pump();
    expect(answers, [true]);
    expect(find.text('Waiting for the other device…'), findsOneWidget);

    events.add(const PairingCompleted(_peer));
    await tester.pump();
    expect(find.text('Paired with Office PC'), findsOneWidget);
  });

  testWidgets('Client types the PIN, compares the SAS, sees the result',
      (tester) async {
    String? typedPin;
    late Future<bool> answer;
    final done = Completer<TrustedDevice>();
    await _show(
        tester,
        ClientPairingDialog(
            peerName: 'Office PC',
            pair: (pin, confirm) {
              typedPin = pin;
              answer = confirm('639589', 'Office PC');
              return done.future;
            }));
    expect(find.text('Enter the PIN shown on Office PC'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pin-field')), '482910');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pump();
    expect(typedPin, '482910');
    expect(find.text('639 589'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sas-no')));
    await tester.pump();
    expect(await answer, isFalse);
    done.completeError(const PairingClientException('E_SAS_FAILED', ''));
    await tester.pump();
    expect(find.text('Pairing failed (E_SAS_FAILED)'), findsOneWidget);
  });
}
