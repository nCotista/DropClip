import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'mobile_peer.dart';

export 'mobile_peer.dart';

/// Tier 2 phone screen (T2.5, UI-05): paired computers, pair by IP + PIN
/// with the SAS check, 1-tap clipboard send and received clips.
class DropClipMobileApp extends StatelessWidget {
  final MobilePeer node;
  final ValueListenable<List<String>> received;
  final Future<String?> Function() readClipboard;

  const DropClipMobileApp(
      {super.key,
      required this.node,
      required this.received,
      required this.readClipboard});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DropClip',
        theme: buildDropClipTheme(Brightness.light),
        darkTheme: buildDropClipTheme(Brightness.dark),
        home: _Home(app: this),
      );
}

class _Home extends StatelessWidget {
  final DropClipMobileApp app;

  const _Home({required this.app});

  Future<void> _send(BuildContext context) async {
    final text = await app.readClipboard();
    if (text == null || text.isEmpty) return;
    app.node.sendText(text);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sent')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('DropClip')),
        floatingActionButton: FloatingActionButton.extended(
            key: const Key('pair'),
            onPressed: () => showDialog<void>(
                context: context, builder: (_) => _PairDialog(app.node)),
            icon: const Icon(Icons.add_link),
            label: const Text('Pair with computer')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
              key: const Key('send-clipboard'),
              onPressed: () => _send(context),
              icon: const Icon(Icons.send),
              label: const Text('Send clipboard')),
          const SizedBox(height: 16),
          StreamBuilder<Set<String>>(
            stream: app.node.connectedChanges,
            initialData: app.node.connected,
            builder: (_, live) => ValueListenableBuilder<List<TrustedDevice>>(
              valueListenable: app.node.trusted,
              builder: (_, list, __) => Column(children: [
                if (list.isEmpty) const Text('No paired computers yet'),
                for (final d in list)
                  ListTile(
                      leading: const Icon(Icons.computer),
                      title: Text(d.name),
                      subtitle: Text(live.data?.contains(d.deviceId) ?? false
                          ? 'Connected'
                          : 'Offline')),
              ]),
            ),
          ),
          const Divider(),
          ValueListenableBuilder<List<String>>(
            valueListenable: app.received,
            builder: (_, clips, __) => Column(children: [
              for (final c in clips)
                ListTile(
                    leading: const Icon(Icons.content_paste), title: Text(c)),
            ]),
          ),
        ]),
      );
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
    setState(() => _result = '…');
    try {
      final d = await pair((sas, _) {
        if (!mounted) return Future.value(false);
        setState(() => _sas = sas);
        return (_answer = Completer<bool>()).future;
      });
      if (!mounted) return;
      setState(() => _result = 'Paired with ${d.name}');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _result = 'Pairing failed: $e');
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
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pair with computer'),
        content: _sas != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Does the computer show this number?'),
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
                        decoration:
                            const InputDecoration(labelText: 'Computer IP')),
                    TextField(
                        controller: _port,
                        decoration: const InputDecoration(labelText: 'Port')),
                    TextField(
                        key: const Key('pin'),
                        controller: _pin,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: 'PIN')),
                  ]),
        actions: [
          if (_sas != null) ...[
            TextButton(
                onPressed: () => _reply(false),
                child: const Text("Doesn't match")),
            FilledButton(
                key: const Key('match'),
                onPressed: () => _reply(true),
                child: const Text('Match')),
          ] else if (_result == null) ...[
            TextButton.icon(
                key: const Key('scan'),
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR')),
            FilledButton(
                key: const Key('go'),
                onPressed: _start,
                child: const Text('Pair')),
          ] else
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
        ],
      );
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
        appBar: AppBar(title: const Text('Scan the QR on your computer')),
        body: MobileScanner(onDetect: (capture) {
          final value = capture.barcodes.firstOrNull?.rawValue;
          if (value == null || _done) return;
          _done = true;
          Navigator.of(context).pop(value);
        }),
      );
}
