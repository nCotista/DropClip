import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/node/desktop_node.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DesktopNode> _node(String name) async {
  final dir = await Directory.systemTemp.createTemp('dc_node_');
  final node = await DesktopNode.start(
      dir: dir,
      keys: InMemorySecureKeyStore(),
      name: name,
      os: DeviceOs.windows);
  addTearDown(() async {
    await node.close();
    await dir.delete(recursive: true).catchError((Object _) => dir);
  });
  return node;
}

DiscoveredPeer _seen(DesktopNode n, PeerTrust trust) => DiscoveredPeer(
    record: n.record,
    address: '127.0.0.1',
    lastSeen: DateTime.now(),
    state: PeerState.discovered,
    trust: trust);

void main() {
  test('QR address skips virtual adapters and prefers Wi-Fi', () {
    ({String name, InternetAddress address}) nic(String n, String ip) =>
        (name: n, address: InternetAddress(ip));
    expect(
        pickLanAddress([
          nic('VirtualBox Host-Only Network', '192.168.56.1'),
          nic('vEthernet (WSL)', '172.20.0.1'),
          nic('Bluetooth Network', '10.0.0.9'),
          nic('Wi-Fi', '10.201.250.85'),
        ]),
        '10.201.250.85');
    // Windows names the VirtualBox adapter just "Ethernet 2".
    expect(
        pickLanAddress([
          nic('Ethernet 2', '192.168.56.1'),
          nic('Ethernet', '192.168.1.20'),
        ]),
        '192.168.1.20');
    expect(pickLanAddress([nic('Loopback', '127.0.0.1')]), '127.0.0.1');
  });

  test('identity, port and fingerprint survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('dc_node_');
    addTearDown(
        () => dir.delete(recursive: true).catchError((Object _) => dir));
    final keys = InMemorySecureKeyStore();
    Future<DesktopNode> boot() => DesktopNode.start(
        dir: dir, keys: keys, name: 'PC', os: DeviceOs.windows);
    final first = await boot();
    final id = first.record.deviceId, fp = first.record.fingerprint;
    expect(first.record.port, inInclusiveRange(53317, 53417));
    await first.close();
    final again = await boot();
    addTearDown(again.close);
    expect(again.record.deviceId, id);
    expect(again.record.fingerprint, fp);
  });

  test('pair with a PIN, then trusted peers link up from discovery', () async {
    final host = await _node('Host'), client = await _node('Client');
    final session = await host.openPairing();
    host.pairing.events.listen((e) {
      if (e is PairingSasReady) host.pairing.confirm(true);
    });

    final done = host.pairing.events.firstWhere((e) => e is PairingCompleted);
    final paired = await client.pairWith(
        _seen(host, PeerTrust.untrusted), session.pin, (_, __) async => true);
    expect(paired.deviceId, host.me.deviceId);
    expect(client.trusted.value.single.deviceId, host.me.deviceId);
    await done;
    expect(host.trusted.value.single.deviceId, client.me.deviceId);

    // Whoever §6.2 picks dials; the other ignores the event.
    final up = host.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    client.onPeers([_seen(host, PeerTrust.trusted)]);
    host.onPeers([_seen(client, PeerTrust.trusted)]);
    expect(await up.timeout(const Duration(seconds: 5)), {client.me.deviceId});

    await host.forget(client.me.deviceId);
    expect(host.trusted.value, isEmpty);
  });
}
