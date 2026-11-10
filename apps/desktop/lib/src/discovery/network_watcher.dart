import 'dart:async';
import 'dart:io';

/// Lists the local addresses; injectable for tests.
typedef AddressLister = Future<List<String>> Function();

Future<List<String>> _listAddresses() async => [
      for (final i in await NetworkInterface.list())
        for (final a in i.addresses) '${i.name}/${a.address}',
    ];

/// Emits when the set of local interface addresses changes (Wi-Fi ↔
/// Ethernet, new DHCP lease), so discovery can re-announce within 5 s
/// (PROTO-DC-V2.0 §3.3). Polls because Dart has no interface-change event.
class NetworkWatcher {
  final Duration interval;
  final AddressLister _list;

  NetworkWatcher({
    this.interval = const Duration(seconds: 2),
    AddressLister? list,
  }) : _list = list ?? _listAddresses;

  Stream<void> get changes {
    late final StreamController<void> out;
    Timer? timer;
    Set<String>? last;
    var polling = false;

    Future<void> poll() async {
      if (polling) return;
      polling = true;
      try {
        final now = (await _list()).toSet();
        final changed = last != null &&
            (now.length != last!.length || !now.containsAll(last!));
        last = now;
        if (changed && !out.isClosed) out.add(null);
      } on SocketException {
        // Interfaces can vanish mid-listing; the next poll catches up.
      } finally {
        polling = false;
      }
    }

    out = StreamController<void>(
      onListen: () {
        unawaited(poll());
        timer = Timer.periodic(interval, (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
        return out.close();
      },
    );
    return out.stream;
  }
}
