import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/node/desktop_node.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DesktopNode> _node(String name) async {
  final dir = await Directory.systemTemp.createTemp('dc_revoke_');
  final n = await DesktopNode.start(
      dir: dir,
      keys: InMemorySecureKeyStore(),
      name: name,
      os: DeviceOs.windows);
  addTearDown(() async {
    await n.close();
    await dir.delete(recursive: true).catchError((Object _) => dir);
  });
  return n;
}

DiscoveredPeer _seen(DesktopNode n, PeerTrust t) => DiscoveredPeer(
    record: n.record,
    address: '127.0.0.1',
    lastSeen: DateTime.now(),
    state: PeerState.discovered,
    trust: t);

Future<void> _pair(DesktopNode host, DesktopNode client) async {
  final s = await host.openPairing();
  final sub = host.pairing.events.listen((e) {
    if (e is PairingSasReady) host.pairing.confirm(true);
  });
  final done = host.pairing.events.firstWhere((e) => e is PairingCompleted);
  await client.pairWith(
      _seen(host, PeerTrust.untrusted), s.pin, (_, __) async => true);
  await done;
  await sub.cancel();
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 100 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(ok(), isTrue);
}

void main() {
  test('removing a device revokes it everywhere (T1.13, §13)', () async {
    final a = await _node('A'), b = await _node('B'), c = await _node('C');
    await _pair(a, b);
    await _pair(a, c);
    await _pair(b, c);
    final all = [a, b, c];
    for (final n in all) {
      n.onPeers([
        for (final o in all)
          if (o != n) _seen(o, PeerTrust.trusted)
      ]);
    }
    await _until(() => all.every((n) => n.mesh.connected.length == 2));

    await a.forget(c.me.deviceId);
    expect(a.trusted.value.map((d) => d.name), ['B']);
    // C was told directly and forgets A too.
    await _until(() => c.trusted.value.every((d) => d.name != 'A'));
    // B got A's signed cluster.revocation: C waits for B's user.
    await _until(() => b.quarantined.value.any((d) => d.name == 'C'));
    expect(b.trusted.value.map((d) => d.name), ['A']);

    await b.settleQuarantine(c.me.deviceId, remove: true);
    expect(b.quarantined.value, isEmpty);
    expect(b.trusted.value.map((d) => d.name), ['A']);
    expect(a.revocation.isTombstoned(c.me.deviceId), isTrue);
  });

  test(
      'a device that was offline learns of a removal when it reconnects '
      '(§13.2.6)', () async {
    final a = await _node('A'), b = await _node('B'), c = await _node('C');
    await _pair(a, b);
    await _pair(a, c);
    await _pair(b, c);
    // C is switched off: only A and B are linked when A removes B.
    a.onPeers([_seen(b, PeerTrust.trusted)]);
    b.onPeers([_seen(a, PeerTrust.trusted)]);
    await _until(() => a.mesh.connected.length == 1);
    await a.forget(b.me.deviceId);
    expect(c.trusted.value.map((d) => d.name).toSet(), {'A', 'B'});

    // C comes back and meets A: the hello shows different tombstones, A
    // sends revocation.sync, and B now waits for C's user.
    a.onPeers([_seen(c, PeerTrust.trusted)]);
    c.onPeers([_seen(a, PeerTrust.trusted)]);
    await _until(() => c.quarantined.value.any((d) => d.name == 'B'));
    expect(c.trusted.value.map((d) => d.name), ['A']);
  });
}
