import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/devices_page.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _fp = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

TrustedDevice _trusted(String id, String name) => TrustedDevice(
    deviceId: id,
    name: name,
    os: 'windows',
    tier: 1,
    fp: _fp,
    pairedAt: 0,
    lastSeenAt: 0);

DiscoveredPeer _peer(String id, String name, PeerTrust trust) => DiscoveredPeer(
    record: DiscoveryRecord(
        deviceId: id,
        name: name,
        os: DeviceOs.macos,
        port: 53317,
        fingerprint: _fp),
    address: '192.168.1.9',
    lastSeen: DateTime(2026),
    state: PeerState.discovered,
    trust: trust);

void main() {
  testWidgets('lists paired and nearby devices and routes every action',
      (tester) async {
    const a = '00000000-0000-4000-8000-00000000000a';
    const b = '00000000-0000-4000-8000-00000000000b';
    const c = '00000000-0000-4000-8000-00000000000c';
    final trusted =
        ValueNotifier([_trusted(a, 'Office PC'), _trusted(b, 'Laptop')]);
    final nearby = ValueNotifier([
      _peer(a, 'Office PC', PeerTrust.trusted),
      _peer(c, 'MacBook', PeerTrust.untrusted),
    ]);
    final live = StreamController<Set<String>>();
    addTearDown(live.close);
    var pairNew = 0;
    final pairedWith = <String>[], forgot = <String>[];
    final settled = <String>[];
    final quarantined = ValueNotifier([_trusted(c, 'MacBook')]);

    await tester.pumpWidget(MaterialApp(
        theme: buildDropClipTheme(Brightness.dark),
        home: Scaffold(
            body: DevicesPage(
                myName: 'This PC',
                myFingerprint: _fp,
                trusted: trusted,
                connectedChanges: live.stream,
                connected: const {a},
                nearby: nearby,
                onPairNew: () => pairNew++,
                onPairWith: (p) => pairedWith.add(p.deviceId),
                onForget: (d) => forgot.add(d.deviceId),
                quarantined: quarantined,
                onSettle: (d, remove) =>
                    settled.add('${d.deviceId}:$remove')))));

    expect(find.text('This PC'), findsOneWidget);
    expect(find.byKey(const Key('link-web')), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    // A trusted peer is not offered for pairing again.
    expect(find.byKey(const Key('pair-$a')), findsNothing);

    await tester.tap(find.byKey(const Key('pair-new')));
    await tester.tap(find.byKey(const Key('pair-$c')));
    await tester.tap(find.byKey(const Key('forget-$b')));
    expect(pairNew, 1);
    expect(pairedWith, [c]);
    expect(forgot, [b]);

    expect(find.text('Another device removed MacBook. Remove it here too?'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('revoke-$c')));
    expect(settled, ['$c:true']);

    live.add({a, b});
    await tester.pump();
    expect(find.text('Connected'), findsNWidgets(2));

    trusted.value = [];
    await tester.pump();
    expect(find.text('No paired devices yet'), findsOneWidget);
  });
}
