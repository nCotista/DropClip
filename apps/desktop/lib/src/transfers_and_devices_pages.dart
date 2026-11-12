import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';

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
  final VoidCallback? onSendSampleFile;
  final VoidCallback onOpenDropzone;
  final ValueChanged<String>? onResumeTransfer;

  const DesktopTransfersPage({
    super.key,
    required this.transfers,
    this.onSendSampleFile,
    required this.onOpenDropzone,
    this.onResumeTransfer,
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
            if (onSendSampleFile != null)
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
                          '${item.completed ? 'SHA-256 Verified' : 'Paused'}',
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ),
                      if (item.resumablePart &&
                          !item.completed &&
                          onResumeTransfer != null)
                        TextButton.icon(
                          key: Key('btn-desktop-resume-${item.id}'),
                          onPressed: () => onResumeTransfer!(item.id),
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
