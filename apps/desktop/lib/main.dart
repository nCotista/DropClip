import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/debug/debug_console.dart';
import 'src/demo_data.dart';
import 'src/discovery/bonsoir_backend.dart';
import 'src/discovery/discovery_controller.dart';
import 'src/dropzone/dropzone_controller.dart';
import 'src/dropzone/dropzone_host.dart';
import 'src/l10n/strings.dart';
import 'src/native_host.dart';
import 'src/node/desktop_node.dart';
import 'src/node/os_key_store.dart';
import 'src/onboarding.dart';
import 'src/settings/auto_start.dart';
import 'src/settings/config.dart';
import 'src/settings/settings_page.dart';
import 'src/shell.dart';
import 'src/transfers_and_devices_pages.dart';
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
  // Warnings during load are kept until the logger exists (it needs the
  // device id, which needs the config).
  final early = <String>[];
  void Function(String) warn = early.add;
  final store = ConfigStore(
    ConfigStore.defaultFile(Platform.environment, isMacOS: isMacOS),
    defaultDeviceName: Platform.localHostname,
    onWarn: (m) => warn(m),
  );
  await store.load();
  final configs = ConfigController(
    store,
    isMacOS
        ? MacLaunchAgentAutoStart(Platform.resolvedExecutable,
            home: Platform.environment['HOME'] ?? '')
        : WindowsRunKeyAutoStart(Platform.resolvedExecutable),
  );

  // Persistent identity, Trusted Store, mTLS server, pairing and the
  // Control Plane (T1.2–T1.5), keys in DPAPI / Keychain (§4.2).
  final configDir = store.file.parent;
  final node = await DesktopNode.start(
    dir: configDir,
    keys: osKeyStore(Directory('${configDir.path}/keys')),
    name: store.config.value.deviceName,
    os: isMacOS ? DeviceOs.macos : DeviceOs.windows,
    log: (m) => warn(m),
  );
  final local = node.record;
  // Structured JSON logs (T0.3): <config dir>/logs, 10 MB × 5 files, every
  // line scrubbed (NFR-S02). Ctrl+Shift+D / ⌘⇧D shows them in the app.
  final log = StructuredLogger(
    deviceId: local.deviceId,
    // §15.6 log_level; per-event discovery chatter is debug only.
    minLevel: LogLevel.values.byName(store.config.value.logLevel),
    sink: RotatingFileSink(
        Directory('${store.file.parent.path}${Platform.pathSeparator}logs')),
  );
  warn = (m) => log.warn('config', m);
  early.forEach(warn);
  // Paired peers are recognised by fingerprint and dialed automatically.
  final discovery = DiscoveryController(
    backend: BonsoirMdnsBackend(),
    cache: PeerCache(
        localDeviceId: local.deviceId,
        trustedFingerprint: node.store.fingerprintOf),
    local: local,
    onDebug: (m) => log.debug('discovery', m),
  );
  discovery.cache.changes.listen(node.onPeers);
  node.mesh.peerChanges
      .listen((ids) => log.info('mesh', 'connected', {'peers': ids.length}));
  final status = ValueNotifier(demoShellStatus);
  final transfers = ValueNotifier<List<DesktopTransferRecord>>([
    const DesktopTransferRecord(
      id: 'tx-1',
      fileName: 'Design-Review-Deck.pdf',
      peerName: 'Pixel 8',
      totalBytes: 18 * 1024 * 1024,
      transferredBytes: 18 * 1024 * 1024,
      completed: true,
    ),
    const DesktopTransferRecord(
      id: 'tx-2',
      fileName: '4K-Demo-Recording.mp4.part',
      peerName: 'Surface Laptop',
      totalBytes: 256 * 1024 * 1024,
      transferredBytes: 128 * 1024 * 1024,
      resumablePart: true,
    ),
  ]);
  discovery.nearby.addListener(() {
    final found = discovery.nearby.value;
    if (found.isNotEmpty) {
      status.value = status.value.withNearby(found);
    }
    // Names come from public TXT records (§3.2).
    log.info('discovery', 'nearby', {
      'devices': [for (final d in found) '${d.name} (${d.reach.name})'],
    });
  });

  Future<void> sendLocalClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text?.trim().isNotEmpty ?? false)
        ? data!.text!.trim()
        : 'Live clipboard broadcast from ${store.config.value.deviceName}';
    final updated = [
      ClipItem(
        text.startsWith('http') ? ClipKind.link : ClipKind.text,
        text,
        sourceDevice: store.config.value.deviceName,
        age: 'just now',
      ),
      ...status.value.clips,
    ].take(20).toList();
    status.value = ShellStatus(
      networkName: status.value.networkName,
      address: status.value.address,
      verifiedDevices: status.value.verifiedDevices,
      activeTransfers: status.value.activeTransfers,
      deviceCount: status.value.deviceCount,
      clips: updated,
      suppressedClips: status.value.suppressedClips,
      nearby: status.value.nearby,
      latencyP95Ms: status.value.latencyP95Ms,
    );
    log.info('clipboard', 'broadcast', {'items': updated.length});
  }

  final app = DropClipDesktopApp(
    hiddenLaunch: hidden,
    status: status.value,
    liveStatus: status,
    section: section,
    settingsPage: SettingsPage(config: store.config, onChanged: configs.update),
    transfersPage: ValueListenableBuilder<List<DesktopTransferRecord>>(
      valueListenable: transfers,
      builder: (_, list, __) => DesktopTransfersPage(
        transfers: list,
        onOpenDropzone: dropzone.show,
        onSendSampleFile: () {
          final nextId = 'tx-${list.length + 1}';
          transfers.value = [
            DesktopTransferRecord(
              id: nextId,
              fileName: 'Sample-Archive-$nextId.zip',
              peerName: status.value.nearby.isNotEmpty
                  ? status.value.nearby.first.name
                  : 'Pixel 8',
              totalBytes: 32 * 1024 * 1024,
              transferredBytes: 32 * 1024 * 1024,
              completed: true,
            ),
            ...list,
          ];
        },
        onResumeTransfer: (id) {
          transfers.value = [
            for (final item in list)
              if (item.id == id)
                DesktopTransferRecord(
                  id: item.id,
                  fileName: item.fileName.replaceAll('.part', ''),
                  peerName: item.peerName,
                  totalBytes: item.totalBytes,
                  transferredBytes: item.totalBytes,
                  completed: true,
                )
              else
                item,
          ];
        },
      ),
    ),
    devicesPage: ValueListenableBuilder<ShellStatus>(
      valueListenable: status,
      builder: (_, s, __) => DesktopDevicesPage(nearby: s.nearby),
    ),
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
    onOpenDropzone: dropzone.show,
    onSendClipboard: sendLocalClipboard,
    onPair: () => section.value = ShellSection.devices,
    // UI-02: drop files anywhere, or open from the tray / ⌥⌘D, Ctrl+Alt+D.
    overlay: (context, child) => DebugConsoleHost(
      feed: _LoggerFeed(log),
      child: DropzoneHost(
        controller: dropzone,
        devices: discovery.nearby,
        onSend: (device, items) {
          final added = [
            for (var i = 0; i < items.length; i++)
              DesktopTransferRecord(
                id: 'drop-${DateTime.now().millisecondsSinceEpoch}-$i',
                fileName: items[i].name,
                peerName: device.name,
                totalBytes: items[i].bytes <= 0 ? 1048576 : items[i].bytes,
                transferredBytes:
                    items[i].bytes <= 0 ? 1048576 : items[i].bytes,
                completed: true,
              ),
          ];
          transfers.value = [...added, ...transfers.value];
          dropzone.close();
          section.value = ShellSection.transfers;
        },
        child: child!,
      ),
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
  log.info('app', 'started', {'hidden': hidden});
  await discovery.start();
}

/// The core logger as the debug console's feed.
class _LoggerFeed implements LogFeed {
  final StructuredLogger log;

  _LoggerFeed(this.log);

  @override
  List<String> get recent => log.recent;

  @override
  Stream<String> get lines => log.lines;
}
