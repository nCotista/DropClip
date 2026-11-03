import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'l10n/strings.dart';

enum TrayAction {
  openDropzone('Open Dropzone', '⌥⌘D', 'Ctrl+Alt+D'),
  sendClipboard('Send clipboard to…', '⌥⌘V', 'Ctrl+Alt+V'),
  pair('Pair new device…', null, null),
  trustedDevices('Trusted devices…', null, null),
  settings('Settings…', '⌘,', 'Ctrl+,'),
  quit('Quit DropClip', '⌘Q', null);

  final String label;
  final String? macShortcut;
  final String? windowsShortcut;

  const TrayAction(this.label, this.macShortcut, this.windowsShortcut);

  String? shortcutFor(TargetPlatform platform) =>
      platform == TargetPlatform.macOS ? macShortcut : windowsShortcut;

  /// Localized label for the in-app menu (NFR-L01). [label] stays English
  /// for the native tray menu, which the OS builds once at startup.
  String labelIn(Strings s) => switch (this) {
        openDropzone => s.trayOpenDropzone,
        sendClipboard => s.traySendClipboard,
        pair => s.trayPair,
        trustedDevices => s.trayTrusted,
        settings => s.traySettings,
        quit => s.trayQuit,
      };
}

/// Menubar (macOS) / system tray (Windows) popover from the UI design
/// (T1.12, UI-01, NFR-U03). The same content is shown on both OSes; the
/// tray icon and popup window are wired in a later PR.
class TrayMenu extends StatelessWidget {
  final ShellStatus status;
  final bool syncEnabled;
  final ValueChanged<bool> onSyncChanged;
  final ValueChanged<TrayAction> onAction;

  /// Defaults to [defaultTargetPlatform]; picks the shortcut labels.
  final TargetPlatform? platform;

  const TrayMenu({
    super.key,
    required this.status,
    required this.syncEnabled,
    required this.onSyncChanged,
    required this.onAction,
    this.platform,
  });

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final t = Strings.of(context);
    final os = platform ?? defaultTargetPlatform;
    Widget divider() => Divider(height: DropClipSpacing.lg, color: c.border);
    return Container(
      width: 320,
      padding: const EdgeInsets.all(DropClipSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(DropClipRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Icon(Icons.layers_rounded, color: c.accent, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(DropClipThemeTokens.appName,
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(t.connectedTo(status.networkName),
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary)),
                    ]),
              ),
              Semantics(
                label: t.clipboardSync,
                child: Switch(value: syncEnabled, onChanged: onSyncChanged),
              ),
            ]),
          ),
          divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(t.onlineDevices,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.88,
                    color: c.textTertiary)),
          ),
          if (status.nearby.isEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(t.noDevicesNearby,
                  style: TextStyle(color: c.textTertiary)),
            ),
          for (final d in status.nearby)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, overflow: TextOverflow.ellipsis),
                        Text(d.detail,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: c.textSecondary)),
                      ]),
                ),
                Icon(Icons.circle,
                    size: 8,
                    color: d.reach == PeerReach.online ? c.success : c.warning),
              ]),
            ),
          for (final a in TrayAction.values) ...[
            // Groups as in the design: actions, then Quit on its own.
            if (a == TrayAction.values.first || a == TrayAction.quit) divider(),
            _MenuItem(
              action: a,
              shortcut: a.shortcutFor(os),
              onTap: () => onAction(a),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final TrayAction action;
  final String? shortcut;
  final VoidCallback onTap;

  const _MenuItem(
      {required this.action, required this.shortcut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DropClipRadius.button),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            Expanded(child: Text(action.labelIn(Strings.of(context)))),
            if (shortcut != null)
              Text(shortcut!,
                  style: dropClipMono(context, fontSize: 12)
                      .copyWith(color: c.textTertiary)),
          ]),
        ),
      ),
    );
  }
}
