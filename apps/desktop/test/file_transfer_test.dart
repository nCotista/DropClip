import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/node/desktop_node.dart';
import 'package:dropclip_desktop/src/transfer/file_transfer.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Device = ({
  DesktopNode node,
  FileTransfers files,
  Directory dir,
  List<TransferUpdate> updates,
});

Future<_Device> _device(String name,
    {bool accept = true,
    Future<bool> Function()? decide,
    Duration offerTimeout = const Duration(seconds: 70),
    Duration stallTimeout = const Duration(seconds: 60)}) async {
  final dir = await Directory.systemTemp.createTemp('dc_files_');
  final node = await DesktopNode.start(
      dir: dir,
      keys: InMemorySecureKeyStore(),
      name: name,
      os: DeviceOs.windows);
  final updates = <TransferUpdate>[];
  final files = FileTransfers(
      node: node,
      downloads: Directory('${dir.path}/Downloads'),
      decide: (_, __) => decide?.call() ?? Future.value(accept),
      onUpdate: updates.add,
      offerTimeout: offerTimeout,
      stallTimeout: stallTimeout);
  addTearDown(() async {
    await files.close();
    await node.close();
    await dir.delete(recursive: true).catchError((Object _) => dir);
  });
  return (node: node, files: files, dir: dir, updates: updates);
}

DiscoveredPeer _seen(DesktopNode n, PeerTrust trust) => DiscoveredPeer(
    record: n.record,
    address: '127.0.0.1',
    lastSeen: DateTime.now(),
    state: PeerState.discovered,
    trust: trust);

Future<void> _pairAndLink(DesktopNode a, DesktopNode b) async {
  final session = await a.openPairing();
  a.pairing.events.listen((e) {
    if (e is PairingSasReady) a.pairing.confirm(true);
  });
  final done = a.pairing.events.firstWhere((e) => e is PairingCompleted);
  await b.pairWith(
      _seen(a, PeerTrust.untrusted), session.pin, (_, __) async => true);
  await done;
  final up = a.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
  a.onPeers([_seen(b, PeerTrust.trusted)]);
  b.onPeers([_seen(a, PeerTrust.trusted)]);
  await up.timeout(const Duration(seconds: 5));
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

Future<File> _file(Directory dir, String name, int size) async {
  final rng = Random(size);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(
      Uint8List.fromList(List<int>.generate(size, (_) => rng.nextInt(256))));
  return f;
}

void main() {
  test('files stream to the paired PC and arrive intact (FR-07/08)', () async {
    final a = await _device('A'), b = await _device('B');
    await _pairAndLink(a.node, b.node);
    final big = await _file(a.dir, 'video.mp4', 2500000);
    final small = await _file(a.dir, 'notes.txt', 300);

    await a.files.send(b.node.me.deviceId, 'B', [big, small]).timeout(
        const Duration(seconds: 20));

    for (final f in [big, small]) {
      final got = File('${b.dir.path}/Downloads/${f.uri.pathSegments.last}');
      expect(await computeFileSha256(got), await computeFileSha256(f));
    }
    expect(a.updates.last.state, 'complete');
    expect(a.updates.last.done, 2500300);
    // The receiving PC shows it arriving and finishing, not a row stuck at 0.
    expect(b.updates.every((u) => u.incoming), isTrue);
    expect(b.updates.first.state, 'in_progress');
    expect(
        b.updates.map((u) => u.done).any((d) => d > 0 && d < 2500300), isTrue);
    expect(b.updates.last.state, 'complete');
    expect(b.updates.last.done, 2500300);
  });

  test('sending to a device that is not connected fails at once', () async {
    final a = await _device('A');
    await expectLater(
        a.files.send('00000000-0000-4000-8000-000000000000', 'Ghost', [
          await _file(a.dir, 'x.bin', 10)
        ]).timeout(const Duration(seconds: 2)),
        throwsStateError);
    expect(a.updates.last.state, 'failed');
  });

  test('no answer to the offer ends as failed, not in progress forever',
      () async {
    final a =
            await _device('A', offerTimeout: const Duration(milliseconds: 300)),
        b = await _device('B', decide: () => Completer<bool>().future);
    await _pairAndLink(a.node, b.node);
    await expectLater(
        a.files
            .send(b.node.me.deviceId, 'B', [await _file(a.dir, 'x.bin', 10)]),
        throwsA(isA<TimeoutException>()));
    expect(a.updates.first.state, 'in_progress');
    expect(a.updates.last.state, 'failed');
  });

  test('a received file never replaces one with the same name', () async {
    final a = await _device('A'), b = await _device('B');
    await _pairAndLink(a.node, b.node);
    final mine = File('${b.dir.path}/Downloads/notes.txt');
    await mine.create(recursive: true);
    await mine.writeAsString('my own notes');
    final sent = await _file(a.dir, 'notes.txt', 300);

    await a.files.send(b.node.me.deviceId, 'B', [sent]);

    expect(await mine.readAsString(), 'my own notes');
    expect(
        await computeFileSha256(File('${b.dir.path}/Downloads/notes (1).txt')),
        await computeFileSha256(sent));
  });

  test('an empty file arrives too', () async {
    final a = await _device('A'), b = await _device('B');
    await _pairAndLink(a.node, b.node);
    await a.files
        .send(b.node.me.deviceId, 'B', [await _file(a.dir, 'empty.txt', 0)]);
    final got = File('${b.dir.path}/Downloads/empty.txt');
    expect(got.existsSync(), isTrue);
    expect(got.lengthSync(), 0);
    expect(a.updates.last.state, 'complete');
  });

  test('an accepted transfer whose sender goes quiet is shown as failed',
      () async {
    final a = await _device('A'),
        b = await _device('B', stallTimeout: const Duration(milliseconds: 300));
    await _pairAndLink(a.node, b.node);
    // An offer with no upload behind it.
    final me = a.node.me.deviceId;
    await a.node.mesh.broadcast(
        Envelope(
            type: MessageType.fileOffer,
            msgId: '00000000-0000-4000-8000-0000000000f1',
            origin: me,
            hlc: Hlc.now(me),
            ts: DateTime.now().millisecondsSinceEpoch,
            payload: {
              'transfer_id': '00000000-0000-4000-8000-0000000000f2',
              'items': [
                FileOfferItem(
                        itemId: 'i0',
                        path: 'never.bin',
                        size: 10,
                        sha256: '00',
                        mime: 'application/octet-stream',
                        modifiedAt: 0)
                    .toJson()
              ],
              'manifest': false,
              'total_size': 10,
              'total_count': 1,
            }),
        to: b.node.me.deviceId);
    for (var i = 0; i < 100 && b.updates.lastOrNull?.state != 'failed'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(b.updates.map((u) => u.state), ['in_progress', 'failed']);
  });

  test('a declined offer sends nothing', () async {
    final a = await _device('A'), b = await _device('B', accept: false);
    await _pairAndLink(a.node, b.node);
    await a.files
        .send(b.node.me.deviceId, 'B', [await _file(a.dir, 'x.bin', 10)]);
    expect(a.updates.last.state, 'rejected');
    expect(Directory('${b.dir.path}/Downloads').existsSync(), isFalse);
  });
}
