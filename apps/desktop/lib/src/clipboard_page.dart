import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_data.dart';

/// Clipboard home screen from the UI design (T1.12, FR-04, FR-05, SF-03).
class ClipboardPage extends StatefulWidget {
  final ShellStatus status;

  /// Re-copies a clip into the local clipboard. Defaults to the system
  /// clipboard for text; images need the native watcher (T1.6/T1.7).
  final ValueChanged<ClipItem>? onCopy;
  final VoidCallback? onSendClipboard;

  const ClipboardPage({
    super.key,
    required this.status,
    this.onCopy,
    this.onSendClipboard,
  });

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage> {
  bool _autoSync = true;
  ClipKind? _filter;
  String _query = '';

  List<ClipItem> get _visible => widget.status.clips
      .where((c) => _filter == null || c.kind == _filter)
      .where((c) => c.preview.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  void _copy(ClipItem clip) {
    if (widget.onCopy != null) {
      widget.onCopy!(clip);
    } else if (clip.kind != ClipKind.image) {
      Clipboard.setData(ClipboardData(text: clip.preview));
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final s = widget.status;
    final clips = _visible;
    return ListView(
      padding: const EdgeInsets.all(DropClipSpacing.xxl),
      children: [
        Wrap(
          spacing: DropClipSpacing.lg,
          runSpacing: DropClipSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Clipboard',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                  'Live sync across ${s.verifiedDevices} devices'
                  ' · text, links, PNG/JPEG',
                  style: TextStyle(color: c.textSecondary)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Auto-sync', style: TextStyle(color: c.textSecondary)),
              Switch(
                value: _autoSync,
                onChanged: (v) => setState(() => _autoSync = v),
              ),
            ]),
            FilledButton.icon(
              onPressed: widget.onSendClipboard,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send clipboard'),
            ),
          ],
        ),
        const SizedBox(height: DropClipSpacing.xl),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search recent clips…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: DropClipSpacing.lg),
        Wrap(spacing: DropClipSpacing.sm, children: [
          for (final (label, kind) in [
            ('All', null),
            ('Text', ClipKind.text),
            ('Links', ClipKind.link),
            ('Images', ClipKind.image),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _filter == kind,
              onSelected: (_) => setState(() => _filter = kind),
            ),
        ]),
        const SizedBox(height: DropClipSpacing.xl),
        Text('RECENT · UP TO 20 ITEMS · MEMORY ONLY',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: c.textTertiary)),
        const SizedBox(height: DropClipSpacing.sm),
        if (clips.isEmpty)
          Padding(
            padding: const EdgeInsets.all(DropClipSpacing.xl),
            child:
                Text('No clips match', style: TextStyle(color: c.textTertiary)),
          ),
        for (final clip in clips)
          _ClipTile(clip: clip, onCopy: () => _copy(clip)),
        if (s.suppressedClips > 0) ...[
          const SizedBox(height: DropClipSpacing.md),
          _SuppressedNotice(count: s.suppressedClips),
        ],
      ],
    );
  }
}

class _ClipTile extends StatelessWidget {
  final ClipItem clip;
  final VoidCallback onCopy;

  const _ClipTile({required this.clip, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final (icon, tint) = switch (clip.kind) {
      ClipKind.text => (Icons.notes_rounded, c.textAccent),
      ClipKind.link => (Icons.link_rounded, c.cyan),
      ClipKind.image => (Icons.image_outlined, c.warning),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: DropClipSpacing.sm),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(DropClipSpacing.sm),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(DropClipRadius.button),
          ),
          child: Icon(icon, color: tint, size: 20),
        ),
        title: Text(clip.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('From ${clip.sourceDevice} · ${clip.age}',
            style: TextStyle(color: c.textSecondary)),
        trailing: IconButton(
          tooltip: 'Copy again',
          icon: const Icon(Icons.copy_rounded),
          onPressed: onCopy,
        ),
      ),
    );
  }
}

class _SuppressedNotice extends StatelessWidget {
  final int count;

  const _SuppressedNotice({required this.count});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final items = count == 1 ? '1 item' : '$count items';
    return Container(
      padding: const EdgeInsets.all(DropClipSpacing.md),
      decoration: BoxDecoration(
        color: c.elevated,
        borderRadius: BorderRadius.circular(DropClipRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, color: c.success, size: 18),
        const SizedBox(width: DropClipSpacing.sm),
        Expanded(
          child: Text(
            '$items from a password manager not synced — '
            'password-manager content never leaves this device',
            style: TextStyle(color: c.textSecondary),
          ),
        ),
      ]),
    );
  }
}
