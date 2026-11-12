import 'dart:async';
import 'dart:math';

import 'package:dropclip_protocol/dropclip_protocol.dart';

/// Abstract transport channel for a single WebSocket control session (§6).
abstract interface class ControlSocketChannel {
  Stream<String> get incoming;
  Future<void> sendFrame(String rawFrame);
  Future<void> close(int code, String reason);
}

/// Computes exponential backoff with jitter per PROTO-DC-V2.0 §6.4:
/// base delays 1s, 2s, 4s, 8s, 16s, capped at 30s, with ±20% jitter.
class ReconnectBackoffPolicy {
  static const List<int> baseSeconds = <int>[1, 2, 4, 8, 16, 30];
  final double jitterFraction;
  final Random _random;

  ReconnectBackoffPolicy({
    this.jitterFraction = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  Duration delayForAttempt(int attempt) {
    final idx = attempt < 0
        ? 0
        : (attempt >= baseSeconds.length ? baseSeconds.length - 1 : attempt);
    final baseMs = baseSeconds[idx] * 1000;
    if (jitterFraction <= 0) {
      return Duration(milliseconds: baseMs);
    }
    final delta = (_random.nextDouble() * 2 - 1) * jitterFraction;
    final jitteredMs = (baseMs * (1 + delta)).round();
    return Duration(milliseconds: jitteredMs < 100 ? 100 : jitteredMs);
  }
}

/// Active authenticated Control Plane session with a single peer (§6.2–§6.7).
class ControlPlaneSession {
  final HelloPayload localHello;
  final ControlSocketChannel channel;
  final Duration pingInterval;
  final Duration pongTimeout;
  final int Function() _nowMs;
  final String Function() _nextMsgId;
  final void Function(HelloPayload remoteHello)? onTombstoneMismatch;
  final void Function(Envelope envelope)? onMessage;
  final void Function(int code, String reason)? onClosed;

  Hlc _clock;
  HelloPayload? _remoteHello;
  int? _negotiatedVersion;
  StreamSubscription<String>? _sub;
  Timer? _pingTimer;
  Timer? _pongTimer;
  bool _closed = false;

  ControlPlaneSession({
    required this.localHello,
    required this.channel,
    required Hlc initialClock,
    this.pingInterval = const Duration(seconds: 15),
    this.pongTimeout = const Duration(seconds: 5),
    int Function()? nowMs,
    String Function()? nextMsgId,
    this.onTombstoneMismatch,
    this.onMessage,
    this.onClosed,
  })  : _clock = initialClock,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _nextMsgId = nextMsgId ?? _defaultUuidV4;

  bool get isReady => _remoteHello != null && !_closed;
  bool get isClosed => _closed;
  HelloPayload? get remoteHello => _remoteHello;
  int? get negotiatedVersion => _negotiatedVersion;
  Hlc get clock => _clock;

  /// Starts listening and sends the initial `hello` frame (§6.2).
  Future<void> start({bool sendInitialHello = true}) async {
    _sub = channel.incoming.listen(
      (raw) => unawaited(_handleRawFrame(raw)),
      onDone: () => unawaited(
        shutdown(VersionNegotiator.wsCloseProtocolError, 'socket closed'),
      ),
    );
    if (sendInitialHello) {
      await sendEnvelope(MessageType.hello, localHello.toJson());
    }
  }

  /// Encodes and sends a control plane message enforcing the 64 KiB quota.
  Future<Envelope> sendEnvelope(
    MessageType type,
    Map<String, dynamic> payload,
  ) async {
    if (_closed) {
      throw const ProtocolException(
        ProtocolErrorCode.internal,
        'session is closed',
      );
    }
    final now = _nowMs();
    _clock = _clock.send(now);
    final env = Envelope(
      v: _negotiatedVersion ?? localHello.v,
      type: type,
      msgId: _nextMsgId(),
      origin: localHello.deviceId,
      hlc: _clock,
      ts: now,
      payload: payload,
    );
    final wire = env.encodeWire();
    await channel.sendFrame(wire);
    return env;
  }

  /// Sends a `ping` frame and starts the `pong` deadline timer (§6.3).
  Future<void> sendPing() async {
    if (_closed || !isReady) return;
    _pongTimer?.cancel();
    _pongTimer = Timer(pongTimeout, () {
      unawaited(
        shutdown(
          VersionNegotiator.wsCloseHeartbeatTimeout,
          'heartbeat pong timeout',
        ),
      );
    });
    await sendEnvelope(MessageType.ping, <String, dynamic>{'ts': _nowMs()});
  }

  Future<void> _handleRawFrame(String rawFrame) async {
    if (_closed) return;
    final Envelope env;
    try {
      env = Envelope.decodeWire(rawFrame);
      _clock = _clock.receive(env.hlc, _nowMs());
    } on ClockDriftException catch (e) {
      await _sendErrorAndMaybeClose(
        const ProtocolException(
          ProtocolErrorCode.malformed,
          'clock drift exceeds 60s bound',
        ),
        detail: e.toString(),
      );
      return;
    } on ProtocolException catch (e) {
      await _sendErrorAndMaybeClose(e);
      return;
    }

    if (env.type == MessageType.hello || env.type == MessageType.helloAck) {
      await _handleHandshake(env);
      return;
    }
    if (!isReady) {
      await _sendErrorAndMaybeClose(
        const ProtocolException(
          ProtocolErrorCode.malformed,
          'received frame before hello handshake completed',
          wsCloseCode: VersionNegotiator.wsCloseProtocolError,
        ),
      );
      return;
    }
    if (env.type == MessageType.ping) {
      await sendEnvelope(
        MessageType.pong,
        <String, dynamic>{'ref_msg_id': env.msgId},
      );
      return;
    }
    if (env.type == MessageType.pong) {
      _pongTimer?.cancel();
      _pongTimer = null;
      return;
    }
    onMessage?.call(env);
  }

  Future<void> _handleHandshake(Envelope env) async {
    final HelloPayload remote;
    try {
      remote = HelloPayload.fromJson(env.payload);
      _negotiatedVersion = VersionNegotiator.negotiate(
        localV: localHello.v,
        localMinV: localHello.minV,
        remoteV: remote.v,
        remoteMinV: remote.minV,
      );
    } on ProtocolException catch (e) {
      await _sendErrorAndMaybeClose(
        e,
        forceCloseCode:
            e.wsCloseCode ?? VersionNegotiator.wsCloseUnsupportedVersion,
      );
      return;
    }
    _remoteHello = remote;
    if (env.type == MessageType.hello) {
      await sendEnvelope(MessageType.helloAck, localHello.toJson());
    }
    if (remote.tombstonesHash != localHello.tombstonesHash) {
      onTombstoneMismatch?.call(remote);
    }
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      unawaited(sendPing());
    });
  }

