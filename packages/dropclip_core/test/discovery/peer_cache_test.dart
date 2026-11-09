import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

const _localId = '00000000-0000-4000-8000-000000000000';
const _peerId = '550e8400-e29b-41d4-a716-446655440000';
const _fp = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';
const _otherFp =
    '0000000000000000000000000000000000000000000000000000000000000000';

DiscoveryRecord _record({String id = _peerId, String fp = _fp}) =>
    DiscoveryRecord(
      deviceId: id,
      name: 'Peer',
      os: DeviceOs.windows,
      port: 53317,
      fingerprint: fp,
    );

void main() {
  group('PeerCache (T1.1, PROTO-DC-V2.0 §3.3–§3.5)', () {
    late DateTime clock;
    late Map<String, String> trusted;
    late PeerCache cache;

    setUp(() {
      clock = DateTime.utc(2026, 11, 2);
      trusted = {};
      cache = PeerCache(
        localDeviceId: _localId,
        trustedFingerprint: (id) => trusted[id],
        now: () => clock,
      );
    });

    tearDown(() => cache.dispose());

    test('Untrusted announcement is discovered but not auto-connectable', () {
      expect(cache.onAnnouncement(_record(), '192.168.1.10'), isTrue);

      final peer = cache[_peerId]!;
      expect(peer.state, PeerState.discovered);
      expect(peer.trust, PeerTrust.untrusted);
      expect(peer.canAutoConnect, isFalse);
    });

    test('Trusted id and matching fingerprint becomes trustedOnline', () {
      trusted[_peerId] = _fp.toUpperCase();
      cache.onAnnouncement(_record(), '192.168.1.10');

      final peer = cache[_peerId]!;
      expect(peer.state, PeerState.trustedOnline);
      expect(peer.trust, PeerTrust.trusted);
      expect(peer.canAutoConnect, isTrue);
    });

    test('Trusted id with a different fingerprint is identityChanged', () {
      trusted[_peerId] = _otherFp;
      cache.onAnnouncement(_record(), '192.168.1.10');

      final peer = cache[_peerId]!;
      expect(peer.trust, PeerTrust.identityChanged);
      expect(peer.state, PeerState.discovered);
      expect(peer.canAutoConnect, isFalse);
      cache.markConnected(_peerId);
      expect(cache[_peerId]!.state, PeerState.discovered);
    });

    test('IP change updates the existing entry instead of duplicating', () {
      cache.onAnnouncement(_record(), '192.168.1.10');
      cache.onAnnouncement(_record(), '10.0.0.7');

      expect(cache.peers, hasLength(1));
      expect(cache[_peerId]!.address, '10.0.0.7');
    });

    test('Ignores own record and TXT/SRV port mismatch', () {
      expect(cache.onAnnouncement(_record(id: _localId), '127.0.0.1'), isFalse);
      expect(
        cache.onAnnouncement(_record(), '192.168.1.10', srvPort: 53318),
        isFalse,
      );
      expect(cache.peers, isEmpty);
    });

    test('Marks stale after 30 s and removes after 120 s of silence', () {
      trusted[_peerId] = _fp;
      cache.onAnnouncement(_record(), '192.168.1.10');

      clock = clock.add(const Duration(seconds: 30));
      cache.sweep();
      expect(cache[_peerId]!.state, PeerState.trustedOnline);

      clock = clock.add(const Duration(seconds: 1));
      cache.sweep();
      expect(cache[_peerId]!.state, PeerState.stale);

      clock = clock.add(const Duration(seconds: 90));
      cache.sweep();
      expect(cache[_peerId], isNull);
    });

    test('Stale peer seen again returns to its previous state', () {
      trusted[_peerId] = _fp;
      cache.onAnnouncement(_record(), '192.168.1.10');
      clock = clock.add(const Duration(seconds: 31));
      cache.sweep();

      cache.onAnnouncement(_record(), '192.168.1.10');
      expect(cache[_peerId]!.state, PeerState.trustedOnline);
    });

    test('Connected peer is never staled by mDNS silence', () {
      trusted[_peerId] = _fp;
      cache.onAnnouncement(_record(), '192.168.1.10');
      cache.markConnected(_peerId);

      clock = clock.add(const Duration(minutes: 10));
      cache.sweep();
      cache.onGoodbye(_peerId);
      expect(cache[_peerId]!.state, PeerState.connected);

      cache.onAnnouncement(_record(), '192.168.1.11');
      expect(cache[_peerId]!.state, PeerState.connected);

      cache.markDisconnected(_peerId);
      expect(cache[_peerId]!.state, PeerState.trustedOnline);
      expect(cache[_peerId]!.lastSeen, clock);
    });

    test('Goodbye removes the peer immediately', () {
      cache.onAnnouncement(_record(), '192.168.1.10');
      cache.onGoodbye(_peerId);
      cache.onGoodbye('unknown');

      expect(cache.peers, isEmpty);
    });

    test('Emits a snapshot on every change', () async {
      final snapshots = <int>[];
      final sub = cache.changes.listen((p) => snapshots.add(p.length));

      cache.onAnnouncement(_record(), '192.168.1.10');
      cache.sweep(); // no change, no emission
      cache.onGoodbye(_peerId);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots, [1, 0]);
    });
  });
}
