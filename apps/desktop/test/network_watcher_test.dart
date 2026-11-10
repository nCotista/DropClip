import 'dart:io';
import 'dart:math';

import 'package:dropclip_desktop/src/discovery/network_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkWatcher', () {
    test('emits only when the address set changes, survives errors', () async {
      // null = the listing throws, as when an interface vanishes mid-list.
      final answers = <List<String>?>[
        ['wifi/10.0.0.2'],
        null,
        ['wifi/10.0.0.2'], // same set: no event
        ['wifi/10.0.0.3'], // DHCP change: event 1
        ['eth/192.168.1.5', 'wifi/10.0.0.3'], // cable plugged in: event 2
      ];
      var polls = 0;
      final watcher = NetworkWatcher(
        interval: const Duration(milliseconds: 5),
        list: () async {
          final a = answers[min(polls++, answers.length - 1)];
          if (a == null) throw const SocketException('interface vanished');
          return a;
        },
      );
      var changes = 0;
      final sub = watcher.changes.listen((_) => changes++);
      while (polls < answers.length + 3) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await sub.cancel();
      expect(changes, 2);
    });
  });
}
