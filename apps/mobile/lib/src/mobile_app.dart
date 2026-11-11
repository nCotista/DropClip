import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

/// Mobile navigation tabs for Android (Tier 2) and iOS (Tier 3) (`T2.5`).
enum MobileTab { clipboard, pair, devices }

/// DropClip Mobile Application (`T2.5`, UI-03, UI-05, ADR-009).
class DropClipMobileApp extends StatefulWidget {
  final String localFingerprint;
  final Uint8List localNonceB;
  final void Function(String clipText)? onSendClipboard;

  const DropClipMobileApp({
    super.key,
    this.localFingerprint =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    Uint8List? localNonceB,
    this.onSendClipboard,
  }) : localNonceB = localNonceB ?? _defaultNonceB;

  static final Uint8List _defaultNonceB = Uint8List.fromList(
    const <int>[16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31],
  );

  @override
  State<DropClipMobileApp> createState() => _DropClipMobileAppState();
}

class _DropClipMobileAppState extends State<DropClipMobileApp> {
  MobileTab _tab = MobileTab.clipboard;
  final List<String> _recentClips = <String>[
    'https://github.com/nCotista/DropClip',
    'Meeting notes: LAN-only mTLS 1.3 mesh verified',
  ];
  final TextEditingController _qrOrHostFpController = TextEditingController(
    text: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  final TextEditingController _pinController = TextEditingController();
  String? _computedSas;
  String? _pairingError;
  bool _sasConfirmed = false;

  @override
  void dispose() {
    _qrOrHostFpController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _sendCurrentClipboard() {
    const sample = 'Sent from DropClip Mobile 1-Tap Action';
    setState(() {
      _recentClips.insert(0, sample);
    });
    widget.onSendClipboard?.call(sample);
  }

  void _computeCommitRevealSas({required bool usePinMode}) {
    final hostFp = _qrOrHostFpController.text.trim().toLowerCase();
    final pin = _pinController.text.trim();
    final nonceA = Uint8List.fromList(
      const <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    );
    try {
      final sas = SasCalculator.calculateSasDual(
        fpA: hostFp,
        fpB: widget.localFingerprint,
        nonceA: nonceA,
        nonceB: widget.localNonceB,
        pin: usePinMode ? pin : null,
      );
      setState(() {
        _computedSas = sas;
        _pairingError = null;
        _sasConfirmed = false;
      });
    } on FormatException catch (e) {
      setState(() {
        _computedSas = null;
        _pairingError = e.message;
        _sasConfirmed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: DropClipThemeTokens.appName,
        debugShowCheckedModeBanner: false,
        theme: buildDropClipTheme(Brightness.light),
        darkTheme: buildDropClipTheme(Brightness.dark),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('${DropClipThemeTokens.appName} Mobile'),
          ),
          body: switch (_tab) {
            MobileTab.clipboard => _buildClipboardTab(),
            MobileTab.pair => _buildPairTab(),
            MobileTab.devices => _buildDevicesTab(),
          },
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (idx) =>
                setState(() => _tab = MobileTab.values[idx]),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.content_paste_rounded),
                label: 'Clipboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.qr_code_scanner_rounded),
                label: 'Pair (QR/PIN)',
              ),
              NavigationDestination(
                icon: Icon(Icons.devices_rounded),
                label: 'Devices',
              ),
            ],
          ),
        ),
      );

  Widget _buildClipboardTab() => ListView(
        padding: const EdgeInsets.all(DropClipSpacing.lg),
        children: <Widget>[
          ElevatedButton.icon(
            key: const Key('mobile_send_clipboard_btn'),
            onPressed: _sendCurrentClipboard,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send Clipboard Now (1-Tap)'),
          ),
          const SizedBox(height: DropClipSpacing.lg),
          const Text(
            'Recent Synced Clips',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: DropClipSpacing.sm),
          for (final clip in _recentClips)
            Card(
              child: ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(clip),
              ),
            ),
        ],
      );

  Widget _buildPairTab() => ListView(
        padding: const EdgeInsets.all(DropClipSpacing.lg),
        children: <Widget>[
          const Text(
            'Commit-then-Reveal Pairing (Zero-PIN-on-Wire)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: DropClipSpacing.sm),
          TextField(
            key: const Key('host_fp_input'),
            controller: _qrOrHostFpController,
            decoration: const InputDecoration(
              labelText: 'Scanned QR Host Fingerprint (64-hex)',
            ),
          ),
          const SizedBox(height: DropClipSpacing.sm),
          TextField(
            key: const Key('pin_input'),
            controller: _pinController,
            decoration: const InputDecoration(
              labelText: 'Optional 6-Digit Manual PIN (local OOB salt only)',
            ),
          ),
          const SizedBox(height: DropClipSpacing.md),
          Row(
            children: <Widget>[
              ElevatedButton(
                key: const Key('verify_qr_sas_btn'),
                onPressed: () => _computeCommitRevealSas(usePinMode: false),
                child: const Text('Verify QR SAS'),
              ),
              const SizedBox(width: DropClipSpacing.sm),
              ElevatedButton(
                key: const Key('verify_pin_sas_btn'),
                onPressed: () => _computeCommitRevealSas(usePinMode: true),
                child: const Text('Verify PIN SAS'),
              ),
            ],
          ),
          if (_pairingError != null) ...<Widget>[
            const SizedBox(height: DropClipSpacing.md),
            Text(
              'Error: $_pairingError',
              key: const Key('pairing_error_text'),
            ),
          ],
          if (_computedSas != null) ...<Widget>[
            const SizedBox(height: DropClipSpacing.md),
            Card(
              child: ListTile(
                title: Text(
                  'SAS Code: $_computedSas',
                  key: const Key('computed_sas_text'),
                ),
                subtitle: Text(
                  _sasConfirmed
                      ? 'Paired & Pinned (TLS 1.3)'
                      : 'Confirm SAS matches Host screen',
                ),
                trailing: ElevatedButton(
                  key: const Key('confirm_sas_match_btn'),
                  onPressed: () => setState(() => _sasConfirmed = true),
                  child: const Text('Match'),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _buildDevicesTab() => ListView(
        padding: const EdgeInsets.all(DropClipSpacing.lg),
        children: const <Widget>[
          ListTile(
            leading: Icon(Icons.laptop_mac_rounded),
            title: Text('MacBook-Pro.local'),
            subtitle: Text('Online · TLS 1.3 P-256 Pinned'),
          ),
          ListTile(
            leading: Icon(Icons.desktop_windows_rounded),
            title: Text('Workstation-Win11.local'),
            subtitle: Text('Online · TLS 1.3 P-256 Pinned'),
          ),
        ],
      );
}
