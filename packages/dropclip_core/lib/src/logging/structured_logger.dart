import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

const _mib = 1024 * 1024;

/// Appends lines to `<baseName>.log` and rotates it to `<baseName>.1.log` …
/// `<baseName>.<maxFiles-1>.log` when it would pass [maxFileBytes]. Rotated
/// files are deleted oldest first so all files together stay within
/// [maxTotalBytes] (10 MB × 5 files, 50 MB in total by default).
///
/// Lines are buffered and written every [flushBytes] or [flushEvery]. A write
/// error drops the buffered lines instead of failing the caller.
class RotatingFileSink implements LogSink {
  RotatingFileSink(
    this.directory, {
    this.baseName = 'dropclip',
    this.maxFileBytes = 10 * _mib,
    this.maxFiles = 5,
    this.maxTotalBytes = 50 * _mib,
    this.flushBytes = 64 * 1024,
    Duration flushEvery = const Duration(seconds: 1),
  }) : assert(maxFiles >= 1 && maxFileBytes > 0 && maxTotalBytes > 0) {
    directory.createSync(recursive: true);
    final current = fileAt(0);
    _size = current.existsSync() ? current.lengthSync() : 0;
    _timer = Timer.periodic(flushEvery, (_) => _flushSync());
  }

  final Directory directory;
  final String baseName;
  final int maxFileBytes;
  final int maxFiles;
  final int maxTotalBytes;
  final int flushBytes;
  final _pending = BytesBuilder(copy: false);
  late final Timer _timer;
  RandomAccessFile? _raf;
  int _size = 0;
  bool _closed = false;

  /// The current file at 0, then older rotated files.
  File fileAt(int index) => File('${directory.path}${Platform.pathSeparator}'
      '$baseName${index == 0 ? '' : '.$index'}.log');

  @override
  void add(String line) {
    if (_closed) return;
    final bytes = utf8.encode('$line\n');
    if (_size > 0 && _size + bytes.length > maxFileBytes) {
      _flushSync();
      _rotate();
    }
    _pending.add(bytes);
    _size += bytes.length;
    if (_pending.length >= flushBytes) _flushSync();
  }

  @override
  Future<void> flush() async => _flushSync();

  @override
  Future<void> close() async {
    if (_closed) return;
    _timer.cancel();
    _flushSync();
    _closeFile();
    _closed = true;
  }

  void _flushSync() {
    if (_pending.isEmpty) return;
    final bytes = _pending.takeBytes();
    try {
      // Kept open between flushes: reopening makes antivirus scanners re-read
      // the whole file on every close (about 45 µs per line on Windows).
      (_raf ??= fileAt(0).openSync(mode: FileMode.append)).writeFromSync(bytes);
    } on FileSystemException {
      // Logging must never take the app down.
      _closeFile();
    }
  }

  void _closeFile() {
    try {
      _raf?.closeSync();
    } on FileSystemException {
      // Already gone.
    }
    _raf = null;
  }

  void _rotate() {
    _closeFile(); // Windows cannot rename a file that is still open.
    try {
      final oldest = fileAt(maxFiles - 1);
      if (maxFiles > 1 && oldest.existsSync()) oldest.deleteSync();
      for (var i = maxFiles - 2; i >= 0; i--) {
        final f = fileAt(i);
        if (f.existsSync()) f.renameSync(fileAt(i + 1).path);
      }
      if (maxFiles == 1 && fileAt(0).existsSync()) fileAt(0).deleteSync();
      _trimTotal();
    } on FileSystemException {
      // Keep appending to the current file; the next rotation tries again.
    }
    _size = 0;
  }

  /// Leaves room for a full current file within [maxTotalBytes].
  void _trimTotal() {
    final rotated = [
      for (var i = 1; i < maxFiles; i++)
        if (fileAt(i).existsSync()) fileAt(i),
    ];
    var total = rotated.fold<int>(0, (sum, f) => sum + f.lengthSync());
    for (final f in rotated.reversed) {
      if (total + maxFileBytes <= maxTotalBytes) break;
      total -= f.lengthSync();
      f.deleteSync();
    }
  }
}
