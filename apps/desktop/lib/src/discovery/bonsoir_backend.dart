import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:dropclip_core/dropclip_core.dart';

import 'network_watcher.dart';

/// [MdnsBackend] on bonsoir: Windows uses the system DNS-SD API
/// (`DnsServiceRegister` / `DnsServiceBrowse`, PROTO-DC-V2.0 §3.1), macOS
/// uses Bonjour. Not unit-tested: it needs a real OS mDNS responder.
class BonsoirMdnsBackend implements MdnsBackend {
  final NetworkWatcher _network;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  /// Services seen so far, re-resolved on every [query].
  final Map<String, BonsoirService> _known = {};

  BonsoirMdnsBackend({NetworkWatcher? network})
      : _network = network ?? NetworkWatcher();

  @override
  Stream<void> get networkChanges => _network.changes;

  @override
  Future<void> register({
    required String serviceType,
    required String instanceName,
    required int port,
    required Map<String, String> txt,
  }) async {
    final broadcast = _broadcast = BonsoirBroadcast(
      printLogs: false,
      service: BonsoirService(
        name: instanceName,
        type: serviceType,
        port: port,
        attributes: txt,
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
  }

  @override
  Future<void> unregister() async {
    final broadcast = _broadcast;
    _broadcast = null;
    await broadcast?.stop();
  }

  @override
  Stream<MdnsEvent> browse(String serviceType) {
    late final StreamController<MdnsEvent> out;
    StreamSubscription<BonsoirDiscoveryEvent>? events;

    Future<void> start() async {
      final discovery =
          _discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
      await discovery.initialize();
      events = discovery.eventStream!.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            _known[service.name] = service;
            discovery.serviceResolver.resolveService(service);
          case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
                BonsoirDiscoveryServiceUpdatedEvent(:final service):
            final address = service.hostAddress ?? service.hostname;
            if (address == null) return;
            out.add(MdnsResolved(service.name,
                address: address,
                srvPort: service.port,
                txt: service.attributes));
          case BonsoirDiscoveryServiceLostEvent(:final service):
            _known.remove(service.name);
            out.add(MdnsLost(service.name));
          default:
        }
      });
      await discovery.start();
    }

    out = StreamController<MdnsEvent>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        await events?.cancel();
        await _discovery?.stop();
        _discovery = null;
        _known.clear();
        await out.close();
      },
    );
    return out.stream;
  }

  /// bonsoir reports a service once; re-resolving every known service each
  /// `DISCOVERY_QUERY_INTERVAL` sends fresh SRV/TXT queries so live peers keep
  /// their `last_seen_at` and silent ones go stale (§3.3).
  @override
  Future<void> query() async {
    final discovery = _discovery;
    if (discovery == null) return;
    for (final service in _known.values.toList()) {
      await discovery.serviceResolver.resolveService(service);
    }
  }
}
