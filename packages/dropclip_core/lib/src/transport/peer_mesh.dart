import 'dart:async';
import 'dart:io';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../security/device_identity.dart';
import '../security/trusted_device_store.dart';
import 'control_plane.dart';
import 'pinned_transport_client.dart';
import 'tls_transport_server.dart';

/// A Control Plane message from a connected peer.
typedef PeerMessage = ({String peerId, Envelope envelope});

/// Where the open link to a peer goes. [port] is the peer's listening port
/// when this device dialed it, and null when the peer dialed us.
typedef LinkAddress = ({String host, int? port});

/// The WebSocket links to paired peers (§6): one [ControlPlaneSession] each,
/// pinned on both sides, with the initiator rule (§6.2) and the §6.5 backoff.
///
/// Serve [accept] as the server's `/api/v1/ws` upgrade and call [reach]
/// whenever discovery sees a trusted peer.
class PeerMesh {
  final DeviceIdentityManager identity;
  final TrustedDeviceStore store;
  final HelloPayload Function() hello;
  final ReconnectBackoffPolicy backoff;

  /// How long one address may take to connect before the next is tried.
  final Duration dialTimeout;

  /// §6.2 rule 3: how long the non-initiator waits for the peer to dial
  /// before dialing itself, e.g. when a firewall blocks our inbound port
  /// but not the peer's.
  final Duration initiatorGrace;

  /// A link that drops sooner than this after its handshake counts as a
  /// failed attempt, so two endpoints that keep kicking each other out (the
  /// same identity running twice, §6.2 rule 4) back off instead of
  /// reconnecting every second forever.
  final Duration stableAfter;

  /// Link diagnostics for the log: `ready`, `closed`, `dial_failed`. Never
  /// carries clipboard or file content.
  final void Function(String event, Map<String, Object?> data)? onEvent;

  final _sessions = <String, ControlPlaneSession>{};
  final _links = <String, LinkAddress>{};
  final _dialing = <String>{};
  final _failures = <String, int>{};
  final _candidates = <String, List<(String, int)>>{};
  final _retry = <String, Timer>{};
  final _grace = <String, Timer>{};
  final _skew = <String, int>{};
  final _messages = StreamController<PeerMessage>.broadcast();
  final _peers = StreamController<Set<String>>.broadcast();
  final _mismatches = StreamController<String>.broadcast();
  bool _closed = false;

  PeerMesh({
    required this.identity,
    required this.store,
    required this.hello,
    ReconnectBackoffPolicy? backoff,
    this.dialTimeout = const Duration(seconds: 5),
    this.initiatorGrace = ProtocolConstants.initiatorGrace,
    this.stableAfter = const Duration(seconds: 10),
    this.onEvent,
  }) : backoff = backoff ?? ReconnectBackoffPolicy();

  Stream<PeerMessage> get messages => _messages.stream;

  /// Device ids with a finished hello handshake, on every change.
  Stream<Set<String>> get peerChanges => _peers.stream;
  Set<String> get connected => {
        for (final e in _sessions.entries)
          if (e.value.isReady) e.key
      };

  /// Peers whose `hello` carried a different `tombstones_hash` than ours
  /// (§13.2.6): the owner answers with `revocation.sync`.
  Stream<String> get tombstoneMismatches => _mismatches.stream;

  /// Where the open link to [peerId] goes, or null when there is none. The
  /// Data Plane uses it: an address a live link proves reachable beats one
  /// that was only announced (a PC announces every adapter it has).
  LinkAddress? linkAddress(String peerId) =>
      _sessions[peerId]?.isClosed == false ? _links[peerId] : null;

  String get _myId => identity.identity.deviceId;

  /// §6.2: mobile (tier 2/3) dials desktop; otherwise the smaller id dials.
  static bool shouldInitiate({
    required String myId,
    required int myTier,
    required String peerId,
    required int peerTier,
  }) {
    final meMobile = myTier > 1, peerMobile = peerTier > 1;
    if (meMobile != peerMobile) return meMobile;
    return myId.compareTo(peerId) < 0;
  }

  /// Server side: a pinned peer opened `/api/v1/ws`.
  Future<void> accept(HttpRequest request, String fp) async {
    final peer = store.getByFingerprint(fp);
    if (_closed || peer == null) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final from = request.connectionInfo?.remoteAddress.address;
    final ws = await WebSocketTransformer.upgrade(request);
    await _start(peer, ws,
        initiator: false,
        remote: from == null ? null : (host: from, port: null));
  }

