import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'clipboard_page.dart';
import 'l10n/strings.dart';
import 'demo_data.dart';
import 'tray_menu.dart';

/// Main window sections from the UI design (Clipboard is the home screen).
enum ShellSection { clipboard, transfers, devices, settings }

extension on ShellSection {
  String label(Strings s) => switch (this) {
        ShellSection.clipboard => s.clipboard,
        ShellSection.transfers => s.transfers,
        ShellSection.devices => s.devices,
        ShellSection.settings => s.settings,
      };

  IconData get icon => switch (this) {
        ShellSection.clipboard => Icons.content_paste_rounded,
        ShellSection.transfers => Icons.swap_vert_rounded,
        ShellSection.devices => Icons.devices_rounded,
        ShellSection.settings => Icons.settings_rounded,
      };

  int? count(ShellStatus s) => switch (this) {
        ShellSection.clipboard => s.clipCount,
        ShellSection.transfers => s.activeTransfers,
        ShellSection.devices => s.deviceCount,
        ShellSection.settings => null,
      };
}

/// Desktop main window: sidebar navigation + the selected page (T1.12).
class DesktopShell extends StatefulWidget {
  final ShellStatus status;

  /// Selected section; shared so the tray menu can open a screen.
  final ValueNotifier<ShellSection>? section;

  /// Shown for the Settings section; a placeholder when null.
  final Widget? settingsPage;
  final Widget? transfersPage;
  final Widget? devicesPage;

  /// Shown above every page (e.g. first-run firewall onboarding).
  final Widget? banner;

  /// Opens the Dropzone (UI-02); a "not available" note when null.
  final VoidCallback? onOpenDropzone;
  final VoidCallback? onSendClipboard;
  final VoidCallback? onPair;
  final ValueChanged<ClipItem>? onCopyClip;
  final VoidCallback? onLinkWeb;

  const DesktopShell(
      {super.key,
      required this.status,
      this.section,
      this.settingsPage,
      this.transfersPage,
      this.devicesPage,
      this.banner,
      this.onOpenDropzone,
      this.onSendClipboard,
      this.onPair,
      this.onCopyClip,
      this.onLinkWeb});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final ValueNotifier<ShellSection> _section =
      widget.section ?? ValueNotifier(ShellSection.clipboard);

  @override
  void dispose() {
    if (widget.section == null) _section.dispose();
    super.dispose();
  }

  /// Buttons stay enabled so they do not look broken; until their engine
  /// lands they say so instead of doing nothing.
  VoidCallback _notReady(String feature, String ticket) =>
      () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Strings.of(context).notAvailable(feature, ticket))));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: _section,
        builder: (context, section, _) => Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                status: widget.status,
                selected: section,
                onSelect: (s) => _section.value = s,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.banner != null) widget.banner!,
                    Expanded(
                      child: switch (section) {
                        ShellSection.clipboard => ClipboardPage(
                            status: widget.status,
                            onSendClipboard: widget.onSendClipboard ??
                                _notReady(
                                    Strings.of(context).sendClipboard, 'T1.9'),
                            onCopy: widget.onCopyClip,
                            onLinkWeb: widget.onLinkWeb,
                            onPair: widget.onPair ??
                                _notReady(Strings.of(context).pairing, 'T1.3'),
                            onOpenDropzone: widget.onOpenDropzone ??
                                _notReady(
                                    Strings.of(context).dropzone, 'T1.12'),
                          ),
                        ShellSection.transfers
                            when widget.transfersPage != null =>
                          widget.transfersPage!,
                        ShellSection.devices when widget.devicesPage != null =>
                          widget.devicesPage!,
                        ShellSection.settings
                            when widget.settingsPage != null =>
                          widget.settingsPage!,
                        _ => _PagePlaceholder(section: section),
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Screen a tray action opens. Dropzone, Pair and Send clipboard get their
/// own screens later; until then they land on Clipboard.
ShellSection sectionForTrayAction(TrayAction action) => switch (action) {
      TrayAction.settings => ShellSection.settings,
      TrayAction.trustedDevices => ShellSection.devices,
      _ => ShellSection.clipboard,
    };

class _Sidebar extends StatelessWidget {
  final ShellStatus status;
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;

  const _Sidebar({
    required this.status,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final s = Strings.of(context);
    final caption = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.88,
      color: c.textTertiary,
    );
    return Container(
      width: 232,
      padding: const EdgeInsets.all(DropClipSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.layers_rounded, color: c.accent, size: 28),
            const SizedBox(width: DropClipSpacing.sm),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(DropClipThemeTokens.appName,
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('v1.0 · Desktop',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  ]),
            ),
          ]),
          const SizedBox(height: DropClipSpacing.xl),
          Text(s.workspace, style: caption),
          const SizedBox(height: DropClipSpacing.sm),
          for (final sec in ShellSection.values)
            _NavItem(
              section: sec,
              count: sec.count(status),
              selected: sec == selected,
              onTap: () => onSelect(sec),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(DropClipSpacing.md),
            decoration: BoxDecoration(
              color: c.elevated,
              borderRadius: BorderRadius.circular(DropClipRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.thisDevice, style: caption),
                const SizedBox(height: DropClipSpacing.sm),
                Text(status.networkName, overflow: TextOverflow.ellipsis),
                Text(status.address,
                    overflow: TextOverflow.ellipsis,
                    style: dropClipMono(context, fontSize: 12)
                        .copyWith(color: c.textSecondary)),
                const SizedBox(height: DropClipSpacing.sm),
                Text(s.devicesVerified(status.verifiedDevices),
                    style: TextStyle(fontSize: 12, color: c.success)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ShellSection section;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.section,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final fg = selected ? c.textPrimary : c.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(DropClipRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(DropClipRadius.button),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: DropClipSpacing.md, vertical: 10),
            child: Row(children: [
              Icon(section.icon, size: 18, color: selected ? c.textAccent : fg),
              const SizedBox(width: DropClipSpacing.md),
              Expanded(
                  child: Text(section.label(Strings.of(context)),
                      style: TextStyle(color: fg))),
              if (count != null)
                Text('$count',
                    style: dropClipMono(context, fontSize: 12)
                        .copyWith(color: c.textTertiary)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PagePlaceholder extends StatelessWidget {
  final ShellSection section;

  const _PagePlaceholder({required this.section});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(DropClipSpacing.xxl),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(section.label(Strings.of(context)),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}
