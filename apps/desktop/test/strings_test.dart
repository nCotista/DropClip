import 'package:dropclip_desktop/src/app.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/l10n/strings.dart';
import 'package:dropclip_desktop/src/onboarding.dart';
import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:dropclip_desktop/src/settings/settings_page.dart';
import 'package:dropclip_desktop/src/shell.dart';
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

  testWidgets('switching language changes every screen at once (NFR-L01)',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = ValueNotifier(const AppConfig(deviceName: 'PC'));
    final section = ValueNotifier(ShellSection.settings);
    await tester.pumpWidget(ValueListenableBuilder<AppConfig>(
      valueListenable: config,
      builder: (_, c, child) =>
          StringsScope(strings: Strings.forLanguage(c.language), child: child!),
      child: DropClipDesktopApp(
        hiddenLaunch: false,
        status: demoShellStatus,
        section: section,
        banner: FirewallOnboardingCard(onDone: () {}),
        settingsPage: SettingsPage(
            config: config, onChanged: (next) async => config.value = next),
      ),
    ));

    // Default language is Thai (§15.6 addition).
    expect(find.text('เปิดพร้อมระบบปฏิบัติการ'), findsOneWidget);
    expect(find.text('อุปกรณ์'), findsOneWidget);
    expect(find.text('เข้าใจแล้ว'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(config.value.language, AppLanguage.en);
    expect(find.text('Start at login'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('เปิดพร้อมระบบปฏิบัติการ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
