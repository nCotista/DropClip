import 'dart:convert';
import 'dart:io';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/debug/debug_console.dart';
import 'src/demo_data.dart';
import 'src/devices_page.dart';
import 'src/discovery/bonsoir_backend.dart';
import 'src/discovery/discovery_controller.dart';
import 'src/dropzone/dropzone_controller.dart';
import 'src/dropzone/dropzone_host.dart';
import 'src/l10n/strings.dart';
import 'src/native_host.dart';
import 'src/node/desktop_node.dart';
import 'src/node/os_key_store.dart';
import 'src/onboarding.dart';
import 'src/pairing/pairing_dialogs.dart';
import 'src/settings/auto_start.dart';
import 'src/settings/config.dart';
import 'src/settings/settings_page.dart';
import 'src/sync/clipboard_bridge.dart';
import 'src/shell.dart';
import 'src/transfers_and_devices_pages.dart';
import 'src/tray_controller.dart';
import 'src/tray_menu.dart';
import 'src/transfer/file_transfer.dart';
import 'src/transfer/receive_dialog.dart';

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
  final status = ValueNotifier(ShellStatus(
    networkName: demoShellStatus.networkName,
    address: demoShellStatus.address,
    verifiedDevices: 0,
    activeTransfers: 0,
    deviceCount: 0,
    clips: const [],
    suppressedClips: 0,
    nearby: const [],
    latencyP95Ms: demoShellStatus.latencyP95Ms,
  ));
  // File transfer with paired peers (T1.10/T1.11) into Downloads/DropClip.
  final transfers = ValueNotifier<List<DesktopTransferRecord>>(const []);
  final home = Platform.environment[isMacOS ? 'HOME' : 'USERPROFILE'] ?? '.';
  final navigator = GlobalKey<NavigatorState>();
  final files = FileTransfers(
    node: node,
    downloads: Directory('$home${Platform.pathSeparator}Downloads'
        '${Platform.pathSeparator}DropClip'),
    decide: (peer, items) async {
      if (store.config.value.autoAccept) return true;
      final context = navigator.currentContext;
      if (context == null) return false;
      return askToReceive(context, peer, items);
    },
    onUpdate: (u) => transfers.value = [
      DesktopTransferRecord(
        id: u.id,
        fileName: u.name,
        peerName: u.incoming ? '← ${u.peer}' : '→ ${u.peer}',
        totalBytes: u.total,
        transferredBytes: u.done,
        completed: u.state == 'complete',
      ),
      for (final t in transfers.value)
        if (t.id != u.id) t,
    ],
  );
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

  // Tier 1 clipboard sync with paired peers (T1.9, FR-03A).
  void showClip(ClipEvent e) {
    final updated = [
      ClipItem(
        switch (e.type) {
          ClipType.text => ClipKind.text,
          ClipType.url => ClipKind.link,
          ClipType.image => ClipKind.image,
        },
        e.preview,
        sourceDevice: e.from == 'me' ? store.config.value.deviceName : e.from,
        age: DateTime.now().toIso8601String().substring(11, 16),
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
    log.info('clipboard', e.from == 'me' ? 'sent' : 'received',
        {'type': e.type.name});
  }

  final native = NativeClipboard(FlutterClipboardChannel(),
      log: (m) => log.debug('clipboard', m));
  final clipboard = ClipboardBridge(
    node: node,
    native: native,
    changes: native.changes,
    windows: !isMacOS,
    onClip: showClip,
    policy: () => syncPolicyFor(store.config.value),
  );

  // UI-03: this device hosts a session; the other types its PIN.
  Future<void> pairNew() async {
    section.value = ShellSection.devices;
    final context = navigator.currentContext;
    if (context == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HostPairingDialog(
        open: () async {
          final s = await node.openPairing();
          return (
            pin: s.pin,
            address: '${s.qr.ip}:${s.qr.port}',
            qr: jsonEncode(s.qr.toJson()),
          );
        },
        events: node.pairing.events,
        confirm: node.pairing.confirm,
      ),
    );
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
      ),
    ),
    navigatorKey: navigator,
    devicesPage: DevicesPage(
      myName: node.me.name,
      myFingerprint: node.me.fp,
      trusted: node.trusted,
      connectedChanges: node.mesh.peerChanges,
      connected: () => node.mesh.connected,
      nearby: discovery.peers,
      onPairNew: pairNew,
      onPairWith: (peer) => showDialog<void>(
        context: navigator.currentContext!,
        barrierDismissible: false,
        builder: (_) => ClientPairingDialog(
          peerName: peer.record.name,
          pair: (pin, confirm) => node.pairWith(peer, pin, confirm),
        ),
      ),
      onForget: (d) => node.forget(d.deviceId),
      quarantined: node.quarantined,
      onSettle: (d, remove) =>
          node.settleQuarantine(d.deviceId, remove: remove),
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
    onSendClipboard: clipboard.sendNow,
    onPair: pairNew,
    // UI-02: drop files anywhere, or open from the tray / ⌥⌘D, Ctrl+Alt+D.
    overlay: (context, child) => DebugConsoleHost(
      feed: _LoggerFeed(log),
      child: DropzoneHost(
        controller: dropzone,
        devices: discovery.nearby,
        onSend: (device, items) {
          final paths = [
            for (final i in items)
              if (!i.isFolder && i.path != null) File(i.path!)
          ];
          final paired = node.trusted.value.any((d) => d.deviceId == device.id);
          if (!paired || paths.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(Strings.of(context).pairFailed('E_NOT_PAIRED'))));
            return;
          }
          dropzone.close();
          section.value = ShellSection.transfers;
          files.send(device.id!, device.name, paths).catchError(
              (Object e) => log.warn('transfer', 'send failed: $e'));
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
  try {
    await clipboard.start();
  } on Object catch (e) {
    log.warn('clipboard', 'native watcher unavailable: $e');
  }
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
