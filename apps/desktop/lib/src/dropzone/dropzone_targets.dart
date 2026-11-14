import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';

import '../demo_data.dart';
import '../web/web_companion.dart';

/// Builds Dropzone target devices from mDNS discovery, active mesh peers not
/// already present in discovery, and linked browser sessions.
List<NearbyDevice> buildDropzoneTargets({
  required List<NearbyDevice> nearby,
  required List<TrustedDevice> trusted,
  required Set<String> connected,
  required List<WebSession> sessions,
}) {
  final seenIds = <String>{
    for (final device in nearby)
      if (device.id != null) device.id!,
  };
  return [
    ...nearby,
    for (final device in trusted)
      if (device.status == 'active' &&
          connected.contains(device.deviceId) &&
          seenIds.add(device.deviceId))
        NearbyDevice(
          device.name,
          'Connected',
          PeerReach.online,
          id: device.deviceId,
        ),
    for (final session in sessions)
      if (seenIds.add('web:${session.id}'))
        NearbyDevice(
          session.name,
          'Browser',
          PeerReach.online,
          id: 'web:${session.id}',
        ),
  ];
}

/// Synchronizes [targets] immediately and on every source update; returns a
/// callback that detaches all listeners and cancels the peer stream.
VoidCallback bindDropzoneTargets({
  required ValueNotifier<List<NearbyDevice>> targets,
  required ValueListenable<List<NearbyDevice>> nearby,
  required ValueListenable<List<TrustedDevice>> trusted,
  required Set<String> Function() connected,
  required Stream<Object?> peerChanges,
  required ValueListenable<List<WebSession>> sessions,
}) {
  void update() {
    targets.value = buildDropzoneTargets(
      nearby: nearby.value,
      trusted: trusted.value,
      connected: connected(),
      sessions: sessions.value,
    );
  }

  nearby.addListener(update);
  sessions.addListener(update);
  trusted.addListener(update);
  final sub = peerChanges.listen((_) => update());
  update();
  return () {
    nearby.removeListener(update);
    sessions.removeListener(update);
    trusted.removeListener(update);
    unawaited(sub.cancel());
  };
}