  Future<void> _sendErrorAndMaybeClose(
    ProtocolException error, {
    String? detail,
    int? forceCloseCode,
  }) async {
    try {
      await sendEnvelope(MessageType.error, error.toWsPayload());
    } on Object {
      // Ignore send failure when closing.
    }
    final closeCode = forceCloseCode ?? error.wsCloseCode;
    if (error.fatal || closeCode != null) {
      await shutdown(
        closeCode ?? VersionNegotiator.wsCloseProtocolError,
        detail ?? error.errorCode.code,
      );
    }
  }

  /// Cancels all timers/subscriptions and closes the socket cleanly.
  Future<void> shutdown(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    await _sub?.cancel();
    _sub = null;
    await channel.close(code, reason);
    onClosed?.call(code, reason);
  }

  static int _counter = 0;
  static String _defaultUuidV4() {
    _counter = (_counter + 1) & 0xffffffffffff;
    final hex = _counter.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$hex';
  }
}

/// Manages automatic reconnection across transient network drops (§6.4).
class ControlPlaneReconnectEngine {
  final Future<ControlPlaneSession> Function() connectFactory;
  final ReconnectBackoffPolicy backoff;
  final int maxAttempts;

  ControlPlaneSession? _activeSession;
  int _attempts = 0;
  bool _stopped = false;

  ControlPlaneReconnectEngine({
    required this.connectFactory,
    ReconnectBackoffPolicy? backoff,
    this.maxAttempts = 20,
  }) : backoff = backoff ?? ReconnectBackoffPolicy();

  ControlPlaneSession? get activeSession => _activeSession;
  int get attempts => _attempts;
  bool get isStopped => _stopped;

  /// Connects or retries according to [backoff] until connected or stopped.
  Future<ControlPlaneSession?> connectWithRetry({
    Future<void> Function(Duration delay)? waitFn,
  }) async {
    final waiter = waitFn ?? Future<void>.delayed;
    while (!_stopped && _attempts < maxAttempts) {
      try {
        final session = await connectFactory();
        _activeSession = session;
        _attempts = 0;
        return session;
      } on Object {
        final delay = backoff.delayForAttempt(_attempts);
        _attempts++;
        if (_stopped || _attempts >= maxAttempts) break;
        await waiter(delay);
      }
    }
    return null;
  }

  Future<void> stop() async {
    _stopped = true;
    final current = _activeSession;
    _activeSession = null;
    if (current != null && !current.isClosed) {
      await current.shutdown(1000, 'client stopped');
    }
  }
}

