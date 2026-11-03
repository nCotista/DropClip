import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const _localId = '00000000-0000-4000-8000-000000000000';
const _peerId = '550e8400-e29b-41d4-a716-446655440000';
const _register = 'register _dropclip._tcp/$_localId:53317';
const _fp = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

class _FakeBackend implements MdnsBackend {
  final events = StreamController<MdnsEvent>.broadcast();
  final network = StreamController<void>.broadcast();
  final calls = <String>[];
  Map<String, String>? registeredTxt;

  /// When set, [unregister] blocks until it completes.
  Completer<void>? unregisterGate;

  @override
  Future<void> register({
    required String serviceType,
    required String instanceName,
    required int port,
    required Map<String, String> txt,
  }) async {
    calls.add('register $serviceType/$instanceName:$port');
    registeredTxt = txt;
  }

  @override
  Future<void> unregister() async {
    calls.add('unregister');
    await unregisterGate?.future;
  }

  @override
  Stream<MdnsEvent> browse(String serviceType) {
    calls.add('browse $serviceType');
    return events.stream;
  }

  @override
  Future<void> query() async => calls.add('query');

  @override
  Stream<void> get networkChanges => network.stream;

  void close() {
    events.close();
    network.close();
  }
}

DiscoveryRecord _record(String id) => DiscoveryRecord(
      deviceId: id,
      name: 'โน้ตบุ๊ก 💻',
      os: DeviceOs.windows,
      port: 53317,
      fingerprint: _fp,
    );

MdnsResolved _resolved({
  String instance = _peerId,
  String address = '192.168.1.10',
  int srvPort = 53317,
  Map<String, String?>? txt,
}) =>
    MdnsResolved(instance,
        address: address,
        srvPort: srvPort,
        txt: txt ?? _record(_peerId).toTxt());

void main() {
  late _FakeBackend backend;
  late PeerCache cache;
  late DiscoveryService service;
  late List<String> debug;

  void setUpService(Duration Function() elapsed, {Duration? queryInterval}) {
    backend = _FakeBackend();
    addTearDown(backend.close);
    cache = PeerCache(
      localDeviceId: _localId,
      trustedFingerprint: (id) => id == _peerId ? _fp : null,
      now: () => DateTime.utc(2026, 11, 2).add(elapsed()),
    );
    debug = [];
    service = DiscoveryService(
      backend: backend,
      cache: cache,
      record: _record(_localId),
      queryInterval: queryInterval ?? const Duration(seconds: 10),
      onDebug: debug.add,
    );
  }

  /// Runs [body] in fake time with the service already started.
  void fakeTest(String name, void Function(FakeAsync async) body) {
    test(name, () {
      fakeAsync((async) {
        setUpService(() => async.elapsed);
        service.start();
        async.flushMicrotasks();
        body(async);
      });
    });
  }

  void emit(FakeAsync async, List<MdnsEvent> events) {
    events.forEach(backend.events.add);
    async.flushMicrotasks();
  }

  group('DiscoveryService (T1.1, PROTO-DC-V2.0 §3.1–§3.3)', () {
    fakeTest('start registers instance=device_id with TXT, then browses', (_) {
      expect(service.isRunning, isTrue);
      expect(backend.calls, [_register, 'browse _dropclip._tcp']);
      expect(DiscoveryRecord.tryParse(backend.registeredTxt!)!.name,
          'โน้ตบุ๊ก 💻');
    });

    fakeTest('resolved peer lands in the cache as trusted_online', (async) {
      emit(async, [_resolved()]);
      final peer = cache[_peerId]!;
      expect(peer.state, PeerState.trustedOnline);
      expect(peer.address, '192.168.1.10');
      expect(peer.record.name, 'โน้ตบุ๊ก 💻');
    });

    fakeTest('re-queries every 10s and sweeps stale (30s) / removed (120s)',
        (async) {
      emit(async, [_resolved()]);
      async.elapse(const Duration(seconds: 10));
      expect(backend.calls.where((c) => c == 'query'), hasLength(1));
      async.elapse(const Duration(seconds: 30));
      expect(cache[_peerId]!.state, PeerState.stale);
      async.elapse(const Duration(seconds: 90));
      expect(cache[_peerId], isNull);
      expect(backend.calls.where((c) => c == 'query'), hasLength(13));
    });

    fakeTest('goodbye removes the peer immediately', (async) {
      emit(async, [_resolved(), MdnsLost(_peerId.toUpperCase())]);
      expect(cache[_peerId], isNull);
    });

    fakeTest('malformed, id/instance mismatch, SRV mismatch, own: dropped',
        (async) {
      emit(async, [
        _resolved(txt: {'v': '1', 'id': 'nope'}),
        _resolved(instance: _localId),
        _resolved(srvPort: 53318),
        _resolved(instance: _localId, txt: _record(_localId).toTxt()),
      ]);
      expect(cache.peers, isEmpty);
      expect(debug, [
        contains('malformed'),
        contains('mismatch'),
        contains('ignored'),
        contains('ignored'),
      ]);
    });

    fakeTest('IP change of the same device updates the existing entry',
        (async) {
      emit(async, [_resolved(), _resolved(address: '10.0.0.7')]);
      expect(cache.peers, hasLength(1));
      expect(cache[_peerId]!.address, '10.0.0.7');
    });

    fakeTest('network change re-announces once within 5s, bursts collapse',
        (async) {
      backend.calls.clear();
      for (var i = 0; i < 3; i++) {
        backend.network.add(null);
      }
      async.elapse(const Duration(seconds: 5));
      expect(backend.calls, ['unregister', _register, 'query']);
    });

    // `stop()` awaits subscription cancels that complete in the root zone,
    // which FakeAsync cannot flush, so these run in real time.
    test('stop sends goodbye, cancels timers and ignores later events',
        () async {
      setUpService(() => Duration.zero,
          queryInterval: const Duration(milliseconds: 5));
      await service.start();
      await service.stop();
      expect(backend.calls.last, 'unregister');
      backend.calls.clear();

      backend.events.add(_resolved());
      backend.network.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(service.isRunning, isFalse);
      expect(backend.calls, isEmpty);
      expect(cache.peers, isEmpty);
    });

    test('start and stop are idempotent', () async {
      setUpService(() => Duration.zero);
      await service.stop();
      await Future.wait([service.start(), service.start()]);
      await Future.wait([service.stop(), service.stop()]);
      expect(
          backend.calls.where((c) => c.startsWith('register')), hasLength(1));
      expect(backend.calls.where((c) => c == 'unregister'), hasLength(1));
    });

    test('stop during an in-flight re-announce does not re-register', () async {
      setUpService(() => Duration.zero);
      await service.start();
      backend.calls.clear();
      final gate = backend.unregisterGate = Completer<void>();
      backend.network.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, ['unregister']);

      final stopping = service.stop();
      backend.unregisterGate = null;
      gate.complete();
      await stopping;
      expect(backend.calls, ['unregister', 'unregister']);
    });
  });
}
