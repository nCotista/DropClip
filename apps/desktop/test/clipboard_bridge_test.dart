import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/node/desktop_node.dart';
import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:dropclip_desktop/src/sync/clipboard_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OS clipboard of one fake device.
class _FakeOs implements PlatformClipboard {
  final changes = StreamController<ClipSnapshot>.broadcast();
  List<ClipboardItem>? items;
  final writes = StreamController<List<ClipboardItem>>.broadcast();
  int _token = 0;

  void copy(List<ClipboardItem> next) {
    items = next;
    changes.add(ClipSnapshot(
        changeToken: ++_token, isConcealed: false, items: next, ts: 0));
  }

  @override
  Future<int> write(List<ClipboardItem> next) async {
    items = next;
    writes.add(next);
    return ++_token;
  }

  @override
  Future<List<ClipboardItem>?> read() async => items;
  @override
  Future<void> clear() async => items = null;
  @override
  int changeToken() => _token;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

typedef _Device = ({
  DesktopNode node,
  _FakeOs os,
  ClipboardBridge bridge,
  List<ClipEvent> shown,
});

Future<_Device> _device(String name) async {
  final shown = <ClipEvent>[];
  final dir = await Directory.systemTemp.createTemp('dc_clip_');
  final node = await DesktopNode.start(
      dir: dir,
      keys: InMemorySecureKeyStore(),
      name: name,
      os: DeviceOs.windows);
  final os = _FakeOs();
  final bridge = ClipboardBridge(
      node: node,
      native: os,
      changes: os.changes.stream,
      windows: true,
      onClip: shown.add,
      policy: () => const SyncPolicy());
  await bridge.start();
  addTearDown(() async {
    await bridge.stop();
    await node.close();
    await dir.delete(recursive: true).catchError((Object _) => dir);
  });
  return (node: node, os: os, bridge: bridge, shown: shown);
}

DiscoveredPeer _seen(DesktopNode n, [PeerTrust trust = PeerTrust.trusted]) =>
    DiscoveredPeer(
        record: n.record,
        address: '127.0.0.1',
        lastSeen: DateTime.now(),
        state: PeerState.discovered,
        trust: trust);

void main() {
  test('one copy reported 3 times shows once; copy again writes natively',
      () async {
    final d = await _device('A');
    for (var i = 0; i < 3; i++) {
      d.os.copy([ClipboardItem(mime: 'text/plain', data: utf8.encode('same'))]);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(d.shown.map((e) => e.preview), ['same']);

    final written = d.os.writes.stream.first;
    await d.bridge.copyAgain(ClipType.url, 'https://dropclip.dev');
    expect((await written).map((i) => i.mime), ['text/plain', 'text/uri-list']);
  });

  test('Settings decide what syncs and for how long (FR-05)', () {
    final p = syncPolicyFor(const AppConfig(
        deviceName: 'PC', syncTypes: {SyncType.text}, clipboardTtlSeconds: 60));
    expect(p.allows(ClipType.text), isTrue);
    expect(p.allows(ClipType.image), isFalse);
    expect(p.ttlSeconds, 60);
    expect(
        syncPolicyFor(
                const AppConfig(deviceName: 'PC', clipboardSyncEnabled: false))
            .allows(ClipType.text),
        isFalse);
  });

  test('Windows DIB and macOS TIFF become PNG; text stays UTF-8', () {
    final png = encodePng(RgbaImage(
        2, 1, Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 255])));
    LocalClip? from(String mime, List<int> data) => localClipFrom(ClipSnapshot(
        changeToken: 1,
        isConcealed: false,
        items: [ClipboardItem(mime: mime, data: data)],
        ts: 0));
    expect(
        from('text/plain', utf8.encode('สวัสดี'))!.raw, utf8.encode('สวัสดี'));
    expect(decodePng(from('image/x-win-dibv5', pngToDibV5(png))!.raw).pixels,
        decodePng(png).pixels);
    expect(from('image/png', png)!.type, ClipType.image);
    expect(
        clipboardItemsFor(ClipType.image, png, windows: true)
            .map((i) => i.mime),
        ['image/png', 'image/x-win-dibv5']);
  });

  test('a copy on one paired PC lands on the other (text and image)', () async {
    final a = await _device('A'), b = await _device('B');
    final session = await a.node.openPairing();
    a.node.pairing.events.listen((e) {
      if (e is PairingSasReady) a.node.pairing.confirm(true);
    });
    final aSeesB =
        a.node.pairing.events.firstWhere((e) => e is PairingCompleted);
    await b.node.pairWith(
        _seen(a.node, PeerTrust.untrusted), session.pin, (_, __) async => true);
    await aSeesB;
    final linked = a.node.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    a.node.onPeers([_seen(b.node)]);
    b.node.onPeers([_seen(a.node)]);
    await linked.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final text = b.os.writes.stream.first;
    a.os.copy([ClipboardItem(mime: 'text/plain', data: utf8.encode('hello'))]);
    expect(
        utf8.decode(
            (await text.timeout(const Duration(seconds: 5))).single.data),
        'hello');

    final rng = Random(7);
    // > 32 KiB, so it travels as a blob over pinned GET /api/v1/blob (§9.3).
    final big = encodePng(RgbaImage(
        200,
        200,
        Uint8List.fromList(
            List<int>.generate(160000, (_) => rng.nextInt(256)))));
    expect(big.length, greaterThan(32 * 1024));
    final image = a.os.writes.stream.first;
    b.os.copy([ClipboardItem(mime: 'image/png', data: big)]);
    final got = await image.timeout(const Duration(seconds: 5));
    expect(got.first.data, big);
    expect(got.map((i) => i.mime), contains('image/x-win-dibv5'));
  });
}
