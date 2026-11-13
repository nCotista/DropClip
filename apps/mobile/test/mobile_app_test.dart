import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_mobile/src/mobile_app.dart';
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
  Future<void>? beforeSas, afterMatch;
  bool? decision;

  @override
  Future<TrustedDevice> pair(String host, int port, String pin,
      Future<bool> Function(String sas, String hostName) confirm) async {
    pairedWith = '$host:$port/$pin';
    if (beforeSas != null) await beforeSas;
    decision = await confirm('639589', 'Office PC');
    if (decision != true) throw StateError('mismatch');
    if (afterMatch != null) await afterMatch;
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
  Future<TrustedDevice> pairWithQr(String scanned,
          Future<bool> Function(String sas, String hostName) confirm) =>
      pair('qr', 0, scanned, confirm);

  @override
  void sendText(String text) => sent.add(text);
}

Future<void> _start(WidgetTester tester, _FakePeer peer) async {
  await tester.pumpWidget(DropClipMobileApp(
      node: peer,
      received: ValueNotifier(const <String>[]),
      readClipboard: () async => null));
  await tester.tap(find.byKey(const Key('pair')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('host')), '127.0.0.1');
  await tester.enterText(find.byKey(const Key('pin')), '482910');
  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
}

Future<void> _dismiss(WidgetTester tester) async {
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  testWidgets('Does not match rejects SAS and creates no trusted peer',
      (tester) async {
    final peer = _FakePeer();
    await _start(tester, peer);
    await tester.tap(find.text("Doesn't match"));
    await tester.pumpAndSettle();
    expect(peer.decision, isFalse);
    expect(peer.trusted.value, isEmpty);
    expect(find.textContaining('Pairing failed:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing while SAS is pending resolves rejection',
      (tester) async {
    final peer = _FakePeer();
    await _start(tester, peer);
    expect(find.byKey(const Key('sas')), findsOneWidget);
    await _dismiss(tester);
    expect(peer.decision, isFalse);
    expect(peer.trusted.value, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SAS arriving after dismissal is rejected without rebuilding',
      (tester) async {
    final reply = Completer<void>();
    final peer = _FakePeer()..beforeSas = reply.future;
    await _start(tester, peer);
    await _dismiss(tester);
    reply.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(peer.decision, isFalse);
    expect(peer.trusted.value, isEmpty);
    expect(find.byKey(const Key('sas')), findsNothing);
  });

  testWidgets('network error after dismissal does not update disposed state',
      (tester) async {
    final reply = Completer<void>();
    final peer = _FakePeer()..beforeSas = reply.future;
    await _start(tester, peer);
    await _dismiss(tester);
    reply.completeError(StateError('test network failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(peer.trusted.value, isEmpty);
    expect(find.textContaining('Pairing failed:'), findsNothing);
  });

  testWidgets('late success after explicit Match does not reopen the dialog',
      (tester) async {
    final reply = Completer<void>();
    final peer = _FakePeer()..afterMatch = reply.future;
    await _start(tester, peer);
    await tester.tap(find.byKey(const Key('match')));
    await tester.pumpAndSettle();
    expect(peer.decision, isTrue);
    await _dismiss(tester);
    reply.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(peer.trusted.value, hasLength(1));
    expect(find.text('Paired with Office PC'), findsNothing);
  });

  testWidgets('repeated rejection answers the pending SAS only once',
      (tester) async {
    final peer = _FakePeer();
    await _start(tester, peer);
    await tester.tap(find.text("Doesn't match"));
    await tester.tap(find.text("Doesn't match"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(peer.decision, isFalse);
    expect(peer.trusted.value, isEmpty);
  });

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