  /// Discovery saw trusted [peerId] at [host]:[port]. The §6.2 initiator
  /// dials it now (or when its backoff ends); the other side waits
  /// [initiatorGrace] for the peer to dial and then dials itself (rule 3).
  ///
  /// [force] closes a session we still believe is open before dialing. A
  /// phone returning from doze has a half-open socket that Dart has not
  /// marked closed yet, so a plain [reach] would do nothing.
  Future<void> reach(String peerId, String host, int port,
      {bool force = false}) async {
    final peer = _trusted(peerId);
    if (_closed || peer == null) return;
    if (force) {
      _retry.remove(peerId)?.cancel();
      _grace.remove(peerId)?.cancel();
      _failures.remove(peerId);
      _links.remove(peerId);
      await _sessions.remove(peerId)?.shutdown(1000, 'redial');
      if (_closed || _trusted(peerId) == null) return;
      _emit();
    }
    final known = _candidates.putIfAbsent(peerId, () => []);
    final isNew = !known.contains((host, port));
    if (isNew) {
      // Newest first; a PC with several adapters is announced once per
      // adapter, so the last few are kept and tried in turn.
      known.insert(0, (host, port));
      if (known.length > 3) known.removeLast();
    }
    if (_sessions[peerId]?.isClosed == false) return;
    final myTier = hello().tier;
    if (!shouldInitiate(
        myId: _myId, myTier: myTier, peerId: peerId, peerTier: peer.tier)) {
      // A phone has no server to dial; only desktops fall back.
      if (myTier == 1 && peer.tier == 1) _armGrace(peerId);
      return;
    }
    if (isNew) _retry.remove(peerId)?.cancel();
    if (_retry.containsKey(peerId)) return; // backing off (§6.5)
    await _dial(peerId);
  }

  TrustedDevice? _trusted(String peerId) {
    final d = store.getByDeviceId(peerId);
    return d != null && d.status == 'active' ? d : null;
  }

  void _armGrace(String peerId) {
    if (_closed || _grace.containsKey(peerId)) return;
    _grace[peerId] = Timer(initiatorGrace, () {
      _grace.remove(peerId);
      if (_retry.containsKey(peerId)) return;
      unawaited(_dial(peerId));
    });
  }

  /// Tries every known address of [peerId] once; on failure retries with
  /// backoff. Does nothing while a link is open or another dial is running.
  Future<void> _dial(String peerId) async {
    final peer = _trusted(peerId);
    final known = _candidates[peerId];
    if (_closed || peer == null || known == null || known.isEmpty) return;
    if (_dialing.contains(peerId)) return;
    if (_sessions[peerId]?.isClosed == false) return;
    _retry.remove(peerId)?.cancel();
    _dialing.add(peerId);
    try {
      Object? lastError;
      for (final at in List.of(known)) {
        PinnedTransportClient? client;
        try {
          // Inside the try: if reading the key fails (e.g. the iOS keychain
          // right after launch) the peer must still be retried, or it stays
          // offline until the app restarts.
          client = await PinnedTransportClient.forIdentity(
              identity: identity, store: store, expectedFp: peer.fp);
          client.httpClient.connectionTimeout = dialTimeout;
          final ws = await client
              .connectWebSocket(Uri(
                  scheme: 'wss',
                  host: at.$1,
                  port: at.$2,
                  path: kWebSocketPath))
              .timeout(dialTimeout * 2);
          unawaited(ws.done.whenComplete(client.close));
          if (_closed) {
            await ws.close(1000, 'closing');
            return;
          }
          // The address that works goes first next time.
          known
            ..remove(at)
            ..insert(0, at);
          await _start(peer, ws,
              initiator: true, remote: (host: at.$1, port: at.$2));
          return;
        } on Object catch (e) {
          lastError = e;
          client?.close(force: true);
        }
        if (_closed) return;
      }
      onEvent?.call('dial_failed', {
        'peer': peerId,
        'addresses': [for (final a in known) '${a.$1}:${a.$2}'],
        'error': lastError.runtimeType.toString(),
      });
      _retryLater(peerId, failed: true);
    } finally {
      _dialing.remove(peerId);
    }
  }

  /// §6.5: 1, 2, 4, 8, 16, 30 s; the counter resets after a stable link.
  void _retryLater(String peerId, {required bool failed}) {
    if (_closed) return;
    if (!failed) _failures.remove(peerId);
    final n =
        failed ? _failures.update(peerId, (v) => v + 1, ifAbsent: () => 0) : 0;
    _retry[peerId]?.cancel();
    _retry[peerId] = Timer(backoff.delayForAttempt(n), () {
      _retry.remove(peerId);
      unawaited(_dial(peerId));
    });
  }

  /// Sends [env] unchanged to every connected peer (or only [to]). A link
  /// that fails mid-send is skipped; it closes and reconnects by itself.
  Future<void> broadcast(Envelope env, {String? to}) async {
    for (final e in _sessions.entries.toList()) {
      if ((to == null || e.key == to) && e.value.isReady) {
        try {
          await e.value.forward(env);
        } on Object {
          // Closed between the check and the send.
        }
      }
    }
  }

