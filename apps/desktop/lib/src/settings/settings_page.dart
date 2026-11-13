import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.of(context).autoStartFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppConfig>(
        valueListenable: config,
        builder: (context, c, _) {
          final s = Strings.of(context);
          void set(AppConfig next) => _apply(context, next);
          return ListView(
            padding: const EdgeInsets.all(DropClipSpacing.xxl),
            children: [
              Text(s.settings,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              _Header(s.application),
              _Row(
                title: 'ภาษา / Language',
                subtitle: s.languageSub,
                trailing: SegmentedButton<AppLanguage>(
                  segments: const [
                    ButtonSegment(value: AppLanguage.th, label: Text('ไทย')),
                    ButtonSegment(
                        value: AppLanguage.en, label: Text('English')),
                  ],
                  selected: {c.language},
                  onSelectionChanged: (l) => set(c.copyWith(language: l.first)),
                ),
              ),
              _Toggle(
                title: s.startAtLogin,
                subtitle: s.startAtLoginSub,
                value: c.autoStart,
                onChanged: (v) => set(c.copyWith(autoStart: v)),
              ),
              _Toggle(
                title: s.webCompanion,
                subtitle: s.webCompanionSub,
                value: c.webCompanionEnabled,
                onChanged: (v) => set(c.copyWith(webCompanionEnabled: v)),
              ),
              _Header(s.clipboard),
              _Toggle(
                title: s.syncAuto,
                subtitle: s.syncAutoSub,
                value: c.clipboardSyncEnabled,
                onChanged: (v) => set(c.copyWith(clipboardSyncEnabled: v)),
              ),
              _Row(
                title: s.typesToSync,
                subtitle: s.typesToSyncSub,
                trailing: Wrap(spacing: DropClipSpacing.sm, children: [
                  for (final (t, label) in [
                    (SyncType.text, s.text),
                    (SyncType.url, s.links),
                    (SyncType.image, s.images),
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
                title: s.ttlTitle,
                subtitle: s.ttlSub,
                trailing: DropdownButton<int?>(
                  value: c.clipboardTtlSeconds,
                  items: [
                    for (final t in ttlChoices)
                      DropdownMenuItem(value: t, child: Text(s.ttl(t))),
                  ],
                  onChanged: (t) =>
                      set(c.copyWith(clipboardTtlSeconds: () => t)),
                ),
              ),
              _Header(s.receivingFiles),
              _Toggle(
                title: s.autoAccept,
                subtitle: s.autoAcceptSub,
                value: c.autoAccept,
                onChanged: (v) => set(c.copyWith(autoAccept: v)),
              ),
              _Row(
                title: s.destination,
                subtitle: s.destinationSub,
                trailing: Text(c.destinationDir,
                    style: dropClipMono(context, fontSize: 13)),
              ),
            ],
          );
        },
      );
}

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
