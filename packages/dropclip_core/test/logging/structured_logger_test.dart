import 'dart:convert';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

class _MemorySink implements LogSink {
  final lines = <String>[];
  int flushes = 0;

  @override
  void add(String line) => lines.add(line);

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<void> close() async {}
}

void main() {
  group('StructuredLogger (T0.3)', () {
    late _MemorySink sink;
    late StructuredLogger log;

    setUp(() {
      sink = _MemorySink();
      log = StructuredLogger(
        deviceId: 'dev-1',
        sink: sink,
        recentLimit: 3,
        clock: () => DateTime.utc(2026, 11, 3, 12),
      );
    });

    test('writes one valid JSON object per line with the §17.2 fields', () {
      log.info('discovery', 'peer found', {'peer': 'dev-2', 'port': 41234});
      final record = jsonDecode(sink.lines.single) as Map<String, dynamic>;
      expect(record, {
        'ts': '2026-11-03T12:00:00.000Z',
        'level': 'INFO',
        'component': 'discovery',
        'device_id': 'dev-1',
        'msg': 'peer found',
        'data': {'peer': 'dev-2', 'port': 41234},
      });
    });

    test('never writes secrets or clipboard content (NFR-S02)', () {
      log.warn('clipboard', 'sent', {
        'pin': '123456',
        'content': 'my bank password',
        'nested': {'token': 'abc'},
      });
      final line = sink.lines.single;
      expect(line, isNot(contains('123456')));
      expect(line, isNot(contains('my bank password')));
      expect(line, isNot(contains('abc')));
      expect(line, contains('length=16'));
    });

    test('drops lines below the minimum level', () {
      log.debug('x', 'hidden');
      expect(sink.lines, isEmpty);
      expect(log.recent, isEmpty);
    });

    test('flushes at once for warnings and errors only', () async {
      log.info('x', 'a');
      expect(sink.flushes, 0);
      log.error('x', 'b');
      await Future<void>.delayed(Duration.zero);
      expect(sink.flushes, 1);
    });

    test('keeps only the newest lines and streams new ones', () async {
      final seen = <String>[];
      log.lines.listen(seen.add);
      for (var i = 0; i < 5; i++) {
        log.info('x', 'm$i');
      }
      expect(log.recent.map((l) => jsonDecode(l)['msg']), ['m2', 'm3', 'm4']);
      expect(seen, hasLength(5));
    });

    test('ignores lines after close', () async {
      await log.close();
      log.error('x', 'late');
      expect(sink.lines, isEmpty);
    });
  });
}
