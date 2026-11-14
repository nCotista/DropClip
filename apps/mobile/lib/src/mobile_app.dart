import 'dart:async';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'mobile_peer.dart';
import 'mobile_settings.dart';
import 'mobile_strings.dart';

export 'mobile_peer.dart';
export 'mobile_settings.dart';

/// A clip received from a computer, newest first in the list.
/// A clip or file received from a computer, newest first in the list.
/// [path] is set for a received file or image: the row opens it.
typedef ReceivedClip = ({String from, String text, String? path});

/// Tier 2 phone screen (T2.5, UI-05): paired computers, pair by IP + PIN
/// or QR with the SAS check, send the clipboard or a file, received clips
/// with copy again, and Settings.
class DropClipMobileApp extends StatelessWidget {
  final MobilePeer node;
  final ValueNotifier<List<ReceivedClip>> received;
  final Future<String?> Function() readClipboard;

  /// Puts text back on the phone clipboard (copy again).
  final Future<void> Function(String text) writeClipboard;

  /// Lets the user choose a file; null when cancelled.
  final Future<String?> Function() pickFile;

  /// Opens a received file in the phone's app for it.
  final Future<void> Function(String path) openFile;

  final ValueNotifier<MobileSettings> settings;

  const DropClipMobileApp({
    super.key,
    required this.node,
    required this.received,
    required this.readClipboard,
    required this.writeClipboard,
    required this.pickFile,
    required this.openFile,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MobileSettings>(
        valueListenable: settings,
        builder: (_, s, __) => MobileStringsScope(
          strings: MobileStrings(s.language == 'th'),
          child: MaterialApp(
            title: 'DropClip',
            theme: buildDropClipTheme(Brightness.light),
            darkTheme: buildDropClipTheme(Brightness.dark),
            builder: (context, child) => MobileStringsScope(
                strings: MobileStrings(s.language == 'th'), child: child!),
            home: _Home(app: this),
          ),
        ),
      );
}

class _Home extends StatelessWidget {
  final DropClipMobileApp app;

  const _Home({required this.app});

  void _toast(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send(BuildContext context) async {
    final t = MobileStrings.of(context);
    if (!app.settings.value.syncEnabled) return _toast(context, t.syncOff);
    final text = await app.readClipboard();
    if (text == null || text.isEmpty) return;
    app.node.sendText(text);
    if (context.mounted) _toast(context, t.sent);
  }

  Future<void> _sendFile(BuildContext context) async {
    final t = MobileStrings.of(context);
    final online = [
      for (final d in app.node.trusted.value)
        if (app.node.connected.contains(d.deviceId)) d
    ];
    if (online.isEmpty) return _toast(context, t.noComputerOnline);
    final to = online.length == 1
        ? online.single
        : await showDialog<TrustedDevice>(
            context: context,
            builder: (_) => SimpleDialog(title: Text(t.sendTo), children: [
                  for (final d in online)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, d),
                        child: Text(d.name)),
                ]));
    if (to == null || !context.mounted) return;
    final path = await app.pickFile();
    if (path == null || !context.mounted) return;
    final name = path.split(RegExp(r'[\\/]')).last;
    var shown = -1;
    try {
      await app.node.sendFile(to.deviceId, path, onProgress: (sent, total) {
        final pct = total == 0 ? 100 : sent * 100 ~/ total;
        if (pct ~/ 10 != shown ~/ 10) {
          shown = pct;
          _toast(context, t.sending(name, pct));
        }
      });
      if (context.mounted) _toast(context, t.sentFile(name));
    } on Object catch (e) {
      if (context.mounted) _toast(context, t.sendFailed('$e'));
    }
  }

  Future<void> _forget(BuildContext context, TrustedDevice d) async {
    final t = MobileStrings.of(context);
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              content: Text(t.removeQuestion(d.name)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t.cancel)),
                FilledButton(
                    key: const Key('confirm-remove'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t.remove)),
              ],
            ));
    if (ok == true) await app.node.forget(d.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final t = MobileStrings.of(context);
    final c = DropClipColors.of(context);
    void pair() => showDialog<void>(
        context: context, builder: (_) => _PairDialog(app.node));
    return StreamBuilder<Set<String>>(
      stream: app.node.connectedChanges,
      initialData: app.node.connected,
      builder: (_, live) => ValueListenableBuilder<List<TrustedDevice>>(
        valueListenable: app.node.trusted,
        builder: (_, devices, __) {
          final online = [
            for (final d in devices)
              if (live.data?.contains(d.deviceId) ?? false) d
          ];
          return Scaffold(
            appBar: AppBar(title: const Text('DropClip'), actions: [
              if (devices.isNotEmpty)
                IconButton(
                    key: const Key('pair'),
                    tooltip: t.pairWithComputer,
                    icon: const Icon(Icons.add_link),
                    onPressed: pair),
              IconButton(
                  key: const Key('settings'),
                  tooltip: t.settings,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => _SettingsPage(app: app)))),
            ]),
            body: ListView(
              padding: const EdgeInsets.all(DropClipSpacing.lg),
              children: [
                _StatusCard(
                  title: devices.isEmpty
                      ? t.statusNoPair
                      : online.isEmpty
                          ? t.statusOffline
                          : t.statusConnected(online.first.name),
                  hint: devices.isEmpty
                      ? t.statusNoPairHint
                      : online.isEmpty
                          ? t.statusOfflineHint
                          : t.statusConnectedHint,
                  live: online.isNotEmpty,
                  action: devices.isEmpty
                      ? FilledButton.icon(
                          key: const Key('pair'),
                          style: FilledButton.styleFrom(
                              backgroundColor: c.onAccent,
                              foregroundColor: c.accent),
                          onPressed: pair,
                          icon: const Icon(Icons.add_link),
                          label: Text(t.pairWithComputer))
                      : null,
                ),
                const SizedBox(height: DropClipSpacing.md),
                Row(children: [
                  Expanded(
                      child: _ActionTile(
                          key: const Key('send-clipboard'),
                          icon: Icons.content_paste_go_rounded,
                          label: t.sendClipboard,
                          onTap: () => _send(context))),
                  const SizedBox(width: DropClipSpacing.md),
                  Expanded(
                      child: _ActionTile(
                          key: const Key('send-file'),
                          icon: Icons.upload_file_rounded,
                          label: t.sendFile,
                          onTap: () => _sendFile(context))),
                ]),
                if (devices.isNotEmpty) ...[
                  _Section(t.computers),
                  for (final d in devices)
                    Card(
                      margin: const EdgeInsets.only(bottom: DropClipSpacing.sm),
                      child: ListTile(
                        leading: Stack(clipBehavior: Clip.none, children: [
                          Icon(Icons.laptop_windows_rounded,
                              color: c.textSecondary),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: online.contains(d)
                                    ? c.success
                                    : c.textTertiary,
                                border: Border.all(color: c.surface, width: 2),
                              ),
                            ),
                          ),
                        ]),
                        title: Text(d.name),
                        subtitle: Text(
                            online.contains(d) ? t.connected : t.offline,
                            style: TextStyle(
                                color: online.contains(d)
                                    ? c.success
                                    : c.textSecondary)),
                        trailing: IconButton(
                            key: Key('remove-${d.deviceId}'),
                            tooltip: t.remove,
                            icon: const Icon(Icons.link_off),
                            onPressed: () => _forget(context, d)),
                      ),
                    ),
                ],
                ValueListenableBuilder<List<ReceivedClip>>(
                  valueListenable: app.received,
                  builder: (_, clips, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(t.received,
                            trailing: clips.isEmpty
                                ? null
                                : TextButton.icon(
                                    key: const Key('clear'),
                                    onPressed: () =>
                                        app.received.value = const [],
                                    icon: const Icon(
                                        Icons.delete_sweep_outlined,
                                        size: 18),
                                    label: Text(t.clear))),
                        if (clips.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: DropClipSpacing.xl),
                            child: Column(children: [
                              Icon(Icons.inbox_rounded,
                                  size: 40, color: c.textTertiary),
                              const SizedBox(height: DropClipSpacing.sm),
                              Text(t.nothingYet,
                                  style: TextStyle(color: c.textSecondary)),
                            ]),
                          ),
                        for (final clip in clips)
                          if (clip.path != null)
                            Card(
                              margin: const EdgeInsets.only(
                                  bottom: DropClipSpacing.sm),
                              child: ListTile(
                                key: Key('file-${clip.text}'),
                                onTap: () => app.openFile(clip.path!),
                                leading: _isImage(clip.path!)
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            DropClipRadius.tag),
                                        child: Image.file(File(clip.path!),
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                                Icons.image_outlined,
                                                color: c.warning)))
                                    : Icon(Icons.insert_drive_file_outlined,
                                        color: c.warning),
                                title: Text(clip.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(t.fromDevice(clip.from),
                                    style: TextStyle(color: c.textSecondary)),
                                trailing: IconButton(
                                  tooltip: t.openFile,
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  onPressed: () => app.openFile(clip.path!),
                                ),
                              ),
                            )
                          else
                            Card(
                              margin: const EdgeInsets.only(
                                  bottom: DropClipSpacing.sm),
                              child: ListTile(
                                onTap: () => _copy(context, clip.text),
                                leading: Icon(
                                    _isLink(clip.text)
                                        ? Icons.link_rounded
                                        : Icons.notes_rounded,
                                    color: _isLink(clip.text)
                                        ? c.cyan
                                        : c.textAccent),
                                title: Text(clip.text,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(t.fromDevice(clip.from),
                                    style: TextStyle(color: c.textSecondary)),
                                trailing: IconButton(
                                  tooltip: t.copyAgain,
                                  icon: const Icon(Icons.copy_rounded),
                                  onPressed: () => _copy(context, clip.text),
                                ),
                              ),
                            ),
                      ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await app.writeClipboard(text);
    if (context.mounted) _toast(context, MobileStrings.of(context).copied);
  }

  static bool _isImage(String path) =>
      RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false)
          .hasMatch(path);

  static bool _isLink(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }
}

