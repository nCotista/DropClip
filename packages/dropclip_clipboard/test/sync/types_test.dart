import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

ClipEntry entry(int i) => ClipEntry(
    ClipUpdate(
        msgId: 'm$i',
        origin: 'o',
        hlc: Hlc(l: i, c: 0, d: 'o'),
        ts: i,
        type: ClipType.text,
        hash: 'h$i',
        size: 0),
    Uint8List(0));

void main() {
  group('sync types (T1.9, Protocol Spec §10.1)', () {
    test('SeenIds is an LRU of the newest 200 ids', () {
      final seen = SeenIds();
      for (var i = 0; i < 250; i++) {
        expect(seen.addIfAbsent('m$i'), isTrue);
      }
      expect(seen.length, 200);
      expect(seen.addIfAbsent('m249'), isFalse, reason: 'duplicate');
      expect(seen.addIfAbsent('m0'), isTrue, reason: 'evicted');
    });

    test('History keeps the last 20 entries, oldest first', () {
      final h = History();
      for (var i = 0; i < 25; i++) {
        h.add(entry(i));
      }
      expect([for (final e in h.items) e.update.msgId],
          [for (var i = 5; i < 25; i++) 'm$i']);
      expect(() => h.items.add(entry(99)), throwsUnsupportedError);
    });

    test('SyncPolicy allows only enabled, selected types', () {
      expect(const SyncPolicy().allows(ClipType.image), isTrue);
      expect(const SyncPolicy(enabled: false).allows(ClipType.text), isFalse);
      expect(const SyncPolicy(types: {ClipType.url}).allows(ClipType.text),
          isFalse);
    });

    test('LocalClip defaults to not concealed', () {
      expect(LocalClip(ClipType.text, Uint8List(1)).isConcealed, isFalse);
    });
  });
}
