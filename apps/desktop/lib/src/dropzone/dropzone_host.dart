import 'package:desktop_drop/desktop_drop.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo_data.dart';
import 'dropzone_controller.dart';
import 'dropzone_panel.dart';

/// Shows the Dropzone over the app (T1.12, UI-02) when files are dragged
/// onto the window, the tray's "Open Dropzone" is picked, or ⌥⌘D /
/// Ctrl+Alt+D is pressed. The design's floating window is shown as a panel
/// inside the main window; Flutter desktop has a single window.
class DropzoneHost extends StatelessWidget {
  final DropzoneController controller;
  final ValueListenable<List<NearbyDevice>> devices;
  final void Function(NearbyDevice to, List<DroppedItem> items)? onSend;
  final Widget child;

  /// Off in widget tests, where the native drop plugin is not available.
  final bool nativeDrop;

  const DropzoneHost({
    super.key,
    required this.controller,
    required this.devices,
    required this.child,
    this.onSend,
    this.nativeDrop = true,
  });

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    Widget body = CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyD,
            alt: true, meta: mac, control: !mac): controller.show,
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, devices]),
        builder: (context, _) => Stack(children: [
          child,
          if (controller.open) ...[
            ModalBarrier(
                color: Colors.black.withValues(alpha: 0.45),
                onDismiss: controller.close),
            Center(child: _window(context)),
          ],
        ]),
      ),
    );
    if (nativeDrop) {
      body = DropTarget(
        onEnter: (_) => controller.dragEntered(),
        onLeave: controller.dragLeft,
        onDrop: (details) => controller.addDropped([
          for (final item in details.items)
            if (item case DropFileItem(:final name, :final localPath?))
              (name: name, path: localPath, isFolder: false)
            else if (item
                case DropDirectoryItem(:final name, :final localPath?))
              (name: name, path: localPath, isFolder: true),
        ]),
        child: body,
      );
    }
    return body;
  }

  Widget _window(BuildContext context) {
    final c = DropClipColors.of(context);
    return Material(
      color: c.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DropClipRadius.window),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 400,
        height: 640,
        child: DropzonePanel(
          items: controller.items,
          dragging: controller.dragging,
          devices: devices.value,
          onSend: onSend,
          onClose: controller.close,
        ),
      ),
    );
  }
}
