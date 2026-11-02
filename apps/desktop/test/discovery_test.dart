import 'dart:async';
import 'dart:math';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/app.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/discovery/discovery_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _fp = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

class _FakeBackend implements MdnsBackend {
  final events = StreamController<MdnsEvent>.broadcast();

  @override
  Future<void> register({
    required String serviceType,
    required String instanceName,
    required int port,
    required Map<String, String> txt,
  }) async {}

  @override
  Future<void> unregister() async {}

  @override
  Stream<MdnsEvent> browse(String serviceType) => events.stream;

  @override
  Future<void> query() async {}

  @override
  Stream<void> get networkChanges => const Stream.empty();

  Future<void> close() => events.close();
}

DiscoveredPeer _peer(DeviceOs os,
        {PeerState state = PeerState.discovered,
        PeerTrust trust = PeerTrust.untrusted}) =>
    DiscoveredPeer(
      record: DiscoveryRecord(
          deviceId: newDeviceId(Random(1)),
          name: 'โน้ตบุ๊ก',
          os: os,
          port: 53317,
          fingerprint: _fp),
      address: '10.0.0.7',
      lastSeen: DateTime(2026),
      state: state,
      trust: trust,
    );

void main() {
  group('local identity placeholders (T1.1 until T1.2/T1.4)', () {
    test('device ids are valid, distinct UUID v4', () {
      final ids = {for (var i = 0; i < 50; i++) newDeviceId()};
      expect(ids, hasLength(50));
      for (final id in ids) {
        expect(
            id,
            matches(RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      }
    });

    test('placeholder record survives the TXT round trip (§3.2)', () {
      final local =
          placeholderLocalRecord(name: 'DESKTOP-ไทย 💻', os: DeviceOs.windows);
      final parsed = DiscoveryRecord.tryParse(local.toTxt())!;
      expect(parsed.deviceId, local.deviceId);
      expect(parsed.name, 'DESKTOP-ไทย 💻');
      expect(parsed.port, inInclusiveRange(53317, 53417));
      expect(parsed.fingerprint, hasLength(64));
    });
  });

  group('nearbyDeviceFor', () {
    test('shows OS, address and pairing state', () {
      final d = nearbyDeviceFor(_peer(DeviceOs.windows));
      expect(d.name, 'โน้ตบุ๊ก');
      expect(d.detail, 'Windows · 10.0.0.7 · ready to pair');
      expect(d.reach, PeerReach.online);
    });

    test('trusted peers have no note; changed identity is flagged', () {
      expect(
          nearbyDeviceFor(_peer(DeviceOs.macos,
                  state: PeerState.trustedOnline, trust: PeerTrust.trusted))
              .detail,
          'macOS · 10.0.0.7');
      expect(
          nearbyDeviceFor(
                  _peer(DeviceOs.android, trust: PeerTrust.identityChanged))
              .detail,
          contains('identity changed'));
    });

    test('stale peers and Tier 3 (iOS) show as manual', () {
      expect(
          nearbyDeviceFor(_peer(DeviceOs.android, state: PeerState.stale))
              .reach,
          PeerReach.manual);
      expect(nearbyDeviceFor(_peer(DeviceOs.ios)).reach, PeerReach.manual);
    });
  });

  group('DiscoveryController', () {
    test('publishes peers once per real change', () async {
      final backend = _FakeBackend();
      addTearDown(backend.close);
      final local = placeholderLocalRecord(name: 'me', os: DeviceOs.windows);
      final controller = DiscoveryController(
        backend: backend,
        cache: PeerCache(
            localDeviceId: local.deviceId, trustedFingerprint: (_) => null),
        local: local,
      );
      var updates = 0;
      controller.nearby.addListener(() => updates++);
      await controller.start();

      final peer = placeholderLocalRecord(name: 'peer', os: DeviceOs.macos);
      final event = MdnsResolved(peer.deviceId,
          address: '10.0.0.9', srvPort: 53317, txt: peer.toTxt());
      for (var i = 0; i < 5; i++) {
        backend.events.add(event); // one report per adapter on Windows
      }
      await pumpEventQueue();
      expect(updates, 1);
      expect(controller.nearby.value.single.detail, startsWith('macOS'));

      backend.events.add(MdnsLost(peer.deviceId));
      await pumpEventQueue();
      expect(updates, 2);
      expect(controller.nearby.value, isEmpty);
      await controller.stop();
    });
  });

  testWidgets('app rebuilds from live status', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final live = ValueNotifier(demoShellStatus.withNearby(const []));
    await tester.pumpWidget(DropClipDesktopApp(
        hiddenLaunch: false, status: live.value, liveStatus: live));
    expect(find.text('No devices nearby'), findsOneWidget);

    live.value = live.value.withNearby(const [
      NearbyDevice('Peer PC', 'Windows · 10.0.0.9', PeerReach.online)
    ]);
    await tester.pump();
    expect(find.text('Peer PC'), findsOneWidget);
    expect(find.text('1 online'), findsOneWidget);
  });
}
