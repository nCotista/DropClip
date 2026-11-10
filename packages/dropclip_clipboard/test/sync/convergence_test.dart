import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

/// Deterministic cluster simulation: one global time, per-node clock skew,
/// random delivery delays (so messages arrive out of order), and a native
/// watcher that echoes every clipboard write back as a local change.
class _Sim {
  final Random rnd;
  final List<_Node> nodes = [];
  final List<_Event> queue = [];
  int t = 1700000000000;
  int broadcasts = 0, writes = 0, echoes = 0;

  _Sim(int seed, List<int> skewsMs) : rnd = Random(seed) {
    for (var i = 0; i < skewsMs.length; i++) {
      nodes.add(
          _Node(this, '0000000$i-0000-4000-8000-000000000000', skewsMs[i]));
    }
  }

  void schedule(int at, Future<void> Function() run) =>
      queue.add(_Event(at, queue.length, run));

  Future<void> runUntilIdle() async {
    while (queue.isNotEmpty) {
      queue.sort((a, b) =>
          a.at != b.at ? a.at.compareTo(b.at) : a.seq.compareTo(b.seq));
      final e = queue.removeAt(0);
      if (e.at > t) t = e.at;
      await e.run();
    }
  }
}

class _Event {
  final int at, seq;
  final Future<void> Function() run;
  _Event(this.at, this.seq, this.run);
}

class _Node implements SyncPorts {
  final _Sim sim;
  final String id;
  final int skewMs;
  late final ClipboardSyncEngine engine = ClipboardSyncEngine(
    myId: id,
    ports: this,
    policy: () => const SyncPolicy(),
    now: () => DateTime.fromMillisecondsSinceEpoch(sim.t + skewMs),
    random: Random(id.hashCode),
  );

  _Node(this.sim, this.id, this.skewMs);

  /// What the OS clipboard holds right now, and its change counter.
  Uint8List os = Uint8List(0);
  int seq = 0;

  /// The watcher reports the clipboard as it is when it fires.
  void watcherFires() =>
      engine.onLocalChange(LocalClip(ClipType.text, os, changeToken: seq));

  /// The user copies [raw]: the OS clipboard changes and the watcher fires.
  void userCopy(Uint8List raw) {
    os = raw;
    seq++;
    watcherFires();
  }

  @override
  void broadcast(ClipUpdate update) {
    sim.broadcasts++;
    for (final peer in sim.nodes) {
      if (peer == this) continue;
      // 0–80 ms network delay: later messages often overtake earlier ones.
      sim.schedule(sim.t + sim.rnd.nextInt(80),
          () => peer.engine.onRemoteUpdate(update, id));
    }
  }

  @override
  Future<void> writeClipboard(ClipType type, Uint8List raw) async {
    sim.writes++;
    os = raw;
    seq++;
    // The watcher reports the change within the 800 ms window and, like the
    // real watchers (GetClipboardData / NSPasteboard), reads what the
    // clipboard holds *when it fires* — a newer write or copy may have
    // replaced it by then.
    sim.schedule(sim.t + sim.rnd.nextInt(300), () async {
      sim.echoes++;
      watcherFires();
    });
  }

  @override
  String putBlob(Uint8List raw, Duration ttl) => throw UnimplementedError();
  @override
  Future<Uint8List> fetchBlob(String peer, String blobId) =>
      throw UnimplementedError();
  @override
  void persistHlc(Hlc hlc) {}
  @override
  Future<void> clearIfStill(String hash) async {}
  @override
  void sendError(String peer, String code, ClipUpdate update) =>
      throw StateError('unexpected $code');
}

void main() {
  for (final seed in [1, 2, 3]) {
    test('4 devices, 1,000 copies converge with no loop (NFR-RE02), seed $seed',
        () async {
      // One device 30 s behind, one 20 s ahead (both within MAX_CLOCK_DRIFT).
      final sim = _Sim(seed, [0, -30000, 20000, 5]);
      final all = <ClipUpdate>[];
      var at = sim.t;
      for (var i = 0; i < 1000; i++) {
        final node = sim.nodes[sim.rnd.nextInt(4)];
        // Copies 0–40 ms apart, so many race with in-flight updates.
        at += sim.rnd.nextInt(40);
        sim.schedule(
            at,
            () async => node.userCopy(
                Uint8List.fromList(utf8.encode('copy $i on ${node.id}'))));
      }
      // Record every update that goes on the wire.
      await sim.runUntilIdle();
      for (final n in sim.nodes) {
        all.addAll(n.engine.history.items.map((e) => e.update));
      }

      // No loop: only user copies were broadcast; every echo was suppressed.
      expect(sim.broadcasts, 1000);
      expect(sim.echoes, sim.writes);

      // Everyone ends on the same value…
      final heads = {for (final n in sim.nodes) n.engine.head!.update.msgId};
      expect(heads, hasLength(1));
      // …which is the highest HLC ever accepted (Last-Writer-Wins).
      final winner = sim.nodes.first.engine.head!.update;
      for (final u in all) {
        expect(u.hlc.compareTo(winner.hlc), lessThanOrEqualTo(0));
      }
      expect(sim.nodes.map((n) => utf8.decode(n.engine.head!.raw)).toSet(),
          hasLength(1));
    });
  }
}
