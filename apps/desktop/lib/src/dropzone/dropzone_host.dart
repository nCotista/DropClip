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
class DropzoneHost extends StatefulWidget {
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
  State<DropzoneHost> createState() => _DropzoneHostState();
}

class _DropzoneHostState extends State<DropzoneHost> {
  DropzoneController get _dz => widget.controller;

  @override
  void initState() {
    super.initState();
    // A global handler, not CallbackShortcuts: the shortcut has to work
    // even when nothing in the app has keyboard focus yet.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    final k = HardwareKeyboard.instance;
    final mod = defaultTargetPlatform == TargetPlatform.macOS
        ? k.isMetaPressed
        : k.isControlPressed;
    if (e is! KeyDownEvent ||
        e.logicalKey != LogicalKeyboardKey.keyD ||
        !mod ||
        !k.isAltPressed ||
        k.isShiftPressed) {
      return false;
    }
    _dz.show();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    Widget body = ListenableBuilder(
      listenable: Listenable.merge([_dz, widget.devices]),
      builder: (context, _) => Stack(children: [
        widget.child,
        if (_dz.open) ...[
          ModalBarrier(
              color: Colors.black.withValues(alpha: 0.45),
              onDismiss: _dz.close),
          Center(child: _window(context)),
        ],
      ]),
    );
    if (widget.nativeDrop) {
      body = DropTarget(
        onEnter: (_) => _dz.dragEntered(),
        onLeave: _dz.dragLeft,
        onDrop: (details) => _dz.addDropped([
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
          items: _dz.items,
          dragging: _dz.dragging,
          devices: widget.devices.value,
          onSend: widget.onSend,
          onClose: _dz.close,
        ),
      ),
    );
  }
}
