import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';
import 'l10n/strings.dart';

/// Live record of a desktop streaming file transfer (T1.10, T1.11).
class DesktopTransferRecord {
  final String id;
  final String fileName;
  final String peerName;
  final int totalBytes;
  final int transferredBytes;
  final bool resumablePart;
  final bool completed;

  const DesktopTransferRecord({
    required this.id,
    required this.fileName,
    required this.peerName,
    required this.totalBytes,
    required this.transferredBytes,
    this.resumablePart = false,
    this.completed = false,
  });

  double get progress =>
      totalBytes <= 0 ? 1.0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);
}

/// Interactive Transfers page for the Desktop app (T1.10, T1.11).
class DesktopTransfersPage extends StatelessWidget {
  final List<DesktopTransferRecord> transfers;
  final VoidCallback onSendSampleFile;
  final VoidCallback onOpenDropzone;
  final ValueChanged<String> onResumeTransfer;

  const DesktopTransfersPage({
    super.key,
    required this.transfers,
    required this.onSendSampleFile,
    required this.onOpenDropzone,
    required this.onResumeTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final t = Strings.of(context);
    return ListView(
      padding: const EdgeInsets.all(DropClipSpacing.xxl),
      children: [
        Wrap(
          spacing: DropClipSpacing.lg,
          runSpacing: DropClipSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              t.transfers,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            FilledButton.icon(
              key: const Key('btn-desktop-send-sample'),
              onPressed: onSendSampleFile,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Stream Sample File (1 MiB Chunks)'),
            ),
            OutlinedButton.icon(
              key: const Key('btn-desktop-open-dropzone'),
              onPressed: onOpenDropzone,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(t.dropFiles),
            ),
          ],
        ),
        const SizedBox(height: DropClipSpacing.md),
        Text(
          'TLS 1.3 Data Plane · 1 MiB Chunk Streaming · '
          '64 MiB Resumable Checkpoints (transfers.json)',
          style: TextStyle(color: c.textSecondary),
        ),
        const SizedBox(height: DropClipSpacing.xl),
        for (final item in transfers)
          Card(
            margin: const EdgeInsets.only(bottom: DropClipSpacing.md),
            child: Padding(
              padding: const EdgeInsets.all(DropClipSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.completed
                            ? Icons.check_circle_rounded
                            : Icons.downloading_rounded,
                        color: item.completed ? c.success : c.accent,
                      ),
                      const SizedBox(width: DropClipSpacing.sm),
                      Expanded(
                        child: Text(
                          item.fileName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${(item.progress * 100).toStringAsFixed(0)}%',
                        style: dropClipMono(context, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: DropClipSpacing.sm),
                  LinearProgressIndicator(value: item.progress),
                  const SizedBox(height: DropClipSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Peer: ${item.peerName} · '
                          '${item.completed ? "SHA-256 Verified" : "Paused"}',
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ),
                      if (item.resumablePart && !item.completed)
                        TextButton.icon(
                          key: Key('btn-desktop-resume-${item.id}'),
                          onPressed: () => onResumeTransfer(item.id),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Resume .part (T1.11)'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Interactive Devices & Revocation page for Desktop (T1.2, T1.3, T1.12).
class DesktopDevicesPage extends StatefulWidget {
  final List<NearbyDevice> nearby;
  final PairingEngine? pairingEngine;
  final VoidCallback? onDeviceVerified;

  const DesktopDevicesPage({
    super.key,
    required this.nearby,
    this.pairingEngine,
    this.onDeviceVerified,
  });

  @override
  State<DesktopDevicesPage> createState() => _DesktopDevicesPageState();
}

class _DesktopDevicesPageState extends State<DesktopDevicesPage> {
  static const String _defaultHostFp =
      '0000000000000000000000000000000000000000000000000000000000000000';
  static const String _defaultClientFp =
      '1111111111111111111111111111111111111111111111111111111111111111';

  final TextEditingController _pinController =
      TextEditingController(text: '123456');
  late final PairingEngine _engine;
  String? _activePairId;
  String _sasCode = '639589';
  bool _peerConfirmed = false;
  final Map<String, String> _trustState = {
    'Pixel 8': 'trusted',
    'Surface Laptop': 'trusted',
    'iPhone 15': 'quarantined',
  };

  @override
  void initState() {
    super.initState();
    _engine = widget.pairingEngine ?? _buildDefaultEngine();
    _runCommitRevealSession();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  static PairingEngine _buildDefaultEngine() {
    final hostIdentity = DeviceIdentity(
      deviceId: '00000000-0000-4000-8000-000000000001',
      name: 'Desktop-Host',
      os: 'macos',
      certDer: Uint8List(0),
      certPem: Uint8List(0),
      fp: _defaultHostFp,
      createdAt: 1700000000000,
    );
    final store = TrustedDeviceStore(
      storageDir: Directory.systemTemp,
      keyStore: InMemorySecureKeyStore(),
    );
    return PairingEngine(hostIdentity: hostIdentity, trustedStore: store);
  }

  void _runCommitRevealSession() {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return;
    final nonceA = Uint8List.fromList(ascii.encode('0123456789abcdef'));
    final nonceB = Uint8List.fromList(ascii.encode('fedcba9876543210'));

    _engine.startSession(
      hostIp: '192.168.1.24',
      hostPort: 53317,
      nonceAOverride: nonceA,
      pinOverride: pin,
    );
    final commitB = SasCalculator.createCommitment(nonceB, _defaultClientFp);
    final reqResp = _engine.handlePairRequest(
      <String, dynamic>{
        'v': ProtocolConstants.protocolVersion,
        'min_supported_v': ProtocolConstants.minSupportedProtocolVersion,
        'device_id': '00000000-0000-4000-8000-000000000002',
        'name': 'Mobile-Client',
        'os': 'android',
        'tier': 2,
        'fp': _defaultClientFp,
        'method': 'pin',
        'commitment_B': commitB,
      },
      clientIp: '192.168.1.30',
    );
    final pairId = reqResp['pair_id'] as String;
    _engine.handlePairConfirm(
      <String, dynamic>{
        'pair_id': pairId,
        'nonce_B': base64Encode(nonceB),
      },
      clientIp: '192.168.1.30',
    );
    setState(() {
      _activePairId = pairId;
      _sasCode = _engine.currentSasCode ?? '639589';
    });
  }

  Future<void> _confirmSasMatch() async {
    final pairId = _activePairId;
    if (pairId != null && _engine.state == PairingState.awaitingSas) {
      await _engine.handlePairFinalize(
        <String, dynamic>{'pair_id': pairId, 'result': 'match'},
        clientIp: '192.168.1.30',
        hostUserConfirmedMatch: true,
      );
    }
    if (!mounted) return;
    setState(() => _peerConfirmed = true);
    widget.onDeviceVerified?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final t = Strings.of(context);
    return ListView(
      padding: const EdgeInsets.all(DropClipSpacing.xxl),
      children: [
        Text(
          t.devices,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: DropClipSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(DropClipSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zero-PIN-on-Wire Pairing Host (T1.3 · ADR-009)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: DropClipSpacing.sm),
                Text(
                  'Enter the 6-digit PIN on your mobile/peer device and '
                  'confirm that both screens show the same 6-digit SAS code.',
                  style: TextStyle(color: c.textSecondary),
                ),
                const SizedBox(height: DropClipSpacing.md),
                Wrap(
                  spacing: DropClipSpacing.lg,
                  runSpacing: DropClipSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        key: const Key('input-desktop-pin'),
                        controller: _pinController,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: '6-Digit OOB PIN',
                          counterText: '',
                        ),
                        onChanged: (_) => _runCommitRevealSession(),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DropClipSpacing.lg,
                        vertical: DropClipSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: c.elevated,
                        borderRadius:
                            BorderRadius.circular(DropClipRadius.card),
                      ),
                      child: Text(
                        'SAS: $_sasCode',
                        key: const Key('text-desktop-sas'),
                        style: dropClipMono(context, fontSize: 20).copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.cyan,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('btn-desktop-confirm-sas'),
                      onPressed: _confirmSasMatch,
                      icon: const Icon(Icons.verified_user_rounded, size: 18),
                      label: const Text('Confirm SAS Match'),
                    ),
                  ],
                ),
                if (_peerConfirmed) ...[
                  const SizedBox(height: DropClipSpacing.sm),
                  Text(
                    'Peer pinned in Trusted Peer Store (TLS 1.3 SPKI SHA-256).',
                    style: TextStyle(color: c.success),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: DropClipSpacing.xl),
        Text(
          'TRUSTED CLUSTER & QUARANTINE-THEN-CONFIRM REVOCATION (T1.12)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: DropClipSpacing.sm),
        for (final entry in _trustState.entries)
          Card(
            margin: const EdgeInsets.only(bottom: DropClipSpacing.sm),
            child: ListTile(
              leading: Icon(
                entry.value == 'trusted'
                    ? Icons.verified_rounded
                    : entry.value == 'quarantined'
                        ? Icons.warning_amber_rounded
                        : Icons.block_rounded,
                color: entry.value == 'trusted'
                    ? c.success
                    : entry.value == 'quarantined'
                        ? c.warning
                        : c.danger,
              ),
              title: Text(entry.key),
              subtitle: Text('Status: ${entry.value.toUpperCase()}'),
              trailing: Wrap(
                spacing: DropClipSpacing.sm,
                children: [
                  if (entry.value == 'trusted')
                    OutlinedButton(
                      key: Key('btn-quarantine-${entry.key}'),
                      onPressed: () => setState(
                        () => _trustState[entry.key] = 'quarantined',
                      ),
                      child: const Text('Quarantine'),
                    ),
                  if (entry.value == 'quarantined') ...[
                    FilledButton(
                      key: Key('btn-confirm-revoke-${entry.key}'),
                      onPressed: () => setState(
                        () => _trustState[entry.key] = 'revoked',
                      ),
                      child: const Text('Confirm Revoke'),
                    ),
                    TextButton(
                      key: Key('btn-restore-${entry.key}'),
                      onPressed: () => setState(
                        () => _trustState[entry.key] = 'trusted',
                      ),
                      child: const Text('Restore Peer'),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
