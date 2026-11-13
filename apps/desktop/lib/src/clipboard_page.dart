import 'dart:io';

import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clipboard_aside.dart';
import 'demo_data.dart';
import 'l10n/strings.dart';

/// The command that opens [path] in its default app, or with [reveal]
/// shows it selected in its folder. Explorer needs backslashes: given
/// `C:\Users\me/Downloads/x.pdf` it silently opens Documents instead.
(String, List<String>) openCommand(String path,
    {required bool reveal, required bool macOS}) {
  if (macOS) return ('open', [if (reveal) '-R', path]);
  final win = path.replaceAll('/', r'\');
  // Separate args: a name with spaces gets quoted on its own
  // (`/select, "C:\a b.pdf"`); quoting `/select,...` as one breaks it.
  return ('explorer.exe', [if (reveal) '/select,', win]);
}

/// Opens [path] in its default app, or shows it in its folder.
Future<void> openWithSystem(String path, {bool reveal = false}) {
  final (exe, args) =
      openCommand(path, reveal: reveal, macOS: Platform.isMacOS);
  return Process.run(exe, args);
}

/// Below this page width the [ClipboardAside] is hidden.
const double asideMinPageWidth = 900;

/// Clipboard home screen from the UI design (T1.12, FR-04, FR-05, SF-03).
class ClipboardPage extends StatefulWidget {
  final ShellStatus status;

  /// Re-copies a clip into the local clipboard. Defaults to the system
  /// clipboard for text; images need the native watcher (T1.6/T1.7).
  final ValueChanged<ClipItem>? onCopy;
  final VoidCallback? onSendClipboard;
  final VoidCallback? onPair;
  final VoidCallback? onOpenDropzone;
  final VoidCallback? onLinkWeb;

  /// Opens a received file ([reveal]: show it in its folder); defaults to
  /// the OS (tests pass their own).
  final void Function(String path, {bool reveal})? onOpenFile;

  const ClipboardPage({
    super.key,
    required this.status,
    this.onCopy,
    this.onSendClipboard,
    this.onPair,
    this.onOpenDropzone,
    this.onLinkWeb,
    this.onOpenFile,
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
        .showSnackBar(SnackBar(content: Text(Strings.of(context).copied)));
  }

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final t = Strings.of(context);
    final s = widget.status;
    final clips = _visible;
    final list = ListView(
      padding: const EdgeInsets.all(DropClipSpacing.xxl),
      children: [
        Wrap(
          spacing: DropClipSpacing.lg,
          runSpacing: DropClipSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.clipboard,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(t.liveSyncAcross(s.verifiedDevices),
                  style: TextStyle(color: c.textSecondary)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t.autoSync, style: TextStyle(color: c.textSecondary)),
              Switch(
                value: _autoSync,
                onChanged: (v) => setState(() => _autoSync = v),
              ),
            ]),
            FilledButton.icon(
              onPressed: widget.onSendClipboard,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(t.sendClipboard),
            ),
          ],
        ),
        const SizedBox(height: DropClipSpacing.xl),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: t.searchClips,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: DropClipSpacing.lg),
        Wrap(spacing: DropClipSpacing.sm, children: [
          for (final (label, kind) in [
            (t.all, null),
            (t.text, ClipKind.text),
            (t.links, ClipKind.link),
            (t.images, ClipKind.image),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _filter == kind,
              onSelected: (_) => setState(() => _filter = kind),
            ),
        ]),
        const SizedBox(height: DropClipSpacing.xl),
        Text(t.recentHeader,
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
                Text(t.noClipsMatch, style: TextStyle(color: c.textTertiary)),
          ),
        for (final clip in clips)
          _ClipTile(
            clip: clip,
            onCopy: () => _copy(clip),
            onOpen: clip.path == null
                ? null
                : () => (widget.onOpenFile ?? openWithSystem)(clip.path!),
            onReveal: clip.path == null
                ? null
                : () => (widget.onOpenFile ?? openWithSystem)(clip.path!,
                    reveal: true),
          ),
        if (s.suppressedClips > 0) ...[
          const SizedBox(height: DropClipSpacing.md),
          _SuppressedNotice(count: s.suppressedClips),
        ],
      ],
    );
    // The side panel drops out on narrow windows so the list stays usable.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < asideMinPageWidth
          ? list
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: list),
              Container(
                width: 300,
                decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: c.border))),
                child: ClipboardAside(
                  status: s,
                  onPair: widget.onPair,
                  onOpenDropzone: widget.onOpenDropzone,
                  onLinkWeb: widget.onLinkWeb,
                ),
              ),
            ]),
    );
  }
}

class _ClipTile extends StatelessWidget {
  final ClipItem clip;
  final VoidCallback onCopy;

  /// Set for a received file: the row opens it.
  final VoidCallback? onOpen;

  /// Set for a received file: shows it in its folder.
  final VoidCallback? onReveal;

  const _ClipTile(
      {required this.clip, required this.onCopy, this.onOpen, this.onReveal});

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
        subtitle: Text(
            Strings.of(context).fromDevice(clip.sourceDevice, clip.age),
            style: TextStyle(color: c.textSecondary)),
        onTap: onOpen,
        trailing: onOpen != null
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: const Key('clip-open-file'),
                  tooltip: Strings.of(context).openFile,
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: onOpen,
                ),
                IconButton(
                  key: const Key('clip-show-in-folder'),
                  tooltip: Strings.of(context).showInFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                  onPressed: onReveal,
                ),
              ])
            : IconButton(
                tooltip: Strings.of(context).copyAgain,
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
          child: Text(Strings.of(context).suppressed(count),
              style: TextStyle(color: c.textSecondary)),
        ),
      ]),
    );
  }
}
