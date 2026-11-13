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
      expect(sessB.clockSkewMs, behind);
      expect(sessA.clockSkewMs, -behind);
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
