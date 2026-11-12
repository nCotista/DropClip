import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';

/// Devices (T1.12, UI-03): this device, paired devices with live link state
/// and Remove, and nearby devices that can be paired.
class DevicesPage extends StatelessWidget {
  final String myName;
  final String myFingerprint;
  final ValueListenable<List<TrustedDevice>> trusted;
  final Stream<Set<String>> connectedChanges;
  final Set<String> connected;
  final ValueListenable<List<DiscoveredPeer>> nearby;
  final VoidCallback onPairNew;
  final void Function(DiscoveredPeer peer) onPairWith;
  final void Function(TrustedDevice device) onForget;

  const DevicesPage({
    super.key,
    required this.myName,
    required this.myFingerprint,
    required this.trusted,
    required this.connectedChanges,
    required this.connected,
    required this.nearby,
    required this.onPairNew,
    required this.onPairWith,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final c = DropClipColors.of(context);
    final fp = myFingerprint.length >= 16
        ? '${myFingerprint.substring(0, 16)}…'
        : myFingerprint;
    return ListView(
      padding: const EdgeInsets.all(DropClipSpacing.xxl),
      children: [
        Row(children: [
          Expanded(
              child: Text(t.devices,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
          FilledButton.icon(
              key: const Key('pair-new'),
              onPressed: onPairNew,
              icon: const Icon(Icons.add_link, size: 18),
              label: Text(t.pairNewDevice)),
        ]),
        const SizedBox(height: DropClipSpacing.lg),
        Card(
            child: ListTile(
                leading: const Icon(Icons.computer),
                title: Text(myName),
                subtitle: Text('${t.thisDevice} · SHA-256 $fp',
                    style: TextStyle(color: c.textSecondary)))),
        const SizedBox(height: DropClipSpacing.lg),
        Text(t.pairedDevices, style: Theme.of(context).textTheme.titleMedium),
        StreamBuilder<Set<String>>(
          stream: connectedChanges,
          initialData: connected,
          builder: (_, live) => ValueListenableBuilder<List<TrustedDevice>>(
            valueListenable: trusted,
            builder: (_, list, __) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(DropClipSpacing.md),
                    child: Text(t.noPairedDevices,
                        style: TextStyle(color: c.textSecondary)))
                : Column(children: [
                    for (final d in list)
                      _trustedRow(context, d,
                          online: live.data?.contains(d.deviceId) ?? false),
                  ]),
          ),
        ),
        const SizedBox(height: DropClipSpacing.lg),
        Text(t.nearbyDevices, style: Theme.of(context).textTheme.titleMedium),
        ValueListenableBuilder<List<DiscoveredPeer>>(
          valueListenable: nearby,
          builder: (_, peers, __) {
            final unpaired =
                peers.where((p) => p.trust != PeerTrust.trusted).toList();
            if (unpaired.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(DropClipSpacing.md),
                  child: Text(t.noDevicesNearby,
                      style: TextStyle(color: c.textSecondary)));
            }
            return Column(children: [
              for (final p in unpaired)
                ListTile(
                  leading: Icon(_icon(p.record.os.name)),
                  title: Text(p.record.name),
                  subtitle: Text('${p.record.os.name} · ${p.address}'),
                  trailing: OutlinedButton(
                      key: Key('pair-${p.deviceId}'),
                      onPressed: () => onPairWith(p),
                      child: Text(t.pair)),
                ),
            ]);
          },
        ),
      ],
    );
  }

  Widget _trustedRow(BuildContext context, TrustedDevice d,
      {required bool online}) {
    final t = Strings.of(context);
    final c = DropClipColors.of(context);
    return ListTile(
      leading: Icon(_icon(d.os)),
      title: Text(d.name),
      subtitle: Row(children: [
        Icon(Icons.circle, size: 8, color: online ? c.success : c.textTertiary),
        const SizedBox(width: 6),
        Text(online ? t.connected : t.offline),
      ]),
      trailing: TextButton(
          key: Key('forget-${d.deviceId}'),
          onPressed: () => onForget(d),
          child: Text(t.remove)),
    );
  }

  static IconData _icon(String os) => switch (os) {
        'android' || 'ios' => Icons.smartphone,
        _ => Icons.computer,
      };
}
