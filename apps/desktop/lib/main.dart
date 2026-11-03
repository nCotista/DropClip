import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/demo_data.dart';
import 'src/discovery/bonsoir_backend.dart';
import 'src/discovery/discovery_controller.dart';
import 'src/dropzone/dropzone_controller.dart';
import 'src/dropzone/dropzone_host.dart';
import 'src/l10n/strings.dart';
import 'src/native_host.dart';
import 'src/onboarding.dart';
import 'src/settings/auto_start.dart';
import 'src/settings/config.dart';
import 'src/settings/settings_page.dart';
import 'src/shell.dart';
import 'src/tray_controller.dart';
import 'src/tray_menu.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // `--hidden` is passed by the login item / Run key (T1.12, NFR-U03).
  final hidden = args.contains('--hidden');
  final section = ValueNotifier(ShellSection.clipboard);
  final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

  final dropzone = DropzoneController();
  final tray = TrayController(
    NativeDesktopHost(isMacOS: isMacOS),
    onAction: (a) => a == TrayAction.openDropzone
        ? dropzone.show()
        : section.value = sectionForTrayAction(a),
  );

  // config.json (FR-12, §15.6); auto-start uses the Windows Run key.
  final debugLog = _debugLog(Platform.environment['DROPCLIP_DISCOVERY_LOG']);
  final store = ConfigStore(
    ConfigStore.defaultFile(Platform.environment, isMacOS: isMacOS),
    defaultDeviceName: Platform.localHostname,
    onWarn: debugLog,
  );
  await store.load();
  final configs = ConfigController(
    store,
    isMacOS
        ? const UnsupportedAutoStart()
        : WindowsRunKeyAutoStart(Platform.resolvedExecutable),
  );

  // Real mDNS discovery (T1.1) feeds Nearby devices; the rest is demo data.
  final local = placeholderLocalRecord(
    name: store.config.value.deviceName,
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

  final app = DropClipDesktopApp(
    hiddenLaunch: hidden,
    status: status.value,
    liveStatus: status,
    section: section,
    settingsPage: SettingsPage(config: store.config, onChanged: configs.update),
    // §3.1: explain the Windows Firewall prompt once, on first run.
    banner: isMacOS
        ? null
        : ValueListenableBuilder<AppConfig>(
            valueListenable: store.config,
            builder: (_, c, __) => c.firstRunDone
                ? const SizedBox.shrink()
                : FirewallOnboardingCard(
                    onDone: () =>
                        configs.update(c.copyWith(firstRunDone: true))),
          ),
    // UI-02: drop files anywhere, or open from the tray / ⌥⌘D, Ctrl+Alt+D.
    overlay: (context, child) => DropzoneHost(
      controller: dropzone,
      devices: discovery.nearby,
      // File transfer (T1.10/T1.11) is not built yet.
      onSend: (_, __) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Strings.of(context)
              .notAvailable(Strings.of(context).transfers, 'T1.10')))),
      child: child!,
    ),
  );
  // NFR-L01: the UI language follows config.json and switches at once.
  runApp(ValueListenableBuilder<AppConfig>(
    valueListenable: store.config,
    builder: (_, c, child) =>
        StringsScope(strings: Strings.forLanguage(c.language), child: child!),
    child: app,
  ));
  // The runner no longer shows the window itself (flutter_window.cpp), so
  // showing it after the first frame avoids a blank window, and a hidden
  // launch never flashes one.
  await WidgetsBinding.instance.endOfFrame;
  await tray.start(
      hidden: hidden,
      strings: Strings.forLanguage(store.config.value.language));
  // The native tray menu follows the language too (NFR-L01).
  store.config.addListener(
      () => tray.setStrings(Strings.forLanguage(store.config.value.language)));
  await configs.reconcile();
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
