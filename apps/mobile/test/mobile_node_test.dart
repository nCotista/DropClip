import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_mobile/src/mobile_node.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

/// A desktop as the phone sees it: pairing host, mTLS server and mesh.
Future<
    ({
      PairingHost pairing,
      PeerMesh mesh,
      int port,
      String id,
      TrustedDeviceStore store
    })> _desktop(Directory dir) async {
  final keys = InMemorySecureKeyStore();
  final ids = DeviceIdentityManager(
      storageDir: Directory('${dir.path}/d'), keyStore: keys);
  await ids.loadOrCreate(deviceName: 'Office PC', os: 'windows');
  final store = TrustedDeviceStore(
      storageDir: Directory('${dir.path}/dt'), keyStore: keys);
  late TlsTransportServer server;
  final pairing = PairingHost(
      engine: PairingEngine(hostIdentity: ids.identity, trustedStore: store),
      store: store,
      onPaired: (d) => server.addTrustedPeerCert(d.certPem!));
  final mesh = PeerMesh(
      identity: ids,
      store: store,
      hello: () => HelloPayload(
          deviceId: ids.identity.deviceId,
          name: 'Office PC',
          os: 'windows',
          tier: 1,
          appVersion: 't',
          capabilities: const [],
          tombstonesHash: '',
          tombstoneCount: 0));
  server = await TlsTransportServer.bindForIdentity(
      identity: ids,
      store: store,
      pinnedHandler: (_) => Response.notFound(null),
      pairingHandler: pairing.handler,
      webSocket: (r, fp) => unawaited(mesh.accept(r, fp)),
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0);
  addTearDown(() async {
    await mesh.close();
    await server.close(force: true);
  });
  return (
    pairing: pairing,
    mesh: mesh,
    port: server.port,
    id: ids.identity.deviceId,
    store: store
  );
}

