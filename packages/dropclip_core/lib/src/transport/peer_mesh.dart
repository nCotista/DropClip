import 'dart:async';
import 'dart:io';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../security/device_identity.dart';
import '../security/trusted_device_store.dart';
import 'control_plane.dart';
import 'pinned_transport_client.dart';

/// A Control Plane message from a connected peer.
typedef PeerMessage = ({String peerId, Envelope envelope});

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

  final _sessions = <String, ControlPlaneSession>{};
  final _dialing = <String>{};
  final _failures = <String, int>{};
  final _addresses = <String, (String, int)>{};
  final _messages = StreamController<PeerMessage>.broadcast();
  final _peers = StreamController<Set<String>>.broadcast();
  bool _closed = false;

  PeerMesh({
    required this.identity,
    required this.store,
    required this.hello,
    ReconnectBackoffPolicy? backoff,
  }) : backoff = backoff ?? ReconnectBackoffPolicy();

  Stream<PeerMessage> get messages => _messages.stream;

  /// Device ids with a finished hello handshake, on every change.
  Stream<Set<String>> get peerChanges => _peers.stream;
  Set<String> get connected => {
        for (final e in _sessions.entries)
          if (e.value.isReady) e.key
      };

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
    final ws = await WebSocketTransformer.upgrade(request);
    await _start(peer, ws, initiator: false);
  }

  /// Dials [peerId] at [host]:[port] if it is trusted, not connected and this
  /// device is the §6.2 initiator. Retries with backoff until [close].
  Future<void> reach(String peerId, String host, int port) async {
    final peer = store.activeDevices.where((d) => d.deviceId == peerId);
    if (_closed || peer.isEmpty || _dialing.contains(peerId)) return;
    if (_sessions[peerId]?.isClosed == false) return;
    final myTier = hello().tier;
    if (!shouldInitiate(
        myId: _myId,
        myTier: myTier,
        peerId: peerId,
        peerTier: peer.first.tier)) {
      return;
    }
    _dialing.add(peerId);
    _addresses[peerId] = (host, port);
    try {
      final client = await PinnedTransportClient.forIdentity(
          identity: identity, store: store, expectedFp: peer.first.fp);
      final ws = await client.connectWebSocket(
          Uri(scheme: 'wss', host: host, port: port, path: '/api/v1/ws'));
      unawaited(ws.done.whenComplete(client.close));
      _failures.remove(peerId);
      await _start(peer.first, ws, initiator: true);
    } on Object {
      final n = _failures.update(peerId, (v) => v + 1, ifAbsent: () => 0);
      Timer(backoff.delayForAttempt(n), () => reach(peerId, host, port));
    } finally {
      _dialing.remove(peerId);
    }
  }

  /// Sends [env] unchanged to every connected peer (or only [to]).
  Future<void> broadcast(Envelope env, {String? to}) async {
    for (final e in _sessions.entries.toList()) {
      if ((to == null || e.key == to) && e.value.isReady) {
        await e.value.forward(env);
      }
    }
  }

  Future<void> _start(TrustedDevice peer, WebSocket ws,
      {required bool initiator}) async {
    final old = _sessions[peer.deviceId];
    if (old != null && !old.isClosed) {
      // §6.2 rule 4: keep the link the rightful initiator opened.
      final rightful = shouldInitiate(
              myId: _myId,
              myTier: hello().tier,
              peerId: peer.deviceId,
              peerTier: peer.tier) ==
          initiator;
      if (!rightful) {
        await ws.close(4001, 'duplicate connection');
        return;
      }
      await old.shutdown(4001, 'duplicate connection');
    }
    late ControlPlaneSession session;
    session = ControlPlaneSession(
      localHello: hello(),
      channel: _WebSocketChannel(ws),
      initialClock: Hlc.now(_myId),
      onMessage: (env) {
        if (env.origin == _myId) return;
        _messages.add((peerId: peer.deviceId, envelope: env));
      },
      onClosed: (_, __) {
        if (identical(_sessions[peer.deviceId], session)) {
          _sessions.remove(peer.deviceId);
          final at = _addresses[peer.deviceId];
          if (initiator && at != null && !_closed) {
            Timer(backoff.delayForAttempt(0),
                () => reach(peer.deviceId, at.$1, at.$2));
          }
        }
        _emit();
      },
    );
    _sessions[peer.deviceId] = session;
    await session.start(sendInitialHello: initiator);
    unawaited(_whenReady(session, peer.deviceId));
  }

  Future<void> _whenReady(ControlPlaneSession s, String peerId) async {
    for (var i = 0; i < 100 && !s.isReady && !s.isClosed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!s.isReady && !s.isClosed) {
      await s.shutdown(4000, 'hello timeout'); // §6.3
    } else if (s.isReady && s.remoteHello!.deviceId != peerId) {
      await s.shutdown(4004, 'device id does not match pinned cert');
    }
    _emit();
  }

  void _emit() {
    if (!_closed) _peers.add(connected);
  }

  Future<void> close() async {
    _closed = true;
    for (final s in _sessions.values.toList()) {
      await s.shutdown(1000, 'closing');
    }
    _sessions.clear();
    await _messages.close();
    await _peers.close();
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
