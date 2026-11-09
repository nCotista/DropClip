import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _me = '11111111-1111-4111-8111-111111111111';
const _peer = '22222222-2222-4222-8222-222222222222';

int _n = 0;
ClipUpdate update(List<int> raw,
        {int l = 1000,
        int c = 0,
        String origin = _peer,
        ClipType type = ClipType.text,
        String? hash,
        String? blobId,
        bool concealed = false,
        int? ttl}) =>
    ClipUpdate(
      msgId: 'msg-${_n++}',
      origin: origin,
      hlc: Hlc(l: l, c: c, d: origin),
      ts: l,
      type: type,
      hash: hash ?? sha256.convert(raw).toString(),
      size: raw.length,
      isConcealed: concealed,
      ttlSeconds: ttl,
      inline: blobId == null ? Uint8List.fromList(raw) : null,
      blobId: blobId,
    );

void main() {
  late FakePorts ports;
  late SyncPolicy policy;
  late DateTime clock;
  late ClipboardSyncEngine engine;

  ClipboardSyncEngine make({bool canPush = true}) => ClipboardSyncEngine(
      myId: _me,
      ports: ports,
      policy: () => policy,
      now: () => clock,
      canPush: canPush);

  setUp(() {
    ports = FakePorts();
    policy = const SyncPolicy();
    clock = DateTime.fromMillisecondsSinceEpoch(10000);
    engine = make();
  });
  tearDown(() => engine.dispose());

  group('Inbound §10.3 (T1.9, FR-04)', () {
    test('accepted update is written after setting suppression', () async {
      final raw = utf8.encode('จากมือถือ');
      expect(await engine.onRemoteUpdate(update(raw), _peer), isTrue);
      expect(ports.written.single, raw);
      expect(engine.head!.raw, raw);
      expect(engine.hlc.l, 10000, reason: 'merged with local time');

      // The native watcher reports our own write: no echo goes out.
      engine.onLocalChange(LocalClip(ClipType.text, Uint8List.fromList(raw)));
      expect(ports.sent, isEmpty);
    });

    test('future clock beyond 60 s drift is rejected and not merged', () async {
      final u = update([1], l: 10000 + ProtocolConstants.maxClockDriftMs + 1);
      expect(await engine.onRemoteUpdate(u, _peer), isFalse);
      expect(engine.hlc.l, 0);
    });

    test('own origin, duplicates, policy and concealed are dropped', () async {
      expect(await engine.onRemoteUpdate(update([1], origin: _me), _peer),
          isFalse);
      final u = update([2]);
      expect(await engine.onRemoteUpdate(u, _peer), isTrue);
      expect(await engine.onRemoteUpdate(u, _peer), isFalse, reason: 'dup');
      policy = const SyncPolicy(types: {ClipType.url});
      expect(await engine.onRemoteUpdate(update([3], l: 2000), _peer), isFalse);
      policy = const SyncPolicy();
      expect(
          await engine.onRemoteUpdate(
              update([4], l: 3000, concealed: true), _peer),
          isFalse);
      expect(ports.written, hasLength(1));
    });

    test('Last-Writer-Wins: an older HLC never replaces the head', () async {
      await engine.onRemoteUpdate(update([9], l: 5000), _peer);
      expect(await engine.onRemoteUpdate(update([8], l: 4000), _peer), isFalse);
      expect(engine.head!.raw, [9]);
      expect(await engine.onRemoteUpdate(update([7], l: 5000, c: 1), _peer),
          isTrue);
      expect(engine.head!.raw, [7]);
    });

    test('blob content is fetched from the sender and checked', () async {
      final big = Uint8List.fromList(List.filled(40000, 65));
      ports.blobsByPeer['b1'] = big;
      final u = update(big, blobId: 'b1');
      expect(await engine.onRemoteUpdate(u, _peer), isTrue);
      expect(ports.written.single, big);
    });

    test('hash mismatch and non-image bytes are rejected with an error',
        () async {
      expect(await engine.onRemoteUpdate(update([1], hash: 'bad'), _peer),
          isFalse);
      expect(
          await engine.onRemoteUpdate(
              update([1, 2, 3], l: 2000, type: ClipType.image), _peer),
          isFalse);
      expect(ports.errors, ['E_CHECKSUM_MISMATCH', 'E_MALFORMED']);
      expect(ports.written, isEmpty);
    });

    test('PNG and JPEG magic bytes pass', () async {
      const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0];
      const jpeg = [0xFF, 0xD8, 0xFF, 0xE0];
      expect(
          await engine.onRemoteUpdate(update(png, type: ClipType.image), _peer),
          isTrue);
      expect(
          await engine.onRemoteUpdate(
              update(jpeg, l: 2000, type: ClipType.image), _peer),
          isTrue);
    });

    test('Tier 3 keeps the head but does not write the clipboard', () async {
      engine = make(canPush: false);
      expect(await engine.onRemoteUpdate(update([5]), _peer), isTrue);
      expect(engine.head!.raw, [5]);
      expect(ports.written, isEmpty);
    });

    test('one OS change reported twice is handled once (§14.1 changeToken)',
        () {
      final a = Uint8List.fromList([1]);
      engine.onLocalChange(LocalClip(ClipType.text, a, changeToken: 7));
      engine.onLocalChange(LocalClip(ClipType.text, a, changeToken: 7));
      expect(ports.sent, hasLength(1));
      // Same content, new change (a deliberate re-copy): sent again.
      clock = clock.add(const Duration(seconds: 1));
      engine.onLocalChange(LocalClip(ClipType.text, a, changeToken: 8));
      expect(ports.sent, hasLength(2));
    });

    test('merge persists debounced; dispose flushes; TTL clears', () {
      fakeAsync((async) {
        engine.onRemoteUpdate(update([1], ttl: 30), _peer);
        engine.onRemoteUpdate(update([2], l: 2000), _peer);
        async.flushMicrotasks();
        expect(ports.persisted, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(ports.persisted, hasLength(1));
        async.elapse(const Duration(seconds: 29));
        expect(ports.cleared, hasLength(1));

        engine.onRemoteUpdate(update([3], l: 3000), _peer);
        async.flushMicrotasks();
        engine.dispose();
        expect(ports.persisted, hasLength(2));
      });
    });
  });
}
