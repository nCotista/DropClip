import 'dart:async';
import 'dart:convert';

import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';

/// JSON log lines for the console: the newest kept lines plus new ones as
/// they are written. Implemented by the core `StructuredLogger`.
abstract interface class LogFeed {
  List<String> get recent;
  Stream<String> get lines;
}

/// `12:00:03 WARN  discovery  peer lost {id: …}` from a JSON log line; other
/// text is shown as is. Lines are already scrubbed (NFR-S02).
String formatLogLine(String line) {
  try {
    final r = jsonDecode(line) as Map<String, dynamic>;
    final ts = r['ts'] as String? ?? '';
    final time = ts.length >= 19 ? ts.substring(11, 19) : ts;
    final data = r['data'] == null ? '' : ' ${r['data']}';
    return '$time ${(r['level'] ?? '').toString().padRight(5)} '
        '${r['component'] ?? ''}  ${r['msg'] ?? ''}$data';
  } on FormatException {
    return line;
  } on TypeError {
    return line;
  }
}

/// In-app debug console for developers (T0.3): Ctrl+Shift+D (⌘⇧D on
/// macOS) shows the newest log lines over the app and follows new ones.
class DebugConsoleHost extends StatefulWidget {
  final LogFeed feed;
  final Widget child;
  final int maxLines;

  const DebugConsoleHost(
      {super.key,
      required this.feed,
      required this.child,
      this.maxLines = 500});

  @override
  State<DebugConsoleHost> createState() => _DebugConsoleHostState();
}

class _DebugConsoleHostState extends State<DebugConsoleHost> {
  final _lines = <String>[];
  StreamSubscription<String>? _sub;

  bool get _open => _sub != null;

  void _toggle() => setState(() {
        if (_open) {
          _sub!.cancel();
          _sub = null;
          _lines.clear();
          return;
        }
        _lines.addAll(widget.feed.recent.map(formatLogLine));
        _sub = widget.feed.lines.listen((l) => setState(() {
              _lines.add(formatLogLine(l));
              if (_lines.length > widget.maxLines) _lines.removeAt(0);
            }));
      });

  @override
  void initState() {
    super.initState();
    // Global, so it works even when nothing in the app has focus.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sub?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    final k = HardwareKeyboard.instance;
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final hit = e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyD;
    if (!hit || !(mac ? k.isMetaPressed : k.isControlPressed)) return false;
    if (!k.isShiftPressed || k.isAltPressed) return false;
    _toggle();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_open)
        Positioned(left: 0, right: 0, bottom: 0, height: 260, child: _panel()),
    ]);
  }

  Widget _panel() {
    final c = DropClipColors.of(context);
    final s = Strings.of(context);
    return Material(
      color: c.canvas,
      elevation: 8,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.only(left: DropClipSpacing.md),
          decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border))),
          child: Row(children: [
            Expanded(
                child: Text(s.debugConsole(_lines.length),
                    style: TextStyle(fontSize: 12, color: c.textSecondary))),
            // No tooltip: this sits above the Navigator (MaterialApp.builder),
            // where there is no Overlay for a tooltip to float in.
            IconButton(
                icon: const Icon(Icons.close,
                    size: 16, semanticLabel: 'Close (Ctrl+Shift+D)'),
                onPressed: _toggle),
          ]),
        ),
        Expanded(
          child: _lines.isEmpty
              ? Center(
                  child: Text(s.noLogLines,
                      style: TextStyle(color: c.textTertiary)))
              : ListView.builder(
                  reverse: true, // newest at the bottom, kept in view
                  padding: const EdgeInsets.all(DropClipSpacing.sm),
                  itemCount: _lines.length,
                  itemBuilder: (context, i) => SelectableText(
                      _lines[_lines.length - 1 - i],
                      style: dropClipMono(context, fontSize: 11)),
                ),
        ),
      ]),
    );
  }
}
