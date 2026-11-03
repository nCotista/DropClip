import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('RotatingFileSink (T0.3)', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('dropclip_log'));
    tearDown(() => dir.deleteSync(recursive: true));

    String line(int i) => 'line-${i.toString().padLeft(4, '0')}'; // 10 bytes

    test('appends lines and keeps them after close', () async {
      final sink = RotatingFileSink(dir);
      sink.add(line(1));
      sink.add(line(2));
      await sink.close();
      expect(sink.fileAt(0).readAsLinesSync(), [line(1), line(2)]);
    });

    test('rotates at the size limit and keeps at most maxFiles', () async {
      final sink = RotatingFileSink(dir,
          maxFileBytes: 22, maxFiles: 3, maxTotalBytes: 1000);
      for (var i = 0; i < 10; i++) {
        sink.add(line(i)); // 11 bytes with the newline: 2 per file
      }
      await sink.close();
      expect(sink.fileAt(0).readAsLinesSync(), [line(8), line(9)]);
      expect(sink.fileAt(1).readAsLinesSync(), [line(6), line(7)]);
      expect(sink.fileAt(2).readAsLinesSync(), [line(4), line(5)]);
      expect(sink.fileAt(3).existsSync(), isFalse);
    });

    test('deletes the oldest files when the total would pass the cap',
        () async {
      final sink = RotatingFileSink(dir,
          maxFileBytes: 22, maxFiles: 5, maxTotalBytes: 50);
      for (var i = 0; i < 12; i++) {
        sink.add(line(i));
      }
      await sink.close();
      final total = dir
          .listSync()
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + f.lengthSync());
      expect(total, lessThanOrEqualTo(50));
      expect(sink.fileAt(0).readAsLinesSync(), [line(10), line(11)]);
      expect(sink.fileAt(1).readAsLinesSync(), [line(8), line(9)]);
      expect(sink.fileAt(2).existsSync(), isFalse);
    });

    test('a line longer than the limit still gets its own file', () async {
      final sink = RotatingFileSink(dir, maxFileBytes: 5, maxFiles: 2);
      sink.add(line(1));
      sink.add(line(2));
      await sink.close();
      expect(sink.fileAt(0).readAsLinesSync(), [line(2)]);
      expect(sink.fileAt(1).readAsLinesSync(), [line(1)]);
    });

    test('continues the size count of an existing file', () async {
      File('${dir.path}${Platform.pathSeparator}dropclip.log')
          .writeAsStringSync('${line(0)}\n');
      final sink = RotatingFileSink(dir, maxFileBytes: 22, maxFiles: 2);
      sink.add(line(1));
      sink.add(line(2));
      await sink.close();
      expect(sink.fileAt(1).readAsLinesSync(), [line(0), line(1)]);
      expect(sink.fileAt(0).readAsLinesSync(), [line(2)]);
    });

    test('writes in batches and on the timer', () async {
      final sink = RotatingFileSink(dir,
          flushBytes: 30, flushEvery: const Duration(milliseconds: 20));
      sink.add(line(1));
      expect(sink.fileAt(0).existsSync(), isFalse);
      sink.add(line(2));
      sink.add(line(3)); // 33 bytes pending → written
      expect(sink.fileAt(0).readAsLinesSync(), hasLength(3));
      sink.add(line(4));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sink.fileAt(0).readAsLinesSync(), hasLength(4));
      await sink.close();
    });

    test('a write error drops lines instead of throwing', () async {
      final sink = RotatingFileSink(dir);
      dir.deleteSync(recursive: true);
      sink.add(line(1));
      await expectLater(sink.flush(), completes);
      await sink.close();
      dir.createSync();
    });
  });
}
