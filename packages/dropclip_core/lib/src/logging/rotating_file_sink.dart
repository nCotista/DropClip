import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'structured_logger.dart';

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
