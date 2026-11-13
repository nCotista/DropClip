import 'dart:async';

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
typedef ReceivedClip = ({String from, String text});

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

  final ValueNotifier<MobileSettings> settings;

  const DropClipMobileApp({
    super.key,
    required this.node,
    required this.received,
    required this.readClipboard,
    required this.writeClipboard,
    required this.pickFile,
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
    return Scaffold(
      appBar: AppBar(title: const Text('DropClip'), actions: [
        IconButton(
            key: const Key('settings'),
            tooltip: t.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _SettingsPage(app: app)))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          key: const Key('pair'),
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => _PairDialog(app.node)),
          icon: const Icon(Icons.add_link),
          label: Text(t.pairWithComputer)),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                    key: const Key('send-clipboard'),
                    onPressed: () => _send(context),
                    icon: const Icon(Icons.send),
                    label: Text(t.sendClipboard)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                    key: const Key('send-file'),
                    onPressed: () => _sendFile(context),
                    icon: const Icon(Icons.attach_file),
                    label: Text(t.sendFile)),
              ),
            ]),
            const SizedBox(height: 16),
            StreamBuilder<Set<String>>(
              stream: app.node.connectedChanges,
              initialData: app.node.connected,
              builder: (_, live) => ValueListenableBuilder<List<TrustedDevice>>(
                valueListenable: app.node.trusted,
                builder: (_, list, __) => Column(children: [
                  if (list.isEmpty) Text(t.noPaired),
                  for (final d in list)
                    ListTile(
                      leading: const Icon(Icons.computer),
                      title: Text(d.name),
                      subtitle: Text(live.data?.contains(d.deviceId) ?? false
                          ? t.connected
                          : t.offline),
                      trailing: IconButton(
                          key: Key('remove-${d.deviceId}'),
                          tooltip: t.remove,
                          icon: const Icon(Icons.link_off),
                          onPressed: () => _forget(context, d)),
                    ),
                ]),
              ),
            ),
            const Divider(),
            ValueListenableBuilder<List<ReceivedClip>>(
              valueListenable: app.received,
              builder: (_, clips, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(t.received,
                              style: Theme.of(context).textTheme.titleSmall)),
                      if (clips.isNotEmpty)
                        TextButton.icon(
                            key: const Key('clear'),
                            onPressed: () => app.received.value = const [],
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(t.clear)),
                    ]),
                    if (clips.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(t.nothingYet,
                              style: Theme.of(context).textTheme.bodySmall)),
                    for (final c in clips)
                      ListTile(
                        leading: const Icon(Icons.content_paste),
                        title: Text(c.text,
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text(t.fromDevice(c.from)),
                        trailing: IconButton(
                          tooltip: t.copyAgain,
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () async {
                            await app.writeClipboard(c.text);
                            if (context.mounted) _toast(context, t.copied);
                          },
                        ),
                      ),
                  ]),
            ),
          ]),
    );
  }
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
          ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text(t.thisPhone),
              subtitle: Text(app.node.myName)),
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
