import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_mobile/src/mobile_app.dart';
import 'package:dropclip_mobile/src/mobile_node.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shelf/shelf.dart';

class _ObservedPeer implements MobilePeer {
  final MobileNode node;
  final done = Completer<void>();
  bool started = false;
  _ObservedPeer(this.node);

  @override
  ValueListenable<List<TrustedDevice>> get trusted => node.trusted;
  @override
  Stream<Set<String>> get connectedChanges => node.connectedChanges;
  @override
  Set<String> get connected => node.connected;
  @override
  void sendText(String text) => node.sendText(text);
  @override
  Future<TrustedDevice> pair(String host, int port, String pin,
      Future<bool> Function(String, String) confirm) {
    started = true;
    return node.pair(host, port, pin, confirm).whenComplete(done.complete);
  }

  @override
  Future<TrustedDevice> pairWithQr(
          String qr, Future<bool> Function(String, String) confirm) =>
      node.pairWithQr(qr, confirm);
}

typedef _Fixture = ({
  _ObservedPeer peer,
  TrustedDeviceStore hostStore,
  Future<void> ready,
  Future<void> failed,
  Completer<void> release,
});

Future<void> _visible(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<_Fixture> _start(WidgetTester tester, String mode) async {
  final dir = await Directory.systemTemp.createTemp('dc_cancel_native_');
  final keys = InMemorySecureKeyStore();
  final identity = DeviceIdentityManager(
      storageDir: Directory('${dir.path}/host/id'), keyStore: keys);
  await identity.loadOrCreate(deviceName: 'Fixture desktop', os: 'macos');
  final store = TrustedDeviceStore(
      storageDir: Directory('${dir.path}/host/trust'), keyStore: keys);
  await store.load();
  final host = PairingHost(
      engine:
          PairingEngine(hostIdentity: identity.identity, trustedStore: store),
      store: store);
  final ready = Completer<void>(), failed = Completer<void>();
  final release = Completer<void>();
  final sub = host.events.listen((e) {
    if (e is PairingSasReady && !ready.isCompleted) ready.complete();
    if (e is PairingFailed && !failed.isCompleted) failed.complete();
  });
  final delayed = mode == 'late SAS' || mode == 'late network error';
  final server = await TlsTransportServer.bindForIdentity(
      identity: identity,
      store: store,
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0,
      pinnedHandler: (_) => Response.notFound('fixture'),
      pairingHandler: (request) async {
        final response = await host.handler(request);
        if (delayed && request.url.path == 'api/v1/pair/confirm') {
          await release.future;
          if (mode == 'late network error') {
            return Response(500,
                headers: {'content-type': 'application/json'},
                body: jsonEncode({
                  'error': {'code': 'E_INTERNAL', 'message': 'fixture failure'}
                }));
          }
        }
        return response;
      });
  final session = host.open(ip: '127.0.0.1', port: server.port);
  final node = await MobileNode.start(
      dir: Directory('${dir.path}/client'),
      keys: InMemorySecureKeyStore(),
      name: 'Fixture phone',
      os: 'ios',
      writeClipboard: (_) async {},
      onReceived: (_, __) {});
  final peer = _ObservedPeer(node);
  addTearDown(() async {
    if (!release.isCompleted) release.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await server.close(force: true);
    if (peer.started) {
      await peer.done.future.timeout(const Duration(seconds: 5));
    }
    await node.close();
    await sub.cancel();
    await host.close();
    await dir.delete(recursive: true);
  });
  await tester.pumpWidget(DropClipMobileApp(
      node: peer,
      received: ValueNotifier(const <String>[]),
      readClipboard: () async => null));
  await tester.tap(find.byKey(const Key('pair')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('host')), '127.0.0.1');
  await tester.enterText(find.byType(TextField).at(1), '${server.port}');
  await tester.enterText(find.byKey(const Key('pin')), session.pin);
  await tester.tap(find.byKey(const Key('go')));
  await tester.pump();
  return (
    peer: peer,
    hostStore: store,
    ready: ready.future,
    failed: failed.future,
    release: release
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in [
    'Does not match',
    'dismiss SAS',
    'late SAS',
    'late network error',
  ]) {
    testWidgets('native TLS pairing: $mode', (tester) async {
      final f = await _start(tester, mode);
      if (mode.startsWith('late')) {
        await f.ready.timeout(const Duration(seconds: 10));
        expect(find.byKey(const Key('sas')), findsNothing);
      } else {
        await _visible(tester, find.byKey(const Key('sas')));
      }
      if (mode == 'Does not match') {
        await tester.tap(find.text("Doesn't match"));
      } else {
        final barrier = tester.getRect(find.byType(ModalBarrier).last);
        await tester.tapAt(barrier.centerLeft + const Offset(8, 0));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
      if (!f.release.isCompleted) f.release.complete();
      await f.peer.done.future.timeout(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      if (mode != 'late network error') {
        await f.failed.timeout(const Duration(seconds: 5));
      }
      await f.hostStore.load();
      await f.peer.node.store.load();
      expect(f.hostStore.activeDevices, isEmpty);
      expect(f.peer.node.store.activeDevices, isEmpty);
      expect(tester.takeException(), isNull);
      if (mode == 'Does not match') {
        expect(find.textContaining('Pairing failed:'), findsOneWidget);
      }
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
}
