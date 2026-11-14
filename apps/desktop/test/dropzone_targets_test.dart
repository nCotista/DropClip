import 'dart:async';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_controller.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_host.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_targets.dart';
import 'package:dropclip_desktop/src/web/web_companion.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrustedDevice _peer(
  String id,
  String name, {
  String status = 'active',
  int tier = 1,
}) =>
    TrustedDevice(
      deviceId: id,
      name: name,
      os: tier == 3 ? 'ios' : 'android',
      tier: tier,
      fp: 'fp-$id',
      pairedAt: 1,
      lastSeenAt: 2,
      status: status,
    );

WebSession _session(String id, String name) {
  final now = DateTime.utc(2026, 1, 1);
  return WebSession(id, name, now, now.add(const Duration(hours: 1)), 0);
}

void main() {
  group('buildDropzoneTargets (T1.12)', () {
    test('includes connected paired peer missing from nearby discovery', () {
      const mac = NearbyDevice(
        'MacBook',
        'macOS · 2 ms',
        PeerReach.online,
        id: 'mac-1',
      );
      final res = buildDropzoneTargets(
        nearby: const [mac],
        trusted: [_peer('mac-1', 'MacBook'), _peer('phone-1', 'Pixel 8')],
        connected: const {'mac-1', 'phone-1'},
        sessions: const [],
      );

      expect(res, hasLength(2));
      expect(res[0], same(mac));
      expect(res[1].id, 'phone-1');
      expect(res[1].name, 'Pixel 8');
      expect(res[1].detail, 'Connected');
      expect(res[1].reach, PeerReach.online);
    });

    test('does not duplicate connected peers already in nearby list', () {
      const demo = NearbyDevice('Demo', 'Virtual', PeerReach.online);
      const stale = NearbyDevice(
        'iPhone 15',
        'iOS · Share Sheet',
        PeerReach.manual,
        id: 'ios-1',
      );
      final res = buildDropzoneTargets(
        nearby: const [demo, stale],
        trusted: [
          _peer('ios-1', 'iPhone 15', tier: 3),
          _peer('phone-1', 'Pixel 8'),
          _peer('phone-1', 'Pixel 8 Copy'),
        ],
        connected: const {'ios-1', 'phone-1'},
        sessions: const [],
      );

      final ids = [for (final d in res) d.id];
      expect(ids, [null, 'ios-1', 'phone-1']);
      expect(res[1].detail, 'iOS · Share Sheet');
      expect(res[2].name, 'Pixel 8');
    });

    test('excludes offline, untrusted, revoked, and quarantined peers', () {
      final res = buildDropzoneTargets(
        nearby: const [],
        trusted: [
          _peer('off-1', 'Offline Phone'),
          _peer('rev-1', 'Revoked', status: 'revoked'),
          _peer('quar-1', 'Quarantined', status: 'quarantined'),
        ],
        connected: const {'unknown-1', 'rev-1', 'quar-1'},
        sessions: const [],
      );

      expect(res, isEmpty);
    });

    test('appends linked browser sessions cleanly after device targets', () {
      const mac = NearbyDevice(
        'MacBook',
        'macOS · 2 ms',
        PeerReach.online,
        id: 'mac-1',
      );
      final res = buildDropzoneTargets(
        nearby: const [mac],
        trusted: [_peer('phone-1', 'Pixel 8')],
        connected: const {'phone-1'},
        sessions: [
          _session('s1', 'Chrome'),
          _session('s1', 'Chrome Dup'),
          _session('s2', 'Safari'),
        ],
      );

      final rows = [
        for (final d in res) (d.id, d.name, d.detail, d.reach),
      ];
      expect(rows, const [
        ('mac-1', 'MacBook', 'macOS · 2 ms', PeerReach.online),
        ('phone-1', 'Pixel 8', 'Connected', PeerReach.online),
        ('web:s1', 'Chrome', 'Browser', PeerReach.online),
        ('web:s2', 'Safari', 'Browser', PeerReach.online),
      ]);
    });
  });

  group('bindDropzoneTargets (T1.12)', () {
    test('syncs initially, reacts to updates, stops on dispose', () async {
      final targets = ValueNotifier<List<NearbyDevice>>(const []);
      final nearby = ValueNotifier<List<NearbyDevice>>(const []);
      final pixel = _peer('phone-1', 'Pixel 8');
      final trusted = ValueNotifier<List<TrustedDevice>>([pixel]);
      final sessions = ValueNotifier<List<WebSession>>(const []);
      final peerChanges = StreamController<Set<String>>.broadcast();
      var connected = <String>{'phone-1'};

      addTearDown(targets.dispose);
      addTearDown(nearby.dispose);
      addTearDown(trusted.dispose);
      addTearDown(sessions.dispose);
      addTearDown(peerChanges.close);

      final dispose = bindDropzoneTargets(
        targets: targets,
        nearby: nearby,
        trusted: trusted,
        connected: () => connected,
        peerChanges: peerChanges.stream,
        sessions: sessions,
      );

      expect([for (final d in targets.value) d.id], ['phone-1']);

      connected = const <String>{};
      peerChanges.add(connected);
      await Future<void>.delayed(Duration.zero);
      expect(targets.value, isEmpty);

      connected = const {'phone-1'};
      peerChanges.add(connected);
      await Future<void>.delayed(Duration.zero);
      expect([for (final d in targets.value) d.id], ['phone-1']);

      trusted.value = const [];
      expect(targets.value, isEmpty);

      sessions.value = [_session('b1', 'Mobile Safari')];
      expect([for (final d in targets.value) d.id], ['web:b1']);

      dispose();
      nearby.value = const [
        NearbyDevice('Late', 'mDNS', PeerReach.online, id: 'late-1'),
      ];
      peerChanges.add(const {'phone-1'});
      await Future<void>.delayed(Duration.zero);
      expect([for (final d in targets.value) d.id], ['web:b1']);
    });

    testWidgets('DropzoneHost renders connected peer', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dir = Directory.systemTemp.createTempSync('dz_targets_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sample = File('${dir.path}/note.txt')..writeAsStringSync('hi');

      final dz = DropzoneController();
      final targets = ValueNotifier<List<NearbyDevice>>(const []);
      final nearby = ValueNotifier<List<NearbyDevice>>(const []);
      final pixel = _peer('phone-1', 'Pixel 8');
      final trusted = ValueNotifier<List<TrustedDevice>>([pixel]);
      final sessions = ValueNotifier<List<WebSession>>(const []);
      final peerChanges = StreamController<Set<String>>.broadcast();
      var connected = const <String>{};

      addTearDown(dz.dispose);
      addTearDown(targets.dispose);
      addTearDown(nearby.dispose);
      addTearDown(trusted.dispose);
      addTearDown(sessions.dispose);
      addTearDown(peerChanges.close);

      final disposeBinding = bindDropzoneTargets(
        targets: targets,
        nearby: nearby,
        trusted: trusted,
        connected: () => connected,
        peerChanges: peerChanges.stream,
        sessions: sessions,
      );
      addTearDown(disposeBinding);

      final sent = <NearbyDevice>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildDropClipTheme(Brightness.dark),
        builder: (_, child) => DropzoneHost(
          controller: dz,
          devices: targets,
          nativeDrop: false,
          onSend: (to, _) => sent.add(to),
          child: child!,
        ),
        home: const Scaffold(body: Text('app')),
      ));

      final item = (name: 'note.txt', path: sample.path, isFolder: false);
      await tester.runAsync(() => dz.addDropped([item]));
      await tester.pump();
      expect(find.text('No devices nearby'), findsOneWidget);

      connected = const {'phone-1'};
      peerChanges.add(connected);
      await tester.pump();
      await tester.pump();

      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);

      await tester.tap(find.text('Send to Pixel 8'));
      expect(sent.single.id, 'phone-1');
      expect(tester.takeException(), isNull);
    });
  });
}
