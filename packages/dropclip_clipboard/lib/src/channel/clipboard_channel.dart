/// The two §14.1 channels, kept free of Flutter so the logic is testable
/// in pure Dart. The desktop app wraps `MethodChannel('dropclip/clipboard')`
/// and `EventChannel('dropclip/clipboard/events')`, turning each
/// `PlatformException` into a [ClipboardChannelException] with the same
/// code.
abstract interface class ClipboardChannel {
  /// Calls a native method and returns its decoded result.
  Future<Object?> invoke(String method, [Map<String, Object?>? args]);

  /// Raw `ClipSnapshot` maps pushed by the native watcher.
  Stream<Object?> get events;
}

/// A native error, e.g. `CLIPBOARD_LOCKED`.
class ClipboardChannelException implements Exception {
  final String code;
  final String? message;
  const ClipboardChannelException(this.code, [this.message]);

  @override
  String toString() => 'ClipboardChannelException($code)';
}

/// Another app held the clipboard through all retries (50/100/200 ms,
/// §14.1, §16 `CLIPBOARD_LOCK_RETRY`). Callers log a warning and go on
/// (FR-03A Exception Handling).
class ClipboardLockedException implements Exception {
  final String method;
  const ClipboardLockedException(this.method);

  @override
  String toString() => 'ClipboardLockedException($method)';
}
