import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/demo_data.dart';
import 'src/discovery/bonsoir_backend.dart';
import 'src/discovery/discovery_controller.dart';
import 'src/native_host.dart';
import 'src/shell.dart';
import 'src/tray_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // `--hidden` is passed by the login item / Run key (T1.12, NFR-U03).
  final hidden = args.contains('--hidden');
  final section = ValueNotifier(ShellSection.clipboard);
  final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

  final tray = TrayController(
    NativeDesktopHost(isMacOS: isMacOS),
    onAction: (a) => section.value = sectionForTrayAction(a),
  );

  // Real mDNS discovery (T1.1) feeds Nearby devices; the rest is demo data.
  final debugLog = _debugLog(Platform.environment['DROPCLIP_DISCOVERY_LOG']);
  final local = placeholderLocalRecord(
    name: Platform.localHostname,
    os: isMacOS ? DeviceOs.macos : DeviceOs.windows,
  );
  // No Trusted Store yet (T1.2), so every peer shows as ready to pair.
  final discovery = DiscoveryController(
    backend: BonsoirMdnsBackend(),
    cache: PeerCache(
        localDeviceId: local.deviceId, trustedFingerprint: (_) => null),
    local: local,
    onDebug: debugLog,
  );
  final status = ValueNotifier(demoShellStatus.withNearby(const []));
  discovery.nearby.addListener(() {
    status.value = status.value.withNearby(discovery.nearby.value);
    debugLog?.call('nearby: ${[
      for (final d in discovery.nearby.value)
        '${d.name} (${d.detail}, ${d.reach.name})'
    ]}');
  });

  runApp(DropClipDesktopApp(
    hiddenLaunch: hidden,
    status: status.value,
    liveStatus: status,
    section: section,
  ));
  // The runner no longer shows the window itself (flutter_window.cpp), so
  // showing it after the first frame avoids a blank window, and a hidden
  // launch never flashes one.
  await WidgetsBinding.instance.endOfFrame;
  await tray.start(hidden: hidden);
  debugLog?.call('started ${discovery.service.record.deviceId}');
  await discovery.start();
}

/// Dev aid: with `DROPCLIP_DISCOVERY_LOG=<file>`, discovery events are
/// appended there with timestamps. TXT data is public (§3.2); no secrets.
void Function(String)? _debugLog(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return (line) => file.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $line\n',
      mode: FileMode.append);
}
