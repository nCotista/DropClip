import 'dart:async';

import 'package:dropclip_protocol/dropclip_protocol.dart';

import 'peer_cache.dart';
import 'txt_record.dart';

/// A DNS-SD event reported by an [MdnsBackend].
sealed class MdnsEvent {
  /// Service instance name; DropClip uses the device id (§3.1).
  final String instanceName;

  const MdnsEvent(this.instanceName);
}

/// A service instance was resolved (announcement or query response).
class MdnsResolved extends MdnsEvent {
  final String address;
  final int srvPort;
  final Map<String, String?> txt;

  const MdnsResolved(
    super.instanceName, {
    required this.address,
    required this.srvPort,
    required this.txt,
  });
}

/// A service instance sent a goodbye packet (TTL = 0).
class MdnsLost extends MdnsEvent {
  const MdnsLost(super.instanceName);
}

/// Platform DNS-SD binding (Windows `DnsServiceRegister`/`DnsServiceBrowse`
/// via `bonsoir`, macOS Bonjour). Kept abstract so the engine stays pure Dart.
abstract interface class MdnsBackend {
  /// Registers [instanceName] of [serviceType] on [port] with [txt].
  Future<void> register({
    required String serviceType,
    required String instanceName,
    required int port,
    required Map<String, String> txt,
  });

  /// Unregisters the local service, sending a goodbye packet.
  Future<void> unregister();

  /// Starts browsing [serviceType]; the stream ends when browsing stops.
  Stream<MdnsEvent> browse(String serviceType);

  /// Sends a fresh browse query (§3.3 `DISCOVERY_QUERY_INTERVAL`).
  Future<void> query();

  /// Emits whenever a network interface or local IP changes.
  Stream<void> get networkChanges;
}

/// Discovery Layer engine (T1.1, FR-01, PROTO-DC-V2.0 §3): advertises the
/// local [record], feeds browse results into [cache], re-queries every
/// [queryInterval] and re-announces when the network changes.
class DiscoveryService {
  final MdnsBackend backend;
  final PeerCache cache;
  final DiscoveryRecord record;
  final Duration queryInterval;

  /// Receives debug messages for dropped packets (never secret material —
  /// TXT records are public by spec §3.2).
  final void Function(String message)? onDebug;

  StreamSubscription<MdnsEvent>? _browse;
  StreamSubscription<void>? _network;
  Timer? _ticker;
  Future<void>? _reannouncing;

  DiscoveryService({
    required this.backend,
    required this.cache,
    required this.record,
    this.queryInterval = ProtocolConstants.discoveryQueryInterval,
    this.onDebug,
  });

  bool _running = false;

  bool get isRunning => _running;

  /// Registers the local service and starts browsing.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _register();
    if (!_running) return;
    _browse = backend.browse(DiscoveryRecord.serviceType).listen(_onEvent);
    _network = backend.networkChanges.listen((_) => _reannounce());
    _ticker = Timer.periodic(queryInterval, (_) => _tick());
  }

  /// Stops browsing and sends a goodbye for the local service (§3.3).
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    await _browse?.cancel();
    await _network?.cancel();
    _browse = _network = null;
    await _reannouncing;
    await backend.unregister();
  }

  Future<void> _register() => backend.register(
        serviceType: DiscoveryRecord.serviceType,
        instanceName: record.deviceId,
        port: record.port,
        txt: record.toTxt(),
      );

  void _tick() {
    cache.sweep();
    unawaited(backend.query());
  }

  /// Re-registers so peers see the new address well within 5 s (§3.3).
  /// Bursts of interface events collapse into one re-announce.
  void _reannounce() {
    _reannouncing ??= () async {
      try {
        await backend.unregister();
        if (isRunning) await _register();
        if (isRunning) await backend.query();
      } finally {
        _reannouncing = null;
      }
    }();
  }

  void _onEvent(MdnsEvent event) {
    switch (event) {
      case MdnsResolved():
        _onResolved(event);
      case MdnsLost(:final instanceName):
        cache.onGoodbye(instanceName.toLowerCase());
    }
  }

  void _onResolved(MdnsResolved event) {
    final parsed = DiscoveryRecord.tryParse(event.txt);
    if (parsed == null) {
      onDebug?.call('discovery: dropped malformed TXT from ${event.address}');
      return;
    }
    // `id` MUST match the instance name (§3.2).
    if (parsed.deviceId != event.instanceName.toLowerCase()) {
      onDebug?.call('discovery: dropped id/instance mismatch');
      return;
    }
    if (!cache.onAnnouncement(parsed, event.address, srvPort: event.srvPort)) {
      onDebug?.call('discovery: ignored record ${parsed.deviceId}');
    }
  }
}
