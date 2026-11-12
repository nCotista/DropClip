import 'dart:async';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter/material.dart';

import '../dropzone/dropzone_panel.dart';
import '../l10n/strings.dart';

/// Asks whether to receive [items] from [peer] (FR-08, Auto-Accept off).
/// No answer within `OFFER_TIMEOUT` (60 s, §7.4.5) declines.
Future<bool> askToReceive(
    BuildContext context, String peer, List<FileOfferItem> items) async {
  final t = Strings.of(context);
  final total = items.fold<int>(0, (s, i) => s + i.size);
  final navigator = Navigator.of(context);
  final timer = Timer(const Duration(seconds: 60), () => navigator.pop(false));
  final answer = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text(t.receiveFrom(peer)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in items.take(5))
            Text('${i.path} · ${formatBytes(i.size)}'),
          if (items.length > 5) Text('+${items.length - 5}'),
          const SizedBox(height: 8),
          Text(formatBytes(total)),
        ],
      ),
      actions: [
        TextButton(
            key: const Key('receive-no'),
            onPressed: () => navigator.pop(false),
            child: Text(t.decline)),
        FilledButton(
            key: const Key('receive-yes'),
            onPressed: () => navigator.pop(true),
            child: Text(t.accept)),
      ],
    ),
  );
  timer.cancel();
  return answer ?? false;
}
