import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dropzone_panel.dart';

/// A dropped file or folder on disk.
typedef DropEntry = ({String name, String path, bool isFolder});

/// State of the Dropzone overlay (T1.12, UI-02): whether it is open, a drag
/// is over the window, and what has been dropped so far.
class DropzoneController extends ChangeNotifier {
  bool _open = false;
  bool _dragging = false;
  final _items = <String, DroppedItem>{}; // by path, so a re-drop is ignored

  bool get open => _open;
  bool get dragging => _dragging;
  List<DroppedItem> get items => List.unmodifiable(_items.values);

  void show() => _set(() => _open = true);

  /// Closes the overlay and forgets the dropped items.
  void close() => _set(() {
        _open = false;
        _dragging = false;
        _items.clear();
      });

  /// A drag entered the window: open the overlay to receive it.
  void dragEntered() => _set(() {
        _open = true;
        _dragging = true;
      });

  void dragLeft() => _set(() => _dragging = false);

  /// Adds dropped entries with their sizes; a folder counts every file in
  /// it. Entries that vanished before they could be read are skipped.
  Future<void> addDropped(List<DropEntry> entries) async {
    _set(() {
      _open = true;
      _dragging = false;
    });
    for (final e in entries) {
      if (_items.containsKey(e.path)) continue;
      final bytes = await _sizeOf(e);
      if (bytes == null) continue;
      _items[e.path] = DroppedItem(e.name, bytes, isFolder: e.isFolder);
    }
    notifyListeners();
  }

  static Future<int?> _sizeOf(DropEntry e) async {
    try {
      if (!e.isFolder) return await File(e.path).length();
      var total = 0;
      await for (final f
          in Directory(e.path).list(recursive: true, followLinks: false)) {
        if (f is File) total += await f.length();
      }
      return total;
    } on FileSystemException {
      return null;
    }
  }

  void _set(VoidCallback change) {
    change();
    notifyListeners();
  }
}
