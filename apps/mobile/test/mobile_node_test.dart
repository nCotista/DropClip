import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_mobile/src/mobile_node.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

const _badPng = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2];

typedef _Desktop = ({
  PairingHost pairing,
  PeerMesh mesh,
  int port,
  String id,
  TrustedDeviceStore store,
  Map<String, BytesBuilder> files,
  DeviceIdentityManager ids,
});

/// A desktop as the phone sees it: pairing host, mTLS server and mesh.
Future<_Desktop> _desktop(Directory dir,
    {String statusJson = '{"offset":0}'}) async {
  // A minimal desktop receiver: accepts every offer and keeps the bytes.
  final files = <String, BytesBuilder>{};
  Future<Response> fileRoute(Request r) async {
    final seg = r.url.pathSegments; // api v1 file <tid> <item|finish>[/status]
    if (seg.length == 6) return Response.ok(statusJson);
    if (seg[4] == 'finish') return Response.ok('{}');
    await for (final b in r.read()) {
      files.putIfAbsent(seg[3], BytesBuilder.new).add(b);
    }
    return Response.ok('{}');
  }

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
      pinnedHandler: (r) async => r.url.path.startsWith('api/v1/file/')
          ? await fileRoute(r)
          : r.url.path == 'api/v1/blob/img1'
              ? Response.ok(_png)
              : r.url.path == 'api/v1/blob/bad'
                  ? Response.ok(_badPng)
                  : Response.notFound(null),
      pairingHandler: pairing.handler,
      webSocket: (r, fp) => unawaited(mesh.accept(r, fp)),
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0);
  final offers = mesh.messages
      .where((m) => m.envelope.type == MessageType.fileOffer)
      .listen((m) => mesh.broadcast(
          Envelope(
              type: MessageType.fileAccept,
              msgId: '00000000-0000-4000-8000-0000000000cc',
              origin: ids.identity.deviceId,
              hlc: Hlc.now(ids.identity.deviceId),
              ts: DateTime.now().millisecondsSinceEpoch,
              payload: {
                'transfer_id': m.envelope.payload['transfer_id'],
                'accepted_items': ['i0'],
                'auto': true
              }),
          to: m.peerId));
  addTearDown(() async {
    await offers.cancel();
    await mesh.close();
    await server.close(force: true);
  });
  return (
    pairing: pairing,
    mesh: mesh,
    port: server.port,
    id: ids.identity.deviceId,
    store: store,
    files: files,
    ids: ids,
  );
}

