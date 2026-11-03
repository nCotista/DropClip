import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo_data.dart';
import '../l10n/strings.dart';

/// A file or folder dropped on the Dropzone.
class DroppedItem {
  final String name;
  final int bytes;
  final bool isFolder;

  const DroppedItem(this.name, this.bytes, {this.isFolder = false});
}

/// `1.7 GB`-style size, 1000-based like Finder and Explorer's file sizes.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1000 && u < units.length - 1) {
    v /= 1000;
    u++;
  }
  return u == 0 ? '$bytes B' : '${v.toStringAsFixed(1)} ${units[u]}';
}

/// Floating Dropzone from the UI design (T1.12, UI-02): drop files, pick a
/// nearby device, send. ↑/↓ choose, Enter sends, Esc closes.
///
/// [items] and [dragging] come from the drag-and-drop source; [onSend] is
/// null while sending is unavailable (file transfer is T1.10/T1.11).
class DropzonePanel extends StatefulWidget {
  final List<DroppedItem> items;
  final bool dragging;
  final List<NearbyDevice> devices;
  final void Function(NearbyDevice to, List<DroppedItem> items)? onSend;
  final VoidCallback onClose;

  const DropzonePanel({
    super.key,
    required this.items,
    required this.devices,
    required this.onClose,
    this.dragging = false,
    this.onSend,
  });

  @override
  State<DropzonePanel> createState() => _DropzonePanelState();
}

class _DropzonePanelState extends State<DropzonePanel> {
  int _picked = 0;
  final _focus = FocusNode(debugLabel: 'Dropzone');

  @override
  void initState() {
    super.initState();
    // autofocus is ignored when the app already has focus, so take it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  NearbyDevice? get _target => widget.devices.isEmpty
      ? null
      : widget.devices[_picked.clamp(0, widget.devices.length - 1)];

  bool get _canSend =>
      widget.onSend != null && widget.items.isNotEmpty && _target != null;

  void _move(int by) {
    if (widget.devices.isEmpty) return;
    setState(() => _picked = (_picked.clamp(0, widget.devices.length - 1) + by)
        .clamp(0, widget.devices.length - 1));
  }

  void _send() {
    if (_canSend) widget.onSend!(_target!, widget.items);
  }

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final s = Strings.of(context);
    final target = _target;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.enter): _send,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _DropArea(items: widget.items, dragging: widget.dragging),
            const SizedBox(height: DropClipSpacing.lg),
            Text(s.sendTo,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: c.textTertiary)),
            const SizedBox(height: DropClipSpacing.sm),
            if (widget.devices.isEmpty)
              Text(s.noDevicesNearby, style: TextStyle(color: c.textSecondary)),
            for (final (i, d) in widget.devices.indexed)
              _DeviceChoice(
                  device: d,
                  picked: d == target,
                  onTap: () => setState(() => _picked = i)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _canSend ? _send : null,
              icon: const Icon(Icons.send_outlined, size: 16),
              label: Text(s.sendToDevice(target?.name ?? '…')),
            ),
            const SizedBox(height: DropClipSpacing.sm),
            Text(s.dropzoneKeys,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.textTertiary)),
          ]),
        ),
      ),
    );
  }
}

class _DropArea extends StatelessWidget {
  final List<DroppedItem> items;
  final bool dragging;

  const _DropArea({required this.items, required this.dragging});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    final s = Strings.of(context);
    // The OS reports the files only on drop, so the hover text has no count.
    final title = dragging
        ? s.releaseToAdd
        : (items.isEmpty ? s.dropHere : s.itemCount(items.length));
    final total = items.fold<int>(0, (sum, i) => sum + i.bytes);
    final names = [for (final i in items) i.isFolder ? '${i.name}/' : i.name];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: dragging ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(DropClipRadius.window),
        border: Border.all(color: c.accent, width: 2),
      ),
      child: Column(children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: c.accent.withValues(alpha: 0.22),
          child: Icon(Icons.upload_outlined, color: c.textAccent),
        ),
        const SizedBox(height: DropClipSpacing.sm),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (items.isNotEmpty)
          Text('${names.join(', ')} · ${formatBytes(total)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.textSecondary)),
      ]),
    );
  }
}

class _DeviceChoice extends StatelessWidget {
  final NearbyDevice device;
  final bool picked;
  final VoidCallback onTap;

  const _DeviceChoice(
      {required this.device, required this.picked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = DropClipColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DropClipSpacing.sm),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: picked,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DropClipSpacing.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: DropClipSpacing.md, vertical: 10),
            decoration: BoxDecoration(
              color: picked ? c.elevated : c.surface,
              borderRadius: BorderRadius.circular(DropClipSpacing.md),
              border: Border.all(
                  color: picked ? c.accent : c.border, width: picked ? 2 : 1),
            ),
            child: Row(children: [
              Icon(picked ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18, color: picked ? c.accent : c.textTertiary),
              const SizedBox(width: DropClipSpacing.md),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(device.detail,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 11, color: c.textTertiary)),
                    ]),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      device.reach == PeerReach.online ? c.success : c.warning,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