  Future<void> _start(TrustedDevice peer, WebSocket ws,
      {required bool initiator, LinkAddress? remote}) async {
    final peerId = peer.deviceId;
    final old = _sessions[peerId];
    if (old != null && !old.isClosed) {
      // §6.2 rule 4: keep the link the rightful initiator opened.
      final rightful = shouldInitiate(
              myId: _myId,
              myTier: hello().tier,
              peerId: peerId,
              peerTier: peer.tier) ==
          initiator;
      if (!rightful) {
        await ws.close(4001, 'duplicate connection');
        return;
      }
      await old.shutdown(4001, 'duplicate connection');
    }
    final opened = Stopwatch()..start();
    Duration? readyAt;
    late ControlPlaneSession session;
    session = ControlPlaneSession(
      localHello: hello(),
      channel: _WebSocketChannel(ws),
      initialClock: Hlc.now(_myId),
      // What the last session measured, so our `hello` is already stamped
      // in the peer's clock (a peer without clock compensation rejects it
      // otherwise when we are ahead).
      initialClockSkewMs: initiator ? (_skew[peerId] ?? 0) : 0,
      onTombstoneMismatch: (_) => _mismatches.add(peerId),
      onMessage: (env) {
        if (env.origin == _myId) return;
        _messages.add((peerId: peerId, envelope: env));
      },
      onClosed: (code, reason) {
        if (session.clockSkewMeasured) _skew[peerId] = session.clockSkewMs;
        final lived = opened.elapsed;
        // `readyAt` is set by polling, so a link that closes within a few
        // ms of its handshake has none yet: ask the session itself.
        final wasReady = session.remoteHello != null;
        final readyFor = readyAt == null ? Duration.zero : lived - readyAt!;
        final stable = wasReady && readyFor >= stableAfter;
        onEvent?.call('closed', {
          'peer': peerId,
          'code': ws.closeCode ?? code,
          'reason': ws.closeReason ?? reason,
          'ready': wasReady,
          'lived_ms': lived.inMilliseconds,
          'we_dialed': initiator,
        });
        if (identical(_sessions[peerId], session)) {
          _sessions.remove(peerId);
          _links.remove(peerId);
          if (!_closed && _trusted(peerId) != null) {
            if (initiator) {
              _retryLater(peerId, failed: !stable);
            } else if (hello().tier == 1 && peer.tier == 1) {
              // The peer redials; if it cannot, we do after the grace.
              _armGrace(peerId);
            }
          }
        }
        _emit();
      },
    );
    _sessions[peerId] = session;
    if (remote != null) _links[peerId] = remote;
    _retry.remove(peerId)?.cancel();
    _grace.remove(peerId)?.cancel();
    await session.start(sendInitialHello: initiator);
    unawaited(_whenReady(session, peerId, initiator, () {
      readyAt = opened.elapsed;
    }));
  }

  Future<void> _whenReady(ControlPlaneSession s, String peerId, bool initiator,
      void Function() markReady) async {
    for (var i = 0; i < 100 && !s.isReady && !s.isClosed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!s.isReady && !s.isClosed) {
      await s.shutdown(4000, 'hello timeout'); // §6.3
    } else if (s.isReady && s.remoteHello!.deviceId != peerId) {
      await s.shutdown(4004, 'device id does not match pinned cert');
    } else if (s.isReady) {
      markReady();
      // The peer renamed itself: show the name it now uses (§7.4 hello).
      final known = store.getByDeviceId(peerId);
      final name = s.remoteHello!.name.trim();
      if (known != null && name.isNotEmpty && known.name != name) {
        await store.upsert(known.copyWith(name: name));
      }
      if (s.clockSkewMeasured) _skew[peerId] = s.clockSkewMs;
      onEvent?.call('ready', {
        'peer': peerId,
        'we_dialed': initiator,
        'clock_offset_ms': s.clockSkewMs,
        'address': _links[peerId]?.host,
      });
    }
    _emit();
  }

  void _emit() {
    if (!_closed) _peers.add(connected);
  }

  /// Closes the link to [peerId] with [code] (e.g. 4004 after a revoke) and
  /// stops dialing it.
  Future<void> drop(String peerId, int code) async {
    _retry.remove(peerId)?.cancel();
    _grace.remove(peerId)?.cancel();
    _candidates.remove(peerId);
    _failures.remove(peerId);
    _links.remove(peerId);
    await _sessions.remove(peerId)?.shutdown(code, 'dropped');
    _emit();
  }

  Future<void> close() async {
    _closed = true;
    for (final t in [..._retry.values, ..._grace.values]) {
      t.cancel();
    }
    _retry.clear();
    _grace.clear();
    for (final s in _sessions.values.toList()) {
      await s.shutdown(1000, 'closing');
    }
    _sessions.clear();
    _links.clear();
    await _messages.close();
    await _peers.close();
    await _mismatches.close();
  }
}

class _WebSocketChannel implements ControlSocketChannel {
  final WebSocket _ws;

  _WebSocketChannel(this._ws);

  @override
  Stream<String> get incoming => _ws.where((f) => f is String).cast<String>();

  @override
  Future<void> sendFrame(String rawFrame) async => _ws.add(rawFrame);

  @override
  Future<void> close(int code, String reason) => _ws.close(code, reason);
}
