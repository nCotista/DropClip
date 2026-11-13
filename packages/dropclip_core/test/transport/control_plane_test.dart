import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

class _InMemoryControlChannel implements ControlSocketChannel {
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final List<String> sentFrames = <String>[];
  int? closedCode;
  String? closedReason;
  _InMemoryControlChannel? peer;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> sendFrame(String rawFrame) async {
    sentFrames.add(rawFrame);
    peer?._incoming.add(rawFrame);
  }

  @override
  Future<void> close(int code, String reason) async {
    closedCode = code;
    closedReason = reason;
    await _incoming.close();
  }
}

HelloPayload _hello({
  required String id,
  int v = 2,
  int minV = 1,
  String tombstonesHash = 'hash-a',
}) =>
    HelloPayload(
      deviceId: id,
      name: 'Node $id',
      os: 'macos',
      tier: 1,
      v: v,
      minV: minV,
      appVersion: '2.0.0',
      capabilities: const <String>['clipboard', 'file'],
      tombstonesHash: tombstonesHash,
      tombstoneCount: 0,
    );

void main() {
  const idA = '11111111-1111-4111-8111-111111111111';
  const idB = '22222222-2222-4222-8222-222222222222';

  group('ControlPlaneSession & ReconnectEngine (T1.5)', () {
    test('completes hello/hello.ack handshake and exchanges messages',
        () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;

      HelloPayload? mismatchOnA;
      final receivedOnB = <Envelope>[];

      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA, tombstonesHash: 'hash-1'),
        channel: chanA,
        initialClock: Hlc(l: 1000, c: 0, d: idA),
        nowMs: () => 1000,
        onTombstoneMismatch: (r) => mismatchOnA = r,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB, tombstonesHash: 'hash-2'),
        channel: chanB,
        initialClock: Hlc(l: 1000, c: 0, d: idB),
        nowMs: () => 1000,
        onMessage: receivedOnB.add,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);

      expect(sessA.isReady, isTrue);
      expect(sessB.isReady, isTrue);
      expect(sessA.negotiatedVersion, equals(2));
      expect(mismatchOnA?.deviceId, equals(idB));

      await sessA.sendEnvelope(
        MessageType.clipboardClear,
        const <String, dynamic>{'reason': 'manual'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(receivedOnB, hasLength(1));
      expect(receivedOnB.first.type, equals(MessageType.clipboardClear));

      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    test('peers whose clocks are 10 minutes apart still connect and sync',
        () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;
      const behind = 10 * 60 * 1000;
      final receivedOnA = <Envelope>[];
      final receivedOnB = <Envelope>[];

      // A has the right time; B's clock is 10 minutes slow.
      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chanA,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => 1000000,
        onMessage: receivedOnA.add,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB),
        channel: chanB,
        initialClock: Hlc(l: 1000000 - behind, c: 0, d: idB),
        nowMs: () => 1000000 - behind,
        onMessage: receivedOnB.add,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);

      // Before: B dropped A's frames as > 60 s in the future and never
      // finished the handshake.
      expect(sessA.isReady, isTrue);
      expect(sessB.isReady, isTrue);
      // B measured the whole offset from A's hello and answers in A's
      // clock, so A has nothing left to compensate.
      expect(sessB.clockSkewMs, behind);
      expect(sessA.clockSkewMs, 0);
      expect(chanB.closedCode, isNull);

      await sessA.sendEnvelope(
        MessageType.clipboardClear,
        const <String, dynamic>{'reason': 'manual'},
      );
      await sessB.sendEnvelope(
        MessageType.clipboardClear,
        const <String, dynamic>{'reason': 'manual'},
      );
      await Future<void>.delayed(Duration.zero);

      // Each side sees the other's timestamps in its own clock.
      expect(receivedOnB.single.ts, 1000000 - behind);
      expect(receivedOnB.single.hlc.l, 1000000 - behind);
      expect(receivedOnA.single.ts, 1000000);
      expect(receivedOnA.single.hlc.l, 1000000);

      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    test('a few seconds of clock difference is left alone', () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;

      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chanA,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => 1000000,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB),
        channel: chanB,
        initialClock: Hlc(l: 997000, c: 0, d: idB),
        nowMs: () => 997000,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);

      expect(sessB.isReady, isTrue);
      expect(sessA.clockSkewMs, 0);
      expect(sessB.clockSkewMs, 0);
      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    test('a frame > 60 s ahead after the handshake is still rejected',
        () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;
      var nowA = 1000000;
      final receivedOnB = <Envelope>[];

      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chanA,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => nowA,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB),
        channel: chanB,
        initialClock: Hlc(l: 1000000, c: 0, d: idB),
        nowMs: () => 1000000,
        onMessage: receivedOnB.add,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);
      expect(sessB.clockSkewMs, 0);

      // A jumps 2 minutes ahead mid-session: the §10.3 bound still holds.
      nowA += 2 * 60 * 1000;
      await sessA.sendEnvelope(
        MessageType.clipboardClear,
        const <String, dynamic>{'reason': 'manual'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(receivedOnB, isEmpty);

      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    test('rejects hello when clock difference exceeds 24 hours', () async {
      const overMax = 25 * 60 * 60 * 1000;
      const baseNow = 200000000;
      for (final offset in const <int>[overMax, -overMax]) {
        final chanA = _InMemoryControlChannel();
        final chanB = _InMemoryControlChannel();
        chanA.peer = chanB;
        chanB.peer = chanA;

        final sessA = ControlPlaneSession(
          localHello: _hello(id: idA),
          channel: chanA,
          initialClock: Hlc(l: baseNow + offset, c: 0, d: idA),
          nowMs: () => baseNow + offset,
        );
        final sessB = ControlPlaneSession(
          localHello: _hello(id: idB),
          channel: chanB,
          initialClock: Hlc(l: baseNow, c: 0, d: idB),
          nowMs: () => baseNow,
        );

        await sessB.start(sendInitialHello: false);
        await sessA.start(sendInitialHello: true);
        await Future<void>.delayed(Duration.zero);

        expect(sessB.isReady, isFalse);
        expect(sessB.clockSkewMs, 0);
        expect(
          chanB.sentFrames.any((f) => f.contains('"code":"E_MALFORMED"')),
          isTrue,
        );

        await sessA.shutdown(1000, 'done');
        await sessB.shutdown(1000, 'done');
      }
    });

    test('duplicate hello after handshake cannot change clock skew', () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;
      var nowA = 1000000;
      final receivedOnB = <Envelope>[];

      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chanA,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => nowA,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB),
        channel: chanB,
        initialClock: Hlc(l: 1000000, c: 0, d: idB),
        nowMs: () => 1000000,
        onMessage: receivedOnB.add,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);
      expect(sessB.clockSkewMs, 0);

      // A sends a second hello with +30 s ts, then jumps +70 s ahead.
      nowA = 1030000;
      await sessA.sendEnvelope(MessageType.hello, _hello(id: idA).toJson());
      await Future<void>.delayed(Duration.zero);
      expect(sessB.clockSkewMs, 0);

      nowA = 1070000;
      await sessA.sendEnvelope(
        MessageType.clipboardClear,
        const <String, dynamic>{'reason': 'manual'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(receivedOnB, isEmpty);

      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    // A peer running a build without clock compensation: it stamps frames
    // in its own clock and rejects anything > 60 s ahead of it (§10.3).
    Envelope legacyFrame(MessageType type, int nowMs, String id) => Envelope(
          type: type,
          msgId: '00000000-0000-4000-8000-0000000000${nowMs % 90 + 10}',
          origin: id,
          hlc: Hlc(l: nowMs, c: 0, d: id),
          ts: nowMs,
          payload: type == MessageType.error
              ? const ProtocolException(
                      ProtocolErrorCode.malformed, 'clock drift exceeds 60s')
                  .toWsPayload()
              : _hello(id: id).toJson(),
        );
    void legacyAccepts(String wire, int legacyNowMs) {
      final env = Envelope.decodeWire(wire);
      // The old receiver's check; throws ClockDriftException when violated.
      Hlc(l: legacyNowMs, c: 0, d: idB).merge(env.hlc, legacyNowMs);
      expect((env.ts - legacyNowMs).abs(), lessThan(1000));
    }

    test('an old peer with a slow clock accepts everything we send', () async {
      const legacyNow = 400000; // 10 minutes behind us
      final chan = _InMemoryControlChannel();
      final legacy = _InMemoryControlChannel()..peer = chan;
      final received = <Envelope>[];
      final sess = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chan,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => 1000000,
        onMessage: received.add,
      );
      await sess.start(sendInitialHello: false);

      await legacy.sendFrame(
          legacyFrame(MessageType.hello, legacyNow, idB).encodeWire());
      await Future<void>.delayed(Duration.zero);
      expect(sess.isReady, isTrue);
      expect(sess.clockSkewMs, legacyNow - 1000000);

      // Before: this hello_ack was 10 minutes in the old peer's future, so
      // it dropped it, never finished the handshake and hung up after 5 s.
      legacyAccepts(chan.sentFrames.single, legacyNow);

      await sess
          .sendEnvelope(MessageType.clipboardClear, const {'reason': 'manual'});
      await sess.forward(Envelope(
          type: MessageType.clipboardClear,
          msgId: '00000000-0000-4000-8000-0000000000aa',
          origin: idA,
          hlc: Hlc(l: 1000000, c: 3, d: idA),
          ts: 1000000,
          payload: const {'reason': 'manual'}));
      for (final wire in chan.sentFrames) {
        legacyAccepts(wire, legacyNow);
      }

      // And its frames reach us in our clock.
      await legacy.sendFrame(Envelope(
          type: MessageType.clipboardClear,
          msgId: '00000000-0000-4000-8000-0000000000ab',
          origin: idB,
          hlc: Hlc(l: legacyNow, c: 0, d: idB),
          ts: legacyNow,
          payload: const {'reason': 'manual'}).encodeWire());
      await Future<void>.delayed(Duration.zero);
      expect(received.single.ts, 1000000);
      await sess.shutdown(1000, 'done');
    });

    test('an old peer that rejects our hello tells us its clock for the retry',
        () async {
      const legacyNow = 400000; // we are 10 minutes ahead of it
      final chan = _InMemoryControlChannel();
      final legacy = _InMemoryControlChannel()..peer = chan;
      final first = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chan,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => 1000000,
      );
      await first.start(sendInitialHello: true);
      // Our hello is in its future: it answers with an error and waits.
      expect(() => legacyAccepts(chan.sentFrames.single, legacyNow),
          throwsA(isA<ClockDriftException>()));
      await legacy.sendFrame(
          legacyFrame(MessageType.error, legacyNow, idB).encodeWire());
      await Future<void>.delayed(Duration.zero);

      expect(first.isClosed, isTrue);
      expect(first.clockSkewMeasured, isTrue);
      expect(first.clockSkewMs, legacyNow - 1000000);

      // The next attempt starts from that offset: hello is in its clock.
      final chan2 = _InMemoryControlChannel();
      final retry = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chan2,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => 1000000,
        initialClockSkewMs: first.clockSkewMs,
      );
      await retry.start(sendInitialHello: true);
      legacyAccepts(chan2.sentFrames.single, legacyNow);
      await retry.shutdown(1000, 'done');
    });

    test('two new builds agree even when one starts from a stale offset',
        () async {
      // B believes A is 10 minutes ahead (true last time); the clocks have
      // since been corrected and are equal.
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;
      final onA = <Envelope>[], onB = <Envelope>[];
      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chanA,
        initialClock: Hlc(l: 1000000, c: 0, d: idA),
        nowMs: () => 1000000,
        onMessage: onA.add,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB),
        channel: chanB,
        initialClock: Hlc(l: 1000000, c: 0, d: idB),
        nowMs: () => 1000000,
        initialClockSkewMs: 600000,
        onMessage: onB.add,
      );
      await sessA.start(sendInitialHello: false);
      await sessB.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);
      expect(sessA.isReady && sessB.isReady, isTrue);

      await sessA
          .sendEnvelope(MessageType.clipboardClear, const {'reason': 'manual'});
      await sessB
          .sendEnvelope(MessageType.clipboardClear, const {'reason': 'manual'});
      await Future<void>.delayed(Duration.zero);
      // The two wrong offsets cancel: both sides see true local time.
      expect(onA.single.ts, 1000000);
      expect(onB.single.ts, 1000000);
      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    test('closes with 4003 E_UNSUPPORTED_VERSION on incompatible version',
        () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;

      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA, v: 2, minV: 2),
        channel: chanA,
        initialClock: Hlc(l: 1000, c: 0, d: idA),
        nowMs: () => 1000,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB, v: 1, minV: 1),
        channel: chanB,
        initialClock: Hlc(l: 1000, c: 0, d: idB),
        nowMs: () => 1000,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);

      expect(
        chanB.closedCode,
        equals(VersionNegotiator.wsCloseUnsupportedVersion),
      );
      await sessA.shutdown(1000, 'cleanup');
    });

    test('replies with pong to ping and enforces 64 KiB frame limit', () async {
      final chanA = _InMemoryControlChannel();
      final chanB = _InMemoryControlChannel();
      chanA.peer = chanB;
      chanB.peer = chanA;

      final sessA = ControlPlaneSession(
        localHello: _hello(id: idA),
        channel: chanA,
        initialClock: Hlc(l: 1000, c: 0, d: idA),
        nowMs: () => 1000,
      );
      final sessB = ControlPlaneSession(
        localHello: _hello(id: idB),
        channel: chanB,
        initialClock: Hlc(l: 1000, c: 0, d: idB),
        nowMs: () => 1000,
      );

      await sessB.start(sendInitialHello: false);
      await sessA.start(sendInitialHello: true);
      await Future<void>.delayed(Duration.zero);

      await sessA.sendPing();
      await Future<void>.delayed(Duration.zero);
      expect(
        chanB.sentFrames.any((f) => f.contains('"type":"pong"')),
        isTrue,
      );

      final huge = 'x' * 70000;
      expect(
        () => sessA.sendEnvelope(
          MessageType.clipboardClear,
          <String, dynamic>{'pad': huge},
        ),
        throwsA(isA<ProtocolException>()),
      );

      await sessA.shutdown(1000, 'done');
      await sessB.shutdown(1000, 'done');
    });

    test('ReconnectBackoffPolicy & ControlPlaneReconnectEngine recover',
        () async {
      final policy = ReconnectBackoffPolicy(jitterFraction: 0);
      expect(policy.delayForAttempt(0), equals(const Duration(seconds: 1)));
      expect(policy.delayForAttempt(1), equals(const Duration(seconds: 2)));
      expect(policy.delayForAttempt(4), equals(const Duration(seconds: 16)));
      expect(policy.delayForAttempt(99), equals(const Duration(seconds: 30)));

      var tries = 0;
      final recordedDelays = <Duration>[];
      final engine = ControlPlaneReconnectEngine(
        backoff: policy,
        maxAttempts: 5,
        connectFactory: () async {
          tries++;
          if (tries < 3) {
            throw StateError('transient network drop');
          }
          return ControlPlaneSession(
            localHello: _hello(id: idA),
            channel: _InMemoryControlChannel(),
            initialClock: Hlc(l: 1000, c: 0, d: idA),
          );
        },
      );

      final connected = await engine.connectWithRetry(
        waitFn: (d) async => recordedDelays.add(d),
      );
      expect(connected, isNotNull);
      expect(tries, equals(3));
      expect(
        recordedDelays,
        equals(const <Duration>[Duration(seconds: 1), Duration(seconds: 2)]),
      );
      await engine.stop();
    });
  });
}
