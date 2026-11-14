import 'dart:async';
import 'dart:io';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('address selector (T1.1 dual-stack IPv4 preference)', () {
    test('picks private LAN IPv4 when Bonsoir returns IPv6 first', () {
      final picked = selectBestPeerAddress(
        hostAddresses: const [
          'fe80::4cec:f493:a85d:f41c%en0',
          '2405:9800:b651:531c:95e7:25ba:7f82:423c',
          '192.168.1.117',
        ],
        hostAddress: '2405:9800:b651:531c:95e7:25ba:7f82:423c',
        hostname: 'DESKTOP-UID6QT2.local',
      );
      expect(picked, '192.168.1.117');
    });

    test('ranks private LAN > other IPv4 > loopback > global v6 > fe80 > name',
        () {
      expect(peerAddressRank('192.168.1.10'), 0);
      expect(peerAddressRank('10.0.0.5'), 0);
      expect(peerAddressRank('172.16.4.2'), 0);
      expect(peerAddressRank('100.64.0.1'), 1);
      expect(peerAddressRank('127.0.0.1'), 2);
      expect(peerAddressRank('169.254.1.2'), 2);
      expect(peerAddressRank('2405:9800::1'), 3);
      expect(peerAddressRank('[fd00::1]'), 3);
      expect(peerAddressRank('fe80::1%en0'), 4);
      expect(peerAddressRank('Peer.local'), 5);
      expect(peerAddressRank('   '), 5);
    });

    test('strips zone ids and brackets safely', () {
      expect(stripIpZone(' fe80::1%en0 '), 'fe80::1');
      expect(stripIpZone('[2405:9800::1]'), '2405:9800::1');
    });

    test('looks up IPv4 for .local. hostname when event only has IPv6',
        () async {
      String? queried;
      final picked = await resolveMdnsPeerAddress(
        hostAddresses: const ['2405:9800:b651::1'],
        hostAddress: '2405:9800:b651::1',
        hostname: 'DESKTOP-UID6QT2.local.',
        lookupIpv4: (host) async {
          queried = host;
          return [InternetAddress('192.168.1.117')];
        },
      );
      expect(queried, 'DESKTOP-UID6QT2.local');
      expect(picked, '192.168.1.117');
    });

    test('skips DNS lookup when usable IPv4 is already present', () async {
      var called = false;
      final picked = await resolveMdnsPeerAddress(
        hostAddresses: const ['fe80::1%en0', '10.20.30.40'],
        hostname: 'Peer.local',
        lookupIpv4: (_) async {
          called = true;
          return const [];
        },
      );
      expect(called, isFalse);
      expect(picked, '10.20.30.40');
    });

    test('falls back cleanly when lookup fails, times out, or inputs are empty',
        () async {
      final errFallback = await resolveMdnsPeerAddress(
        hostAddress: '2405:9800::1',
        hostname: 'Peer.local',
        lookupIpv4: (_) async => throw const SocketException('offline'),
      );
      expect(errFallback, '2405:9800::1');

      final timeoutFallback = await resolveMdnsPeerAddress(
        hostname: 'Peer.local',
        lookupTimeout: const Duration(milliseconds: 10),
        lookupIpv4: (_) => Completer<List<InternetAddress>>().future,
      );
      expect(timeoutFallback, 'Peer.local');

      expect(
        await resolveMdnsPeerAddress(hostAddresses: const [' ', '']),
        isNull,
      );
    });
  });
}
