import 'dart:async';
import 'dart:math';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';

import '../demo_data.dart';

/// Shows discovered peers in the shell (T1.1 → T1.12 Nearby devices).
class DiscoveryController {
  final DiscoveryService service;
  final PeerCache cache;
  final ValueNotifier<List<NearbyDevice>> nearby = ValueNotifier(const []);
  StreamSubscription<List<DiscoveredPeer>>? _changes;

  DiscoveryController(
      {required MdnsBackend backend,
      required this.cache,
      required DiscoveryRecord local,
      void Function(String)? onDebug})
      : service = DiscoveryService(
            backend: backend, cache: cache, record: local, onDebug: onDebug);

  Future<void> start() async {
    _changes ??= cache.changes.listen((peers) {
      final next = [for (final p in peers) nearbyDeviceFor(p)];
      // Windows reports a service once per adapter; only rebuild the UI
      // when what it shows actually changed.
      if (_key(next) != _key(nearby.value)) nearby.value = next;
    });
    await service.start();
  }

  static String _key(List<NearbyDevice> list) => [
        for (final d in list) '${d.name}|${d.detail}|${d.reach.name}'
      ].join('\n');

  Future<void> stop() async {
    await service.stop();
    await _changes?.cancel();
    _changes = null;
  }
}

/// Maps a cache entry to the UI row: name, OS and address; stale peers show
/// as manual (dimmed) until they answer again (§3.5).
NearbyDevice nearbyDeviceFor(DiscoveredPeer p) {
  final os = switch (p.record.os) {
    DeviceOs.macos => 'macOS',
    DeviceOs.windows => 'Windows',
    DeviceOs.android => 'Android',
    DeviceOs.ios => 'iOS',
  };
  final note = switch (p.trust) {
    PeerTrust.trusted => '',
    PeerTrust.untrusted => ' · ready to pair',
    PeerTrust.identityChanged => ' · identity changed!',
  };
  final online = p.state != PeerState.stale && p.record.tier < 3;
  return NearbyDevice(p.record.name, '$os · ${p.address}$note',
      online ? PeerReach.online : PeerReach.manual);
}

/// Random UUID v4 (RFC 4122) for this device.
String newDeviceId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Local record until identity (T1.2) and transport (T1.4) exist: a fresh
/// device id per launch, a random placeholder fingerprint (not a certificate)
/// and the first port of the range (nothing listens on it yet).
DiscoveryRecord placeholderLocalRecord({
  required String name,
  required DeviceOs os,
  Random? random,
}) {
  final r = random ?? Random.secure();
  final fp = List.generate(32, (_) => r.nextInt(256).toRadixString(16))
      .map((h) => h.padLeft(2, '0'))
      .join();
  return DiscoveryRecord(
    deviceId: newDeviceId(r),
    name: name,
    os: os,
    port: 53317,
    fingerprint: fp,
    capabilities: const ['clip.text'],
  );
}
