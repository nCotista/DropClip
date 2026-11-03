import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const _me = '11111111-1111-4111-8111-111111111111';

class FakePorts implements SyncPorts {
  final sent = <ClipUpdate>[];
  final blobs = <String, Uint8List>{};
  final persisted = <Hlc>[];
  final cleared = <String>[];

  @override
  void broadcast(ClipUpdate update) => sent.add(update);

  @override
  String putBlob(Uint8List raw, Duration ttl) {
    final id = 'blob-${blobs.length}';
    blobs[id] = raw;
    return id;
  }

  @override
  void persistHlc(Hlc hlc) => persisted.add(hlc);

  @override
  Future<void> clearIfStill(String hash) async => cleared.add(hash);
}

LocalClip text(String s) =>
    LocalClip(ClipType.text, Uint8List.fromList(utf8.encode(s)));

String hashOf(LocalClip c) => sha256.convert(c.raw).toString();

void main() {
  late FakePorts ports;
  late SyncPolicy policy;
  late DateTime clock;
  late ClipboardSyncEngine engine;

  setUp(() {
    ports = FakePorts();
    policy = const SyncPolicy();
    clock = DateTime.utc(2026, 11, 3, 10);
    engine = ClipboardSyncEngine(
        myId: _me, ports: ports, policy: () => policy, now: () => clock);
  });
  tearDown(() => engine.dispose());

  group('Outbound §10.2 (T1.9, FR-03A, FR-04, FR-05)', () {
    test('text is hashed, sent inline with a ticked HLC and becomes head', () {
      final clip = text('สวัสดี DropClip 👋');
      engine.onLocalChange(clip);

      final u = ports.sent.single;
      expect(u.origin, _me);
      expect(u.hash, hashOf(clip));
      expect(u.size, clip.raw.length);
      expect(u.inline, clip.raw);
      expect(u.blobId, isNull);
      expect(u.hlc.l, clock.millisecondsSinceEpoch);
      expect(ports.persisted.single, u.hlc);
      expect(engine.head!.update, same(u));
      expect(engine.seen.addIfAbsent(u.msgId), isFalse, reason: 'own id seen');
    });

    test('HLC grows on every event, even within the same millisecond', () {
      engine.onLocalChange(text('a'));
      engine.onLocalChange(text('b'));
      final [a, b] = ports.sent;
      expect(b.hlc.compareTo(a.hlc), greaterThan(0));
      expect([a.hlc.c, b.hlc.c], [0, 1]);
      expect(a.msgId, isNot(b.msgId));
    });

    test('sync off or type not allowed: nothing is sent', () {
      policy = const SyncPolicy(enabled: false);
      engine.onLocalChange(text('x'));
      policy = const SyncPolicy(types: {ClipType.text});
      engine.onLocalChange(LocalClip(ClipType.image, Uint8List(10)));
      expect(ports.sent, isEmpty);
      expect(ports.persisted, isEmpty);
    });

    test('concealed content is dropped and never logged (FR-05, NFR-S04)', () {
      final logs = <String>[];
      engine = ClipboardSyncEngine(
          myId: _me,
          ports: ports,
          policy: () => policy,
          now: () => clock,
          log: logs.add);
      engine.onLocalChange(
          LocalClip(ClipType.text, Uint8List(0), isConcealed: true));
      expect(ports.sent, isEmpty);
      expect(engine.head, isNull);
      expect(logs.single, 'clipboard.blocked_concealed type=text');
    });

    test('echo of our own write is suppressed only inside the window (§10.5)',
        () {
      final clip = text('from peer');
      engine.noteOwnWrite(hashOf(clip));
      engine.onLocalChange(clip); // watcher echo
      expect(ports.sent, isEmpty);

      engine.onLocalChange(text('new copy')); // different content in window
      expect(ports.sent, hasLength(1));

      clock = clock.add(const Duration(milliseconds: 801));
      engine.onLocalChange(clip); // deliberate re-copy after the window
      expect(ports.sent, hasLength(2));
    });

    test('> 32 KiB goes to a blob, > 32 MiB is dropped', () {
      final big = LocalClip(ClipType.image,
          Uint8List(ProtocolConstants.clipboardInlineThreshold + 1));
      engine.onLocalChange(big);
      final u = ports.sent.single;
      expect(u.inline, isNull);
      expect(ports.blobs[u.blobId], same(big.raw));

      engine.onLocalChange(LocalClip(
          ClipType.image, Uint8List(ProtocolConstants.clipboardMaxSize + 1)));
      expect(ports.sent, hasLength(1));
    });

    test('exactly 32 KiB stays inline', () {
      engine.onLocalChange(LocalClip(ClipType.text,
          Uint8List(ProtocolConstants.clipboardInlineThreshold)));
      expect(ports.sent.single.inline, isNotNull);
    });

    test('TTL clears the clipboard later only if still ours', () {
      fakeAsync((async) {
        policy = const SyncPolicy(ttlSeconds: 60);
        final clip = text('one-time code');
        engine.onLocalChange(clip);
        expect(ports.sent.single.ttlSeconds, 60);
        async.elapse(const Duration(seconds: 59));
        expect(ports.cleared, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(ports.cleared, [hashOf(clip)]);
      });
    });

    test('dispose cancels pending TTL clears', () {
      fakeAsync((async) {
        policy = const SyncPolicy(ttlSeconds: 5);
        engine.onLocalChange(text('x'));
        engine.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(ports.cleared, isEmpty);
      });
    });
  });

  group('History via the engine (§10.1)', () {
    test('history keeps the last 20 entries in order', () {
      for (var i = 0; i < 25; i++) {
        engine.onLocalChange(text('clip $i'));
      }
      final items = engine.history.items;
      expect(items, hasLength(20));
      expect(utf8.decode(items.first.raw), 'clip 5');
      expect(utf8.decode(items.last.raw), 'clip 24');
    });
  });
}