/// The big card on top: are we connected, and what to do next.
class _StatusCard extends StatelessWidget {
  final String title, hint;
  final bool live;
  final Widget? action;

  const _StatusCard(
      {required this.title,
      required this.hint,
      required this.live,
      this.action});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    return Container(
      padding: const EdgeInsets.all(DropClipSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DropClipRadius.window),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: live
              ? [c.accent, Color.lerp(c.accent, c.cyan, 0.55)!]
              : [c.accent, Color.lerp(c.accent, Colors.black, 0.25)!],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(live ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded,
              color: c.onAccent),
          const SizedBox(width: DropClipSpacing.sm),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: c.onAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: DropClipSpacing.xs),
        Text(hint, style: TextStyle(color: c.onAccent.withValues(alpha: 0.85))),
        if (action != null) ...[
          const SizedBox(height: DropClipSpacing.md),
          action!,
        ],
      ]),
    );
  }
}

/// A large square button for the two main actions.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DropClipRadius.card),
          side: BorderSide(color: c.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(DropClipRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DropClipSpacing.xl),
          child: Column(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: c.accent.withValues(alpha: 0.15),
              child: Icon(icon, color: c.textAccent),
            ),
            const SizedBox(height: DropClipSpacing.sm),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _Section(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
            top: DropClipSpacing.xl, bottom: DropClipSpacing.sm),
        child: Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: DropClipColors.of(context).textTertiary)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class _SettingsPage extends StatelessWidget {
  final DropClipMobileApp app;

  const _SettingsPage({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = MobileStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ValueListenableBuilder<MobileSettings>(
        valueListenable: app.settings,
        builder: (_, s, __) => ListView(children: [
          StatefulBuilder(
            builder: (context, setTile) => ListTile(
              key: const Key('phone-name'),
              leading: const Icon(Icons.smartphone),
              title: Text(t.phoneName),
              subtitle: Text(app.node.myName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final name = await showDialog<String>(
                    context: context,
                    builder: (_) => _RenameDialog(current: app.node.myName));
                if (name == null || name == app.node.myName) return;
                await app.node.rename(name);
                setTile(() {});
              },
            ),
          ),
          SwitchListTile(
              key: const Key('sync-switch'),
              secondary: const Icon(Icons.sync),
              title: Text(t.syncClipboard),
              subtitle: Text(t.syncHint),
              value: s.syncEnabled,
              onChanged: (v) => app.settings.value =
                  app.settings.value.copyWith(syncEnabled: v)),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(t.language),
            trailing: SegmentedButton<String>(
              key: const Key('language'),
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'th', label: Text('ไทย')),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => app.settings.value =
                  app.settings.value.copyWith(language: v.single),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String current;

  const _RenameDialog({required this.current});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final name = _text.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final t = MobileStrings.of(context);
    return AlertDialog(
      title: Text(t.phoneName),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            key: const Key('rename-field'),
            controller: _text,
            autofocus: true,
            maxLength: 64,
            onSubmitted: (_) => _save()),
        Text(t.phoneNameHint, style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
            key: const Key('rename-save'),
            onPressed: _save,
            child: Text(t.save)),
      ],
    );
  }
}

class _PairDialog extends StatefulWidget {
  final MobilePeer node;

  const _PairDialog(this.node);

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '53317');
  final _pin = TextEditingController();
  String? _sas, _result;
  Completer<bool>? _answer;

  @override
  void dispose() {
    final answer = _answer;
    _answer = null;
    if (answer != null && !answer.isCompleted) answer.complete(false);
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _start() => _run((confirm) => widget.node.pair(_host.text.trim(),
      int.tryParse(_port.text) ?? 53317, _pin.text.trim(), confirm));

  /// Scans the desktop's pairing QR (§5.3) and pairs from it.
  Future<void> _scan() async {
    final scanned = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (scanned != null) {
      await _run((confirm) => widget.node.pairWithQr(scanned, confirm));
    }
  }

  Future<void> _run(
      Future<TrustedDevice> Function(
              Future<bool> Function(String sas, String hostName) confirm)
          pair) async {
    if (!mounted) return;
    final t = MobileStrings.of(context);
    setState(() => _result = '…');
    try {
      final d = await pair((sas, _) {
        if (!mounted) return Future.value(false);
        setState(() => _sas = sas);
        return (_answer = Completer<bool>()).future;
      });
      if (!mounted) return;
      setState(() => _result = t.pairedWith(d.name));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _result = t.pairFailed('$e'));
    }
  }

  void _reply(bool match) {
    final answer = _answer;
    if (!mounted || answer == null || answer.isCompleted) return;
    _answer = null;
    answer.complete(match);
    setState(() => _sas = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = MobileStrings.of(context);
    return AlertDialog(
      title: Text(t.pairWithComputer),
      content: _sas != null
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t.sasQuestion),
              Text(_sas!,
                  key: const Key('sas'),
                  style: Theme.of(context).textTheme.displaySmall),
            ])
          : _result != null
              ? Text(_result!, key: const Key('result'))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      key: const Key('host'),
                      controller: _host,
                      decoration: InputDecoration(labelText: t.computerIp)),
                  TextField(
                      controller: _port,
                      decoration: InputDecoration(labelText: t.port)),
                  TextField(
                      key: const Key('pin'),
                      controller: _pin,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'PIN')),
                ]),
      actions: [
        if (_sas != null) ...[
          TextButton(onPressed: () => _reply(false), child: Text(t.noMatch)),
          FilledButton(
              key: const Key('match'),
              onPressed: () => _reply(true),
              child: Text(t.match)),
        ] else if (_result == null) ...[
          TextButton.icon(
              key: const Key('scan'),
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(t.scanQr)),
          FilledButton(
              key: const Key('go'), onPressed: _start, child: Text(t.pair)),
        ] else
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(t.close)),
      ],
    );
  }
}

/// Camera view that returns the first QR code it reads.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(MobileStrings.of(context).scanTitle)),
        body: MobileScanner(onDetect: (capture) {
          final value = capture.barcodes.firstOrNull?.rawValue;
          if (value == null || _done) return;
          _done = true;
          Navigator.of(context).pop(value);
        }),
      );
}
