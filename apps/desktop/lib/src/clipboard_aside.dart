import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'demo_data.dart';

/// NFR-P01A: macOS ↔ Windows text sync p95 < 1,000 ms.
const int latencyTargetMs = 1000;

/// Right-hand panel of the Clipboard screen: nearby devices, pairing,
/// dropzone shortcut and live sync latency (T1.12).
class ClipboardAside extends StatelessWidget {
  final ShellStatus status;
  final VoidCallback? onPair;
  final VoidCallback? onOpenDropzone;

  const ClipboardAside({
    super.key,
    required this.status,
    this.onPair,
    this.onOpenDropzone,
  });

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final online = status.nearby.where((d) => d.reach == PeerReach.online);
    return ListView(
      padding: const EdgeInsets.all(DropClipSpacing.xl),
      children: [
        Row(children: [
          const Expanded(
            child: Text('Nearby devices',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('${online.length} online',
              style: TextStyle(fontSize: 12, color: c.textSecondary)),
        ]),
        const SizedBox(height: DropClipSpacing.md),
        if (status.nearby.isEmpty)
          Text('No devices nearby', style: TextStyle(color: c.textTertiary)),
        for (final d in status.nearby) _DeviceRow(device: d),
        const SizedBox(height: DropClipSpacing.sm),
        OutlinedButton.icon(
          onPressed: onPair,
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Pair new device'),
        ),
        const SizedBox(height: DropClipSpacing.lg),
        _Panel(
          onTap: onOpenDropzone,
          child: Column(children: [
            Icon(Icons.upload_file_rounded, color: c.textAccent, size: 28),
            const SizedBox(height: DropClipSpacing.sm),
            const Text('Drop files to send',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Text('Any size · Resumable · SHA-256 checked',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ]),
        ),
        const SizedBox(height: DropClipSpacing.lg),
        if (status.latencyP95Ms.isNotEmpty)
          _LatencyCard(samples: status.latencyP95Ms),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Panel({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final radius = BorderRadius.circular(DropClipRadius.card);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: radius, side: BorderSide(color: c.border)),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(DropClipSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final NearbyDevice device;

  const _DeviceRow({required this.device});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final (label, color) = switch (device.reach) {
      PeerReach.online => ('Online', c.success),
      PeerReach.manual => ('Manual', c.warning),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: DropClipSpacing.md),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name, overflow: TextOverflow.ellipsis),
            Text(device.detail,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: DropClipSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(DropClipRadius.tag),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: color)),
        ),
      ]),
    );
  }
}

class _LatencyCard extends StatelessWidget {
  final List<int> samples;

  const _LatencyCard({required this.samples});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final current = samples.last;
    final ok = current < latencyTargetMs;
    final peak = samples.reduce((a, b) => a > b ? a : b);
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Sync latency · p95',
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ),
          Text('LIVE',
              style:
                  dropClipMono(context, fontSize: 11).copyWith(color: c.cyan)),
        ]),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: '$current',
              style: dropClipMono(context, fontSize: 28)
                  .copyWith(fontWeight: FontWeight.w700)),
          TextSpan(text: ' ms', style: TextStyle(color: c.textSecondary)),
        ])),
        const SizedBox(height: DropClipSpacing.sm),
        SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < samples.length; i++)
                Expanded(
                  child: Container(
                    key: ValueKey('latency-bar-$i'),
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: 40 * samples[i] / peak,
                    decoration: BoxDecoration(
                      color: i == samples.length - 1
                          ? c.cyan
                          : c.accent.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DropClipSpacing.sm),
        Text(ok ? 'Under 1,000 ms target' : 'Over 1,000 ms target',
            style: TextStyle(fontSize: 12, color: ok ? c.success : c.danger)),
      ]),
    );
  }
}
