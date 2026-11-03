import 'package:dropclip_desktop/src/l10n/strings.dart';
import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text getter, so a missing or untranslated Thai string shows up.
List<String> _all(Strings s) => [
      s.clipboard, s.transfers, s.devices, s.settings, s.workspace, //
      s.thisDevice, s.devicesVerified(3), s.notAvailable('X', 'T1.9'),
      s.sendClipboard, s.pairing, s.application, s.languageSub,
      s.startAtLogin, s.startAtLoginSub, s.syncAuto, s.syncAutoSub,
      s.typesToSync, s.typesToSyncSub, s.text, s.links, s.images,
      s.ttlTitle, s.ttlSub, s.receivingFiles, s.autoAccept, s.autoAcceptSub,
      s.destination, s.destinationSub, s.autoStartFailed, s.ttl(null),
      s.ttl(30), s.ttl(300), s.firewallTitle, s.firewallBody,
      s.firewallPublic, s.gotIt,
    ];

void main() {
  test('Thai text exists for every string and differs from English', () {
    final en = _all(const EnStrings()), th = _all(const ThStrings());
    for (var i = 0; i < en.length; i++) {
      expect(th[i].trim(), isNotEmpty);
      expect(th[i], isNot(en[i]), reason: 'untranslated: ${en[i]}');
    }
    expect(Strings.forLanguage(AppLanguage.th), isA<ThStrings>());
    expect(Strings.forLanguage(AppLanguage.en), isA<EnStrings>());
  });

  Widget probe(Strings? strings, void Function(String) seen) {
    final child = Builder(builder: (context) {
      seen(Strings.of(context).settings);
      return const SizedBox();
    });
    return strings == null
        ? child
        : StringsScope(strings: strings, child: child);
  }

  testWidgets('a scope gives its language to the tree', (tester) async {
    late String text;
    await tester.pumpWidget(probe(const ThStrings(), (s) => text = s));
    expect(text, const ThStrings().settings);
  });

  testWidgets('no scope falls back to English', (tester) async {
    late String text;
    await tester.pumpWidget(probe(null, (s) => text = s));
    expect(text, const EnStrings().settings);
  });

  testWidgets('changing language rebuilds readers; same language does not',
      (tester) async {
    var builds = 0;
    final reader = Builder(builder: (context) {
      Strings.of(context);
      builds++;
      return const SizedBox();
    });
    Future<void> show(Strings s) =>
        tester.pumpWidget(StringsScope(strings: s, child: reader));
    await show(const EnStrings());
    await show(const EnStrings());
    expect(builds, 1);
    await show(const ThStrings());
    expect(builds, 2);
  });

  test('count words agree with the number', () {
    expect(const EnStrings().devicesVerified(1), contains('1'));
    expect(const ThStrings().devicesVerified(3), contains('3'));
  });
}
