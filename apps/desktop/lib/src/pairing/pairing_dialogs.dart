import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/strings.dart';

/// Host side of UI-03: shows the PIN, then the SAS for the user to compare.
class HostPairingDialog extends StatefulWidget {
  /// Opens a session; returns the PIN and the address to show.
  final Future<({String pin, String address, String qr})> Function() open;
  final Stream<PairingHostEvent> events;
  final void Function(bool match) confirm;

  const HostPairingDialog(
      {super.key,
      required this.open,
      required this.events,
      required this.confirm});

  @override
  State<HostPairingDialog> createState() => _HostPairingDialogState();
}

class _HostPairingDialogState extends State<HostPairingDialog> {
  ({String pin, String address, String qr})? _session;
  String? _sas, _result;
  bool _answered = false;
  StreamSubscription<PairingHostEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.events.listen((e) => setState(() {
          switch (e) {
            case PairingSasReady(:final sas):
              _sas = sas;
            case PairingCompleted(:final device):
              _result = Strings.of(context).pairedWith(device.name);
            case PairingFailed(:final code):
              _result = Strings.of(context).pairFailed(code);
          }
        }));
    widget.open().then((s) {
      if (mounted) setState(() => _session = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _answer(bool match) {
    widget.confirm(match);
    setState(() => _answered = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final s = _session;
    return AlertDialog(
      title: Text(t.pairNewDevice),
      content: _result != null
          ? Text(_result!, key: const Key('pair-result'))
          : _sas != null
              ? _SasPrompt(sas: _sas!, waiting: _answered)
              : s == null
                  ? const LinearProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      // §5.3: the phone scans this; level M.
                      SizedBox.square(
                        dimension: 180,
                        child: QrImageView(
                            key: const Key('pair-qr'),
                            data: s.qr,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                            backgroundColor: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(t.pinOnOtherDevice),
                      const SizedBox(height: 16),
                      _BigCode(s.pin, key: const Key('pair-pin')),
                      Text(s.address),
                    ]),
      actions: [
        if (_sas != null && !_answered && _result == null) ...[
          TextButton(
              key: const Key('sas-no'),
              onPressed: () => _answer(false),
              child: Text(t.sasNoMatch)),
          FilledButton(
              key: const Key('sas-yes'),
              onPressed: () => _answer(true),
              child: Text(t.sasMatch)),
        ] else
          TextButton(
              onPressed: () {
                if (_result == null) widget.confirm(false);
                Navigator.of(context).pop();
              },
              child: Text(MaterialLocalizations.of(context).closeButtonLabel)),
      ],
    );
  }
}

/// Client side of UI-03: type the Host's PIN, then compare the SAS.
class ClientPairingDialog extends StatefulWidget {
  final String peerName;

  /// Runs the pairing; `confirm` resolves when the user answers the SAS.
  final Future<TrustedDevice> Function(String pin,
      Future<bool> Function(String sas, String hostName) confirm) pair;

  const ClientPairingDialog(
      {super.key, required this.peerName, required this.pair});

  @override
  State<ClientPairingDialog> createState() => _ClientPairingDialogState();
}

class _ClientPairingDialogState extends State<ClientPairingDialog> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _sas, _result;
  Completer<bool>? _answer;

  @override
  void dispose() {
    _pin.dispose();
    if (_answer?.isCompleted == false) _answer!.complete(false);
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final t = Strings.of(context);
    String result;
    try {
      final d = await widget.pair(_pin.text.trim(), (sas, _) {
        setState(() => _sas = sas);
        return (_answer = Completer<bool>()).future;
      });
      result = t.pairedWith(d.name);
    } on PairingClientException catch (e) {
      result = t.pairFailed(e.code);
    } on Object catch (e) {
      result = t.pairFailed('$e');
    }
    if (mounted) setState(() => _result = result);
  }

  void _reply(bool match) {
    _answer?.complete(match);
    setState(() => _answer = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final asking = _answer != null && !_answer!.isCompleted;
    return AlertDialog(
      title: Text(t.pair),
      content: _result != null
          ? Text(_result!, key: const Key('pair-result'))
          : _sas != null
              ? _SasPrompt(sas: _sas!, waiting: !asking)
              : _busy
                  ? const LinearProgressIndicator()
                  : TextField(
                      key: const Key('pin-field'),
                      controller: _pin,
                      autofocus: true,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: t.enterPinOf(widget.peerName)),
                      onSubmitted: (_) => _start(),
                    ),
      actions: [
        if (asking) ...[
          TextButton(
              key: const Key('sas-no'),
              onPressed: () => _reply(false),
              child: Text(t.sasNoMatch)),
          FilledButton(
              key: const Key('sas-yes'),
              onPressed: () => _reply(true),
              child: Text(t.sasMatch)),
        ] else if (!_busy)
          FilledButton(
              key: const Key('pin-submit'),
              onPressed: _start,
              child: Text(t.pair)),
        if (!asking)
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel)),
      ],
    );
  }
}

class _SasPrompt extends StatelessWidget {
  final String sas;
  final bool waiting;

  const _SasPrompt({required this.sas, required this.waiting});

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(t.sasQuestion),
      const SizedBox(height: 16),
      _BigCode(sas, key: const Key('pair-sas')),
      if (waiting) Text(t.waitingForPeer),
    ]);
  }
}

/// `123 456` in large digits.
class _BigCode extends StatelessWidget {
  final String code;

  const _BigCode(this.code, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        code.length == 6
            ? '${code.substring(0, 3)} ${code.substring(3)}'
            : code,
        style: Theme.of(context)
            .textTheme
            .displaySmall
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 4),
      );
}