void main() {
  test('phone pairs by IP + PIN, dials the desktop and syncs text both ways',
      () async {
    final dir = await Directory.systemTemp.createTemp('dc_mobile_');
    addTearDown(() => dir.delete(recursive: true));
    final desk = await _desktop(dir);
    final written = StreamController<String>.broadcast();
    addTearDown(written.close);
    final phone = await MobileNode.start(
        dir: Directory('${dir.path}/phone'),
        keys: InMemorySecureKeyStore(),
        name: 'Pixel',
        os: 'android',
        writeClipboard: (t) async => written.add(t),
        onReceived: (_, __) {});
    addTearDown(phone.close);

    final pin = desk.pairing.open(ip: '127.0.0.1', port: desk.port).pin;
    desk.pairing.events.listen((e) {
      if (e is PairingSasReady) desk.pairing.confirm(true);
    });
    final linked = desk.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    final host =
        await phone.pair('127.0.0.1', desk.port, pin, (_, __) async => true);
    expect(host.name, 'Office PC');
    expect(phone.trusted.value.single.deviceId, desk.id);
    expect(
        await linked.timeout(const Duration(seconds: 5)), {phone.me.deviceId});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final atDesk = desk.mesh.messages.first;
    phone.sendText('from phone');
    final up = (await atDesk.timeout(const Duration(seconds: 5))).envelope;
    expect(utf8.decode(base64Decode(up.payload['inline'] as String)),
        'from phone');

    final raw = utf8.encode('from desktop');
    final toPhone = written.stream.first;
    await desk.mesh.broadcast(Envelope(
        type: MessageType.clipboardUpdate,
        msgId: '00000000-0000-4000-8000-0000000000aa',
        origin: desk.id,
        hlc: Hlc.now(desk.id),
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: ClipboardUpdatePayload(
                contentType: 'text/plain',
                hash: sha256.convert(raw).toString(),
                size: raw.length,
                isConcealed: false,
                inline: base64Encode(raw))
            .toJson()));
    expect(await toPhone.timeout(const Duration(seconds: 5)), 'from desktop');
  });

  test('phone pairs by scanning the QR; a revoke makes it forget the desktop',
      () async {
    final dir = await Directory.systemTemp.createTemp('dc_mobile_qr_');
    addTearDown(() => dir.delete(recursive: true));
    final desk = await _desktop(dir);
    final phone = await MobileNode.start(
        dir: Directory('${dir.path}/phone'),
        keys: InMemorySecureKeyStore(),
        name: 'Pixel',
        os: 'android',
        writeClipboard: (_) async {},
        onReceived: (_, __) {});
    addTearDown(phone.close);

    final qr = desk.pairing.open(ip: '127.0.0.1', port: desk.port).qr;
    desk.pairing.events.listen((e) {
      if (e is PairingSasReady) desk.pairing.confirm(true);
    });
    final linked = desk.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    await phone.pairWithQr(jsonEncode(qr.toJson()), (_, __) async => true);
    await linked.timeout(const Duration(seconds: 5));
    expect(phone.trusted.value.single.deviceId, desk.id);
    await expectLater(phone.pairWithQr('not a qr', (_, __) async => true),
        throwsA(isA<PairingClientException>()));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    await desk.mesh.broadcast(Envelope(
        type: MessageType.deviceRevoked,
        msgId: '00000000-0000-4000-8000-0000000000bb',
        origin: desk.id,
        hlc: Hlc.now(desk.id),
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: {'reason': 'user_initiated', 'by': desk.id}));
    for (var i = 0; i < 100 && phone.trusted.value.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(phone.trusted.value, isEmpty);
  });

  Future<MobileNode> phoneAt(Directory dir, String os) async {
    final phone = await MobileNode.start(
        dir: Directory('${dir.path}/phone'),
        keys: InMemorySecureKeyStore(),
        name: 'Test phone',
        os: os,
        writeClipboard: (_) async {},
        onReceived: (_, __) {});
    addTearDown(phone.close);
    return phone;
  }

  for (final os in ['ios', 'android']) {
    for (final mode in ['pin', 'qr']) {
      test('$os advertises its tier in hello and $mode pairing', () async {
        final dir = await Directory.systemTemp.createTemp('dc_tier_');
        addTearDown(() => dir.delete(recursive: true));
        final desk = await _desktop(dir);
        final phone = await phoneAt(dir, os);
        final expectedTier = os == 'ios' ? 3 : 2;
        expect(phone.hello.tier, expectedTier);
        expect(phone.hello.capabilities.contains('clip.push'), os == 'android');
        final session = desk.pairing.open(ip: '127.0.0.1', port: desk.port);
        final sub = desk.pairing.events.listen((e) {
          if (e is PairingSasReady) desk.pairing.confirm(true);
        });
        addTearDown(sub.cancel);
        final paired =
            desk.pairing.events.firstWhere((e) => e is PairingCompleted);
        if (mode == 'pin') {
          await phone.pair(
              '127.0.0.1', desk.port, session.pin, (_, __) async => true);
        } else {
          await phone.pairWithQr(
              jsonEncode(session.qr.toJson()), (_, __) async => true);
        }
        await paired;
        expect(desk.store.activeDevices.single.tier, expectedTier);
        expect(desk.store.activeDevices.single.os, os);
      });
    }
  }

  for (final failure in ['wrong PIN', 'malformed QR', 'wrong QR fingerprint']) {
    test('iOS $failure never creates trust', () async {
      final dir = await Directory.systemTemp.createTemp('dc_ios_reject_');
      addTearDown(() => dir.delete(recursive: true));
      final desk = await _desktop(dir);
      final phone = await phoneAt(dir, 'ios');
      final session = desk.pairing.open(ip: '127.0.0.1', port: desk.port);
      final sub = desk.pairing.events.listen((e) {
        if (e is PairingSasReady) desk.pairing.confirm(false);
      });
      addTearDown(sub.cancel);
      final Future<TrustedDevice> attempt;
      if (failure == 'wrong PIN') {
        final wrong = session.pin == '000000' ? '111111' : '000000';
        attempt =
            phone.pair('127.0.0.1', desk.port, wrong, (_, __) async => true);
      } else {
        final qr = session.qr.toJson();
        final fp = qr['fp'] as String;
        qr['fp'] = (fp[0] == 'a' ? 'b' : 'a') + fp.substring(1);
        attempt = phone.pairWithQr(
            failure == 'malformed QR' ? 'not a qr' : jsonEncode(qr),
            (_, __) async => true);
      }
      await expectLater(attempt, throwsA(anything));
      expect(phone.trusted.value, isEmpty);
      expect(desk.store.activeDevices, isEmpty);
      expect(phone.hello.tier, 3);
      expect(phone.hello.capabilities, isNot(contains('clip.push')));
    });
  }
}