/// A 1×1 PNG, as the desktop's blob store would serve a copied image.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

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

  test('the desktop sends a file to the phone, which saves it', () async {
    final dir = await Directory.systemTemp.createTemp('dc_mobile_recv_');
    addTearDown(() => dir.delete(recursive: true));
    final desk = await _desktop(dir);
    final got = StreamController<(File, String)>.broadcast();
    addTearDown(got.close);
    final phone = await MobileNode.start(
        dir: Directory('${dir.path}/phone'),
        keys: InMemorySecureKeyStore(),
        name: 'Pixel',
        os: 'android',
        writeClipboard: (_) async {},
        onReceived: (_, __) {},
        received: Directory('${dir.path}/Download'),
        onFile: (f, from) => got.add((f, from)));
    addTearDown(phone.close);
    final pin = desk.pairing.open(ip: '127.0.0.1', port: desk.port).pin;
    desk.pairing.events.listen((e) {
      if (e is PairingSasReady) desk.pairing.confirm(true);
    });
    final linked = desk.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    await phone.pair('127.0.0.1', desk.port, pin, (_, __) async => true);
    await linked.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // What the desktop's FileTransfers.send does, against the phone.
    final bytes = List<int>.generate(1500000, (i) => i % 253);
    final sha = sha256.convert(bytes).toString();
    const tid = '00000000-0000-4000-8000-0000000000f1';
    final accepted = desk.mesh.messages.firstWhere((m) =>
        m.envelope.type == MessageType.fileAccept &&
        m.envelope.payload['transfer_id'] == tid);
    await desk.mesh.broadcast(Envelope(
        type: MessageType.fileOffer,
        msgId: '00000000-0000-4000-8000-0000000000f2',
        origin: desk.id,
        hlc: Hlc.now(desk.id),
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'transfer_id': tid,
          'items': [
            FileOfferItem(
                    itemId: 'i0',
                    path: 'รายงาน 1.pdf',
                    size: bytes.length,
                    sha256: sha,
                    mime: 'application/pdf',
                    modifiedAt: 0)
                .toJson()
          ],
          'manifest': false,
          'total_size': bytes.length,
          'total_count': 1,
        }));
    await accepted.timeout(const Duration(seconds: 5));
    final client = await PinnedTransportClient.forIdentity(
        identity: desk.ids, store: desk.store, expectedFp: phone.me.fp);
    addTearDown(client.close);
    Future<HttpClientResponse> call(String method, String path,
        [List<int>? body]) async {
      final req = await client.httpClient.openUrl(
          method,
          Uri(
              scheme: 'https',
              host: '127.0.0.1',
              port: phone.server.port,
              path: path));
      if (body != null) req.add(body);
      return req.close();
    }

    final saved = got.stream.first;
    expect((await call('GET', '/api/v1/file/$tid/i0/status')).statusCode, 200);
    expect((await call('POST', '/api/v1/file/$tid/i0', bytes)).statusCode, 200);
    expect(
        (await call('POST', '/api/v1/file/$tid/finish', [])).statusCode, 200);
    final (file, from) = await saved.timeout(const Duration(seconds: 5));
    expect(from, 'Office PC');
    expect(file.uri.pathSegments.last, 'รายงาน 1.pdf');
    expect(await file.readAsBytes(), bytes);

    // An image copied on the desktop: the phone fetches the blob and saves it.
    final image = got.stream.first;
    await desk.mesh.broadcast(Envelope(
        type: MessageType.clipboardUpdate,
        msgId: '00000000-0000-4000-8000-0000000000f3',
        origin: desk.id,
        hlc: Hlc.now(desk.id),
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: ClipboardUpdatePayload(
                contentType: 'image/png',
                hash: sha256.convert(_png).toString(),
                size: _png.length,
                isConcealed: false,
                blobId: 'img1')
            .toJson()));
    final (png, imageFrom) = await image.timeout(const Duration(seconds: 5));
    expect(imageFrom, 'Office PC');
    expect(png.path, endsWith('.png'));
    expect(await png.readAsBytes(), _png);
  });

  test('phone sends a file to the desktop, then removes it', () async {
    final dir = await Directory.systemTemp.createTemp('dc_mobile_file_');
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
    final pin = desk.pairing.open(ip: '127.0.0.1', port: desk.port).pin;
    desk.pairing.events.listen((e) {
      if (e is PairingSasReady) desk.pairing.confirm(true);
    });
    final linked = desk.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    await phone.pair('127.0.0.1', desk.port, pin, (_, __) async => true);
    await linked.timeout(const Duration(seconds: 5));
    for (var i = 0; i < 100 && !phone.connected.contains(desk.id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final photo = File('${dir.path}/photo.jpg');
    await photo.writeAsBytes(List<int>.generate(300000, (i) => i % 251));
    final progress = <int>[];
    await phone.sendFile(desk.id, photo.path,
        onProgress: (sent, _) => progress.add(sent));
    expect(desk.files.values.single.toBytes(), await photo.readAsBytes());
    expect(progress.last, 300000);

    // Remove: the desktop is told (deviceRevoked) and the phone forgets it.
    final told = desk.mesh.messages
        .firstWhere((m) => m.envelope.type == MessageType.deviceRevoked);
    await phone.forget(desk.id);
    expect((await told.timeout(const Duration(seconds: 5))).peerId,
        phone.me.deviceId);
    expect(phone.trusted.value, isEmpty);
    expect(phone.connected, isEmpty);
    await expectLater(phone.sendFile(desk.id, photo.path), throwsStateError);
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

  test('a corrupt hosts.json is ignored instead of crashing startup', () async {
    final dir = await Directory.systemTemp.createTemp('dc_hosts_');
    addTearDown(() => dir.delete(recursive: true));
    final base = Directory('${dir.path}/phone');
    await base.create(recursive: true);
    await File('${base.path}/hosts.json').writeAsString('{"broken":');

    final phone = await phoneAt(dir, 'android');
    await expectLater(phone.reconnect(), completes);
    expect(File('${base.path}/hosts.json.corrupt').existsSync(), isTrue);
  });

  Future<({MobileNode phone, _Desktop desk, Directory phoneDir})> pairedPair(
    Directory dir, {
    String statusJson = '{"offset":0}',
    void Function(String text, String from)? onReceived,
    void Function(File file, String from)? onFile,
  }) async {
    final desk = await _desktop(dir, statusJson: statusJson);
    final phoneDir = Directory('${dir.path}/phone');
    final phone = await MobileNode.start(
        dir: phoneDir,
        keys: InMemorySecureKeyStore(),
        name: 'Pixel',
        os: 'android',
        writeClipboard: (_) async {},
        onReceived: onReceived ?? (_, __) {},
        onFile: onFile);
    addTearDown(phone.close);
    final pin = desk.pairing.open(ip: '127.0.0.1', port: desk.port).pin;
    final sasSub = desk.pairing.events.listen((e) {
      if (e is PairingSasReady) desk.pairing.confirm(true);
    });
    addTearDown(sasSub.cancel);
    final linked = desk.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    await phone.pair('127.0.0.1', desk.port, pin, (_, __) async => true);
    await linked.timeout(const Duration(seconds: 5));
    for (var i = 0; i < 100 && !phone.connected.contains(desk.id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return (phone: phone, desk: desk, phoneDir: phoneDir);
  }

  test('sendFile skips upload POST when server reports complete', () async {
    final dir = await Directory.systemTemp.createTemp('dc_send_done_');
    addTearDown(() => dir.delete(recursive: true));
    final pair = await pairedPair(dir, statusJson: '{"state":"complete"}');
    final f = File('${dir.path}/doc.bin');
    await f.writeAsBytes(const [1, 2, 3, 4, 5]);
    final progress = <int>[];
    await pair.phone.sendFile(pair.desk.id, f.path,
        onProgress: (sent, _) => progress.add(sent));
    expect(pair.desk.files, isEmpty);
    expect(progress, [5]);
  });

  for (final badOffset in [-1, 99]) {
    test('sendFile rejects invalid server offset $badOffset', () async {
      final dir = await Directory.systemTemp.createTemp('dc_bad_off_');
      addTearDown(() => dir.delete(recursive: true));
      final pair = await pairedPair(dir, statusJson: '{"offset":$badOffset}');
      final f = File('${dir.path}/doc.bin');
      await f.writeAsBytes(const [1, 2, 3, 4, 5]);
      final err = isA<ProtocolException>()
          .having((e) => e.errorCode, 'code', ProtocolErrorCode.internal);
      await expectLater(
          pair.phone.sendFile(pair.desk.id, f.path), throwsA(err));
      expect(pair.desk.files, isEmpty);
    });
  }

  test('receiver rejects bad offer, bad x-offset, and un-uploaded finish',
      () async {
    final dir = await Directory.systemTemp.createTemp('dc_recv_neg_');
    addTearDown(() => dir.delete(recursive: true));
    final pair = await pairedPair(dir);
    final rejected = pair.desk.mesh.messages
        .firstWhere((m) => m.envelope.type == MessageType.fileReject);
    await pair.desk.mesh.broadcast(Envelope(
        type: MessageType.fileOffer,
        msgId: '00000000-0000-4000-8000-0000000000e1',
        origin: pair.desk.id,
        hlc: Hlc.now(pair.desk.id),
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: const <String, dynamic>{}));
    final rej = await rejected.timeout(const Duration(seconds: 5));
    expect(rej.envelope.type, MessageType.fileReject);

    const tid = '00000000-0000-4000-8000-0000000000e2';
    final accepted = pair.desk.mesh.messages.firstWhere((m) =>
        m.envelope.type == MessageType.fileAccept &&
        m.envelope.payload['transfer_id'] == tid);
    final emptySha = sha256.convert(const <int>[]).toString();
    final emptyItem = FileOfferItem(
        itemId: 'i0',
        path: 'empty.txt',
        size: 0,
        sha256: emptySha,
        mime: 'text/plain',
        modifiedAt: 0);
    await pair.desk.mesh.broadcast(Envelope(
        type: MessageType.fileOffer,
        msgId: '00000000-0000-4000-8000-0000000000e3',
        origin: pair.desk.id,
        hlc: Hlc.now(pair.desk.id),
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'transfer_id': tid,
          'items': [emptyItem.toJson()],
          'manifest': false,
          'total_size': 0,
          'total_count': 1,
        }));
    await accepted.timeout(const Duration(seconds: 5));

    final client = await PinnedTransportClient.forIdentity(
        identity: pair.desk.ids,
        store: pair.desk.store,
        expectedFp: pair.phone.me.fp);
    addTearDown(client.close);
    Future<HttpClientResponse> sendReq(String path, [String? offset]) async {
      final req = await client.httpClient.postUrl(Uri(
          scheme: 'https',
          host: '127.0.0.1',
          port: pair.phone.server.port,
          path: path));
      if (offset != null) req.headers.set('x-offset', offset);
      return req.close();
    }

    final badOffRes = await sendReq('/api/v1/file/$tid/i0', '-1');
    expect(badOffRes.statusCode, 409);
    await badOffRes.drain<void>();

    final failed = pair.desk.mesh.messages.firstWhere((m) =>
        m.envelope.type == MessageType.fileComplete &&
        m.envelope.payload['transfer_id'] == tid);
    final finishRes = await sendReq('/api/v1/file/$tid/finish');
    expect(finishRes.statusCode, 409);
    await finishRes.drain<void>();
    final doneMsg = await failed.timeout(const Duration(seconds: 5));
    expect(doneMsg.envelope.payload['state'], 'failed');
    expect(doneMsg.envelope.payload['code'], 'E_INCOMPLETE');
  });

  test('corrupt PNG clipboard update does not write an image file', () async {
    final dir = await Directory.systemTemp.createTemp('dc_bad_png_');
    addTearDown(() => dir.delete(recursive: true));
    final saved = <File>[];
    final gotText = StreamController<String>.broadcast();
    addTearDown(gotText.close);
    final pair = await pairedPair(dir,
        onReceived: (t, _) => gotText.add(t),
        onFile: (f, _) => saved.add(f));
    final now = DateTime.now().millisecondsSinceEpoch;
    await pair.desk.mesh.broadcast(Envelope(
        type: MessageType.clipboardUpdate,
        msgId: '00000000-0000-4000-8000-0000000000e4',
        origin: pair.desk.id,
        hlc: Hlc(l: now, c: 0, d: pair.desk.id),
        ts: now,
        payload: ClipboardUpdatePayload(
                contentType: 'image/png',
                hash: sha256.convert(_badPng).toString(),
                size: _badPng.length,
                isConcealed: false,
                blobId: 'bad')
            .toJson()));
    final okText = utf8.encode('after-bad');
    await pair.desk.mesh.broadcast(Envelope(
        type: MessageType.clipboardUpdate,
        msgId: '00000000-0000-4000-8000-0000000000e5',
        origin: pair.desk.id,
        hlc: Hlc(l: now + 100, c: 0, d: pair.desk.id),
        ts: now + 100,
        payload: ClipboardUpdatePayload(
                contentType: 'text/plain',
                hash: sha256.convert(okText).toString(),
                size: okText.length,
                isConcealed: false,
                inline: base64Encode(okText))
            .toJson()));
    final msg = await gotText.stream.first.timeout(const Duration(seconds: 5));
    expect(msg, 'after-bad');
    expect(saved, isEmpty);
    expect(Directory('${pair.phoneDir.path}/received').existsSync(), isFalse);
  });

  test('offline forget clears hosts.json atomically and reconnect completes',
      () async {
    final dir = await Directory.systemTemp.createTemp('dc_offline_forget_');
    addTearDown(() => dir.delete(recursive: true));
    final pair = await pairedPair(dir);
    final hostsFile = File('${pair.phoneDir.path}/hosts.json');
    expect(hostsFile.existsSync(), isTrue);

    await pair.phone.mesh.drop(pair.desk.id, 1000);
    for (var i = 0; i < 100 && pair.phone.connected.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await pair.phone.forget(pair.desk.id);
    expect(pair.phone.trusted.value, isEmpty);
    expect(jsonDecode(await hostsFile.readAsString()), isEmpty);
    expect(File('${hostsFile.path}.tmp').existsSync(), isFalse);
    await expectLater(pair.phone.reconnect(), completes);
  });
}
