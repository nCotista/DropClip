import 'dart:async';
import 'dart:collection';

import '../logging_scrubber.dart';

/// Log severity, lowest first.
enum LogLevel { debug, info, warn, error }

/// Where formatted JSON lines go.
abstract interface class LogSink {
  void add(String line);
  Future<void> flush();
  Future<void> close();
}

/// Discards every line; the baseline for the overhead benchmark.
class NoopLogSink implements LogSink {
  const NoopLogSink();

  @override
  void add(String line) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Structured JSON Lines logger (T0.3, NFR-S02, Protocol Spec §17.2).
///
/// Every line goes through [LoggingScrubber.formatLogLine], so keys such as
/// `password` or `content` and PEM private keys never reach the sink. The
/// last [recentLimit] lines are kept in memory for the debug console.
class StructuredLogger {
  StructuredLogger({
    required this.deviceId,
    required LogSink sink,
    this.minLevel = LogLevel.info,
    this.recentLimit = 500,
    DateTime Function()? clock,
  })  : _sink = sink,
        _clock = clock ?? DateTime.now;

  final String deviceId;
  final LogLevel minLevel;
  final int recentLimit;
  final LogSink _sink;
  final DateTime Function() _clock;
  final _recent = ListQueue<String>();
  final _lines = StreamController<String>.broadcast(sync: true);
  bool _closed = false;

  /// Newest last.
  List<String> get recent => List.unmodifiable(_recent);

  /// Each line as it is written.
  Stream<String> get lines => _lines.stream;

  void log(LogLevel level, String component, String msg,
      [Map<String, dynamic>? data]) {
    if (_closed || level.index < minLevel.index) return;
    final line = LoggingScrubber.formatLogLine(
      level: level.name,
      component: component,
      deviceId: deviceId,
      msg: msg,
      data: data,
      timestamp: _clock().toUtc(),
    );
    _sink.add(line);
    _recent.addLast(line);
    if (_recent.length > recentLimit) _recent.removeFirst();
    if (_lines.hasListener) _lines.add(line);
    // Warnings and errors are written at once so a crash does not lose them.
    if (level.index >= LogLevel.warn.index) unawaited(_sink.flush());
  }

  void debug(String component, String msg, [Map<String, dynamic>? data]) =>
      log(LogLevel.debug, component, msg, data);
  void info(String component, String msg, [Map<String, dynamic>? data]) =>
      log(LogLevel.info, component, msg, data);
  void warn(String component, String msg, [Map<String, dynamic>? data]) =>
      log(LogLevel.warn, component, msg, data);
  void error(String component, String msg, [Map<String, dynamic>? data]) =>
      log(LogLevel.error, component, msg, data);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sink.close();
    await _lines.close();
  }
}
