// Logging overhead vs a no-op logger (T0.3 acceptance: < 5 %).
//
// Workload per event: hash a 4 KiB clip with SHA-256, as the sync engine does
// for every local change (Protocol Spec §10.2), then log one INFO line with
// structured data. Run with:
//   dart run benchmark/logger_overhead.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';

const _events = 20000;
const _rounds = 5;

Duration _run(StructuredLogger log, Uint8List clip) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < _events; i++) {
    clip[0] = i & 0xff;
    final hash = sha256.convert(clip).toString();
    log.info('clipboard', 'local change', {
      'type': 'text',
      'size': clip.length,
      'hash': hash.substring(0, 16),
      'content': 'never written',
    });
  }
  sw.stop();
  return sw.elapsed;
}

Future<void> main() async {
  final clip = Uint8List(4096);
  final dir = Directory.systemTemp.createTempSync('dropclip_bench');
  final noop = StructuredLogger(deviceId: 'bench', sink: const NoopLogSink());
  final sink = RotatingFileSink(dir);
  final file = StructuredLogger(deviceId: 'bench', sink: sink);

  _run(noop, clip); // warm up
  _run(file, clip);
  final base = <int>[], logged = <int>[];
  for (var r = 0; r < _rounds; r++) {
    base.add(_run(noop, clip).inMicroseconds);
    logged.add(_run(file, clip).inMicroseconds);
  }
  await file.close();
  base.sort();
  logged.sort();
  final b = base[_rounds ~/ 2], l = logged[_rounds ~/ 2];
  final overhead = (l - b) / b * 100;
  stdout.writeln('no-op: ${(b / _events).toStringAsFixed(2)} µs/event');
  stdout.writeln('file:  ${(l / _events).toStringAsFixed(2)} µs/event');
  stdout.writeln('overhead: ${overhead.toStringAsFixed(1)} % (median of '
      '$_rounds × $_events events)');
  dir.deleteSync(recursive: true);
  exitCode = overhead < 5 ? 0 : 1;
}
