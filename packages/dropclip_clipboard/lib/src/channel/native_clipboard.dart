import 'dart:async';
import 'dart:typed_data';

import '../../dropclip_clipboard.dart' show ClipboardItem, PlatformClipboard;
import 'clip_snapshot.dart';
import 'clipboard_channel.dart';

/// [PlatformClipboard] over the §14.1 platform channels (T1.7 Windows,
/// T1.6 macOS share the same contract).
class NativeClipboard implements PlatformClipboard {
  static const lockedCode = 'CLIPBOARD_LOCKED';

  final ClipboardChannel _channel;

  /// Log events only; clipboard content is never passed here (NFR-S02).
  final void Function(String event)? log;

  final _changes = StreamController<ClipSnapshot>.broadcast();
  StreamSubscription<Object?>? _sub;
  int _lastToken = 0;

  NativeClipboard(this._channel, {this.log});

  /// Every clipboard change the native watcher reports, concealed ones
  /// included (with no items) so the sync engine can count them.
  Stream<ClipSnapshot> get changes => _changes.stream;

  @override
  Future<void> start() async {
    if (_sub != null) return;
    _sub = _channel.events.listen(_onEvent,
        onError: (Object _) => log?.call('clipboard.event_error'));
    try {
      await _call('start');
    } catch (_) {
      await _sub?.cancel();
      _sub = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (_sub == null) return;
    await _sub!.cancel();
    _sub = null;
    await _call('stop');
  }

  /// Current content, or null when empty, unsupported or concealed.
  @override
  Future<List<ClipboardItem>?> read() async {
    final raw = await _call('read');
    if (raw == null) return null;
    final snap = ClipSnapshot.fromMap(raw);
    _lastToken = snap.changeToken;
    return snap.items.isEmpty ? null : snap.items;
  }

  /// Writes all [items] in one native transaction; returns the new token.
  @override
  Future<int> write(List<ClipboardItem> items) async {
    if (items.isEmpty) throw ArgumentError.value(items, 'items', 'empty');
    for (final i in items) {
      if (!ClipMime.isKnown(i.mime)) {
        throw ArgumentError.value(i.mime, 'mime', 'unknown');
      }
    }
    final result = await _call('write', {
      'items': [
        for (final i in items)
          {'mime': i.mime, 'data': Uint8List.fromList(i.data)},
      ],
    });
    final token = result is Map ? result['change_token'] : null;
    if (token is! int) {
      throw const FormatException('write: bad change_token');
    }
    _lastToken = token;
    return token;
  }

  @override
  Future<void> clear() => _call('clear');

  /// Last token seen from an event, [read] or [write]. The interface is
  /// synchronous; use [fetchChangeToken] for the live value.
  @override
  int changeToken() => _lastToken;

  Future<int> fetchChangeToken() async {
    final token = await _call('changeToken');
    if (token is! int) throw const FormatException('bad changeToken');
    _lastToken = token;
    return token;
  }

  /// Stops listening and closes [changes].
  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }

  void _onEvent(Object? raw) {
    final ClipSnapshot snap;
    try {
      snap = ClipSnapshot.fromMap(raw);
    } on FormatException {
      log?.call('clipboard.malformed_event');
      return;
    }
    _lastToken = snap.changeToken;
    if (snap.isConcealed) log?.call('clipboard.blocked_concealed');
    _changes.add(snap);
  }

  Future<Object?> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invoke(method, args);
    } on ClipboardChannelException catch (e) {
      if (e.code != lockedCode) rethrow;
      log?.call('clipboard.locked');
      throw ClipboardLockedException(method);
    }
  }
}
