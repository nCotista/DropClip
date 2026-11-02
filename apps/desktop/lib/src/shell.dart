import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';

/// Main window sections from the UI design (Clipboard is the home screen).
enum ShellSection { clipboard, transfers, devices, settings }

extension on ShellSection {
  String get label => switch (this) {
        ShellSection.clipboard => 'Clipboard',
        ShellSection.transfers => 'Transfers',
        ShellSection.devices => 'Devices',
        ShellSection.settings => 'Settings',
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

  const DesktopShell({super.key, required this.status});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  ShellSection _section = ShellSection.clipboard;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              status: widget.status,
              selected: _section,
              onSelect: (s) => setState(() => _section = s),
            ),
            Expanded(child: _PagePlaceholder(section: _section)),
          ],
        ),
      );
}

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
          Text('WORKSPACE', style: caption),
          const SizedBox(height: DropClipSpacing.sm),
          for (final s in ShellSection.values)
            _NavItem(
              section: s,
              count: s.count(status),
              selected: s == selected,
              onTap: () => onSelect(s),
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
                Text('THIS DEVICE', style: caption),
                const SizedBox(height: DropClipSpacing.sm),
                Text(status.networkName, overflow: TextOverflow.ellipsis),
                Text(status.address,
                    overflow: TextOverflow.ellipsis,
                    style: dropClipMono(context, fontSize: 12)
                        .copyWith(color: c.textSecondary)),
                const SizedBox(height: DropClipSpacing.sm),
                Text('${status.verifiedDevices} devices verified (SAS)',
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
              Expanded(child: Text(section.label, style: TextStyle(color: fg))),
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
          child: Text(section.label,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}
