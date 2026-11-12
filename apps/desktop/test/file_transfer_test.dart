import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/node/desktop_node.dart';
import 'package:dropclip_desktop/src/transfer/file_transfer.dart';
import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Device = ({
  DesktopNode node,
  FileTransfers files,
  Directory dir,
  List<TransferUpdate> updates,
});

Future<_Device> _device(String name, {bool accept = true}) async {
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
      decide: (_, __) async => accept,
      onUpdate: updates.add);
  addTearDown(() async {
    await files.close();
    await node.close();
    await dir.delete(recursive: true);
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
    expect(b.updates.single.incoming, isTrue);
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
