import 'dart:async';
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

  group('network adapter pick (T1.1)', () {
    ({String name, InternetAddress address}) nic(String n, String ip) =>
        (name: n, address: InternetAddress(ip));

    test('does not depend on the order the OS lists adapters in', () {
      // The same PC, enumerated two ways: a virtual LAN must never win just
      // because it came first (the 1.0.6 bug: the QR address changed between
      // launches).
      final set = [
        nic('Wi-Fi', '10.201.250.85'),
        nic('Microsoft Wi-Fi Direct Virtual Adapter', '192.168.137.1'),
        nic('vEthernet (Default Switch)', '172.28.0.1'),
      ];
      final reversed = set.reversed.toList();
      expect(pickLanAddress(set), '10.201.250.85');
      expect(pickLanAddress(reversed), '10.201.250.85');
    });

    test('a VPN or third-party virtual LAN loses to the real adapter', () {
      for (final name in [
        'Radmin VPN',
        'Hamachi',
        'NordLynx',
        'ZeroTier One [8056c2e21c000001]',
        'Tailscale',
        'OpenVPN Data Channel Offload',
        'Ethernet 2', // an unlisted virtual switch on 10.10.10.1
      ]) {
        expect(
            pickLanAddress([
              nic(name, '10.10.10.1'),
              nic('Ethernet', '192.168.1.20'),
            ]),
            '192.168.1.20',
            reason: '$name must not be picked over Ethernet');
      }
    });

    test('a real LAN on a container subnet still beats a virtual adapter', () {
      expect(
          pickLanAddress([
            nic('vEthernet (WSL)', '172.29.0.1'),
            nic('Ethernet', '172.20.10.5'),
          ]),
          '172.20.10.5');
    });

    test('falls back to a virtual adapter when nothing else has an address',
        () {
      expect(
          pickLanAddress([
            nic('vEthernet (Default Switch)', '172.28.0.1'),
          ]),
          '172.28.0.1');
    });

    test('a virtual adapter never scores below the real-connection band', () {
      for (final name in [
        'vEthernet (Default Switch)',
        'Microsoft Wi-Fi Direct Virtual Adapter',
        'Hyper-V Virtual Ethernet Adapter',
        'Tailscale',
      ]) {
        expect(
            adapterScore(nic(name, '192.168.1.9')), greaterThanOrEqualTo(100),
            reason: '$name is not a real LAN adapter');
      }
      expect(adapterScore(nic('Wi-Fi', '10.201.250.85')), lessThan(100));
    });

    test('the Settings choice wins over the automatic pick', () {
      final set = [
        nic('Wi-Fi', '10.201.250.85'),
        nic('Ethernet', '192.168.1.20'),
      ];
      expect(chooseAdapter(set, 'Ethernet'),
          (name: 'Ethernet', address: '192.168.1.20'));
      // Unplugged or renamed: fall back instead of returning nothing.
      expect(chooseAdapter(set, 'Ethernet 7')?.address, '10.201.250.85');
      expect(chooseAdapter(set, ''), isNotNull);
      expect(chooseAdapter(const [], 'Wi-Fi'), isNull);
    });
  });

  test('a renamed PC keeps its identity; a paired peer shows the new name',
      () async {
    final host = await _node('Host'), client = await _node('Client');
    final session = await host.openPairing();
    host.pairing.events.listen((e) {
      if (e is PairingSasReady) host.pairing.confirm(true);
    });
    final done = host.pairing.events.firstWhere((e) => e is PairingCompleted);
    await client.pairWith(
        _seen(host, PeerTrust.untrusted), session.pin, (_, __) async => true);
    await done;
    final id = host.me.deviceId, fp = host.me.fp;

    await host.rename('  Office PC  ');
    expect(host.me.name, 'Office PC');
    expect((host.me.deviceId, host.me.fp), (id, fp));
    expect(host.record.name, 'Office PC');
    expect(client.trusted.value.single.name, 'Host');

    // The next connection's hello carries the new name.
    final up = host.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    client.onPeers([_seen(host, PeerTrust.trusted)]);
    host.onPeers([_seen(client, PeerTrust.trusted)]);
    await up.timeout(const Duration(seconds: 5));
    for (var i = 0;
        i < 100 && client.trusted.value.single.name != 'Office PC';
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(client.trusted.value.single.name, 'Office PC');
    await expectLater(host.rename('   '), throwsArgumentError);
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

    // Revocation is asynchronous on the receiving peer. Wait for its store
    // write and disconnect before teardown deletes that peer's directory.
    final removed = Completer<void>();
    void onClientTrustChanged() {
      if (client.trusted.value.isEmpty && !removed.isCompleted) {
        removed.complete();
      }
    }

    client.trusted.addListener(onClientTrustChanged);
    addTearDown(() => client.trusted.removeListener(onClientTrustChanged));
    await host.forget(client.me.deviceId);
    await removed.future.timeout(const Duration(seconds: 5));
    expect(host.trusted.value, isEmpty);
    expect(client.trusted.value, isEmpty);
    expect(client.mesh.connected, isEmpty);

    // "Remove" then pairing again: the old revocation is lifted, so it is
    // not synced to other devices later (§13.2.6).
    expect(host.revocation.isTombstoned(client.me.deviceId), isTrue);
    final again = await host.openPairing();
    final repaired =
        host.pairing.events.firstWhere((e) => e is PairingCompleted);
    await client.pairWith(
        _seen(host, PeerTrust.untrusted), again.pin, (_, __) async => true);
    await repaired;
    for (var i = 0;
        i < 100 && host.revocation.isTombstoned(client.me.deviceId);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(host.revocation.isTombstoned(client.me.deviceId), isFalse);
  });

  test('images and files use the address of the live link', () async {
    final host = await _node('Host'), client = await _node('Client');
    final session = await host.openPairing();
    host.pairing.events.listen((e) {
      if (e is PairingSasReady) host.pairing.confirm(true);
    });
    final done = host.pairing.events.firstWhere((e) => e is PairingCompleted);
    await client.pairWith(
        _seen(host, PeerTrust.untrusted), session.pin, (_, __) async => true);
    await done;
    final (dialer, other) = host.me.deviceId.compareTo(client.me.deviceId) < 0
        ? (host, client)
        : (client, host);

    // Discovery told the side that was dialed a useless address for its
    // peer (another adapter); the link itself came from 127.0.0.1.
    final up = other.mesh.peerChanges.firstWhere((p) => p.isNotEmpty);
    other.onPeers([
      DiscoveredPeer(
          record: dialer.record,
          address: 'unreachable.invalid',
          lastSeen: DateTime.now(),
          state: PeerState.discovered,
          trust: PeerTrust.trusted)
    ]);
    dialer.onPeers([_seen(other, PeerTrust.trusted)]);
    await up.timeout(const Duration(seconds: 5));

    final info = await other
        .fetchFrom(dialer.me.deviceId, '/api/v1/info')
        .timeout(const Duration(seconds: 5));
    expect(String.fromCharCodes(info), contains(dialer.me.deviceId));
  });
}
