import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auto_start.dart';
import 'config.dart';

/// TTL choices; `null` = never clear (§15.6 `clipboard_ttl_seconds`).
const List<int?> ttlChoices = [null, 30, 60, 300, 900];

/// Settings screen from the UI design (FR-12, NFR-L01): every change is
/// saved and applied at once, with no restart.
class SettingsPage extends StatelessWidget {
  final ValueListenable<AppConfig> config;

  /// Saves (and applies OS side effects of) a new config; may throw.
  final Future<void> Function(AppConfig next) onChanged;

  const SettingsPage(
      {super.key, required this.config, required this.onChanged});

  Future<void> _apply(BuildContext context, AppConfig next) async {
    try {
      await onChanged(next);
    } on AutoStartException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not change "Start at login" on this system')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppConfig>(
        valueListenable: config,
        builder: (context, c, _) {
          void set(AppConfig next) => _apply(context, next);
          return ListView(
            padding: const EdgeInsets.all(DropClipSpacing.xxl),
            children: [
              Text('Settings',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const _Header('Application'),
              _Row(
                title: 'Language / ภาษา',
                subtitle: 'Changes every screen right away',
                trailing: SegmentedButton<AppLanguage>(
                  segments: const [
                    ButtonSegment(value: AppLanguage.th, label: Text('ไทย')),
                    ButtonSegment(
                        value: AppLanguage.en, label: Text('English')),
                  ],
                  selected: {c.language},
                  onSelectionChanged: (s) => set(c.copyWith(language: s.first)),
                ),
              ),
              _Toggle(
                title: 'Start at login',
                subtitle:
                    'Stays hidden in the menubar / system tray, no window',
                value: c.autoStart,
                onChanged: (v) => set(c.copyWith(autoStart: v)),
              ),
              const _Header('Clipboard'),
              _Toggle(
                title: 'Sync clipboard automatically',
                subtitle: 'Sends what you copy to paired devices right away',
                value: c.clipboardSyncEnabled,
                onChanged: (v) => set(c.copyWith(clipboardSyncEnabled: v)),
              ),
              _Row(
                title: 'Types to sync',
                subtitle: 'Password-manager content is never sent',
                trailing: Wrap(spacing: DropClipSpacing.sm, children: [
                  for (final (t, label) in [
                    (SyncType.text, 'Text'),
                    (SyncType.url, 'Links'),
                    (SyncType.image, 'Images'),
                  ])
                    FilterChip(
                      label: Text(label),
                      selected: c.syncTypes.contains(t),
                      onSelected: (on) => set(c.copyWith(
                          syncTypes: on
                              ? {...c.syncTypes, t}
                              : ({...c.syncTypes}..remove(t)))),
                    ),
                ]),
              ),
              _Row(
                title: 'Clear clipboard automatically (TTL)',
                subtitle: 'Clears received data after this time unless '
                    'something newer was copied',
                trailing: DropdownButton<int?>(
                  value: c.clipboardTtlSeconds,
                  items: [
                    for (final s in ttlChoices)
                      DropdownMenuItem(value: s, child: Text(ttlLabel(s))),
                  ],
                  onChanged: (s) =>
                      set(c.copyWith(clipboardTtlSeconds: () => s)),
                ),
              ),
              const _Header('Receiving files'),
              _Toggle(
                title: 'Accept files automatically',
                subtitle: 'From paired devices, without asking. Off by '
                    'default for safety (T-E03).',
                value: c.autoAccept,
                onChanged: (v) => set(c.copyWith(autoAccept: v)),
              ),
              _Row(
                title: 'Destination folder',
                subtitle: 'Files are SHA-256 checked before moving here and '
                    'are never opened automatically',
                trailing: Text(c.destinationDir,
                    style: dropClipMono(context, fontSize: 13)),
              ),
            ],
          );
        },
      );
}

String ttlLabel(int? seconds) => switch (seconds) {
      null => 'Never',
      < 60 => '$seconds seconds',
      60 => '1 minute',
      _ => '${seconds ~/ 60} minutes',
    };

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
            top: DropClipSpacing.xl, bottom: DropClipSpacing.sm),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: DropClipColors.of(context).textTertiary)),
      );
}

class _Row extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;
  const _Row(
      {required this.title, required this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DropClipSpacing.sm),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DropClipSpacing.lg,
          runSpacing: DropClipSpacing.sm,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: DropClipColors.of(context).textSecondary)),
                  ]),
            ),
            trailing,
          ],
        ),
      );
}

class _Toggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => _Row(
        title: title,
        subtitle: subtitle,
        trailing: Semantics(
            label: title, child: Switch(value: value, onChanged: onChanged)),
      );
}
