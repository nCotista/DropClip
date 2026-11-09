import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';

/// First-run explanation of the Windows Defender Firewall prompt
/// (PROTO-DC-V2.0 §3.1, UR-07). Shown once, then remembered in
/// `config.json` (`first_run_done`).
class FirewallOnboardingCard extends StatelessWidget {
  final VoidCallback onDone;

  const FirewallOnboardingCard({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final muted = TextStyle(color: c.textSecondary);
    final s = Strings.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
          DropClipSpacing.xxl, DropClipSpacing.xl, DropClipSpacing.xxl, 0),
      padding: const EdgeInsets.all(DropClipSpacing.lg),
      decoration: BoxDecoration(
        color: c.elevated,
        borderRadius: BorderRadius.circular(DropClipRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined, color: c.cyan),
        const SizedBox(width: DropClipSpacing.md),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.firewallTitle,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: DropClipSpacing.xs),
            Text(s.firewallBody, style: muted),
            const SizedBox(height: DropClipSpacing.xs),
            Text(s.firewallPublic, style: muted.copyWith(fontSize: 12)),
          ]),
        ),
        const SizedBox(width: DropClipSpacing.md),
        FilledButton(onPressed: onDone, child: Text(s.gotIt)),
      ]),
    );
  }
}
