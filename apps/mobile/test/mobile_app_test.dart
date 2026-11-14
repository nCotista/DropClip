import 'dart:async';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_mobile/src/mobile_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePeer implements MobilePeer {
  @override
  final ValueNotifier<List<TrustedDevice>> trusted = ValueNotifier(const []);
  @override
  Stream<Set<String>> get connectedChanges => const Stream.empty();
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

  @override
  String get myName => 'Pixel 8';

  final forgotten = <String>[];
  @override
  Future<void> forget(String deviceId) async {
    forgotten.add(deviceId);
    trusted.value = [
      for (final d in trusted.value)
        if (d.deviceId != deviceId) d
    ];
  }

  Set<String> online = const {};
  @override
  Set<String> get connected => online;

  final files = <String>[];
  @override
  Future<void> sendFile(String deviceId, String path,
      {void Function(int sent, int total)? onProgress}) async {
    onProgress?.call(5, 10);
    onProgress?.call(10, 10);
    files.add('$deviceId $path');
  }
}

const _pc = TrustedDevice(
    deviceId: 'pc',
    name: 'Office PC',
    os: 'windows',
    tier: 1,
    fp: '',
    pairedAt: 0,
    lastSeenAt: 0);

Future<
        ({
          ValueNotifier<List<ReceivedClip>> received,
          ValueNotifier<MobileSettings> settings,
          List<String> clipboard,
          List<String> opened,
        })>
    _app(WidgetTester tester, _FakePeer peer,
        {List<ReceivedClip> received = const [],
        String? clipboard,
        String? picked}) async {
  final r = ValueNotifier(received);
  final s = ValueNotifier(const MobileSettings());
  final written = <String>[];
  final opened = <String>[];
  await tester.pumpWidget(DropClipMobileApp(
      node: peer,
      received: r,
      settings: s,
      readClipboard: () async => clipboard,
      writeClipboard: (t) async => written.add(t),
      pickFile: () async => picked,
      openFile: (p) async => opened.add(p)));
  return (received: r, settings: s, clipboard: written, opened: opened);
}

Future<void> _start(WidgetTester tester, _FakePeer peer) async {
  await _app(tester, peer);
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

  testWidgets('copy again puts a received clip back; clear empties the list',
      (tester) async {
    final app = await _app(tester, _FakePeer(),
        received: const [(from: 'Office PC', text: 'hello', path: null)]);
    expect(find.text('From Office PC'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy again'));
    await tester.pump();
    expect(app.clipboard, ['hello']);
    await tester.tap(find.byKey(const Key('clear')));
    await tester.pump();
    expect(app.received.value, isEmpty);
    expect(find.text('Nothing received yet'), findsOneWidget);
  });

  testWidgets('a received file opens from its row', (tester) async {
    final app = await _app(tester, _FakePeer(), received: const [
      (from: 'Office PC', text: 'report.pdf', path: '/dl/DropClip/report.pdf')
    ]);
    await tester.tap(find.byKey(const Key('file-report.pdf')));
    await tester.tap(find.byTooltip('Open'));
    expect(app.opened, ['/dl/DropClip/report.pdf', '/dl/DropClip/report.pdf']);
    expect(app.clipboard, isEmpty);
  });

  testWidgets('a paired computer can be removed after confirming',
      (tester) async {
    final peer = _FakePeer()..trusted.value = const [_pc];
    await _app(tester, peer);
    await tester.tap(find.byKey(const Key('remove-pc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-remove')));
    await tester.pumpAndSettle();
    expect(peer.forgotten, ['pc']);
    expect(find.text('No computer yet'), findsOneWidget);
  });

  testWidgets('send file goes to the connected computer', (tester) async {
    final peer = _FakePeer()
      ..trusted.value = const [_pc]
      ..online = {'pc'};
    await _app(tester, peer, picked: '/sdcard/Download/report.pdf');
    await tester.tap(find.byKey(const Key('send-file')));
    await tester.pumpAndSettle();
    expect(peer.files, ['pc /sdcard/Download/report.pdf']);
    expect(find.text('Sent report.pdf'), findsOneWidget);
  });

  testWidgets('send file with no computer connected says so', (tester) async {
    final peer = _FakePeer()..trusted.value = const [_pc];
    await _app(tester, peer, picked: '/x.pdf');
    await tester.tap(find.byKey(const Key('send-file')));
    await tester.pump();
    expect(peer.files, isEmpty);
    expect(find.text('No computer is connected'), findsOneWidget);
  });

  testWidgets('settings: Thai switches the screen, sync off stops sending',
      (tester) async {
    final peer = _FakePeer();
    final app = await _app(tester, peer, clipboard: 'secret');
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    expect(find.text('Pixel 8'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sync-switch')));
    await tester.tap(find.text('ไทย'));
    await tester.pumpAndSettle();
    expect(
        app.settings.value,
        isA<MobileSettings>()
            .having((s) => s.syncEnabled, 'sync', false)
            .having((s) => s.language, 'language', 'th'));
    expect(find.text('ตั้งค่า'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('ส่งคลิปบอร์ด'), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-clipboard')));
    await tester.pump();
    expect(peer.sent, isEmpty);
    expect(find.text('ซิงก์คลิปบอร์ดปิดอยู่'), findsOneWidget);
  });

  test('settings survive a restart and a broken file gives defaults', () async {
    final dir = await Directory.systemTemp.createTemp('dc_settings_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/settings.json');
    expect((await MobileSettings.load(f)).syncEnabled, isTrue);
    await const MobileSettings(language: 'th', syncEnabled: false).save(f);
    final back = await MobileSettings.load(f);
    expect((back.language, back.syncEnabled), ('th', false));
    await f.writeAsString('{broken');
    expect((await MobileSettings.load(f)).language, 'en');
  });

  test('concurrent settings saves serialize without tmp leftovers', () async {
    final dir = await Directory.systemTemp.createTemp('dc_settings_race_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/settings.json');
    await Future.wait<void>([
      for (var i = 0; i < 12; i++)
        MobileSettings(language: i.isEven ? 'en' : 'th', syncEnabled: i.isEven)
            .save(f),
    ]);
    final back = await MobileSettings.load(f);
    expect((back.language, back.syncEnabled), ('th', false));
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  testWidgets('pair by IP + PIN with SAS, then send the clipboard',
      (tester) async {
    final peer = _FakePeer();
    await _app(tester, peer,
        received: const [(from: 'Office PC', text: 'hello', path: null)],
        clipboard: 'from phone');
    expect(find.text('No computer yet'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);

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
