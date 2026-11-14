import 'package:dropclip_desktop/src/app.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/l10n/strings.dart';
import 'package:dropclip_desktop/src/onboarding.dart';
import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:dropclip_desktop/src/settings/settings_page.dart';
import 'package:dropclip_desktop/src/shell.dart';
import 'package:dropclip_desktop/src/tray_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text getter, so a missing or untranslated Thai string shows up.
List<String> _all(Strings s) => [
      s.clipboard, s.transfers, s.devices, s.settings, s.workspace, //
      s.thisDevice, s.devicesVerified(3), s.notAvailable('X', 'T1.9'),
      s.sendClipboard, s.pairing, s.application, s.languageSub,
      s.startAtLogin, s.startAtLoginSub, s.webCompanion, s.webCompanionSub,
      s.syncAuto, s.syncAutoSub,
      s.typesToSync, s.typesToSyncSub, s.text, s.links, s.images,
      s.ttlTitle, s.ttlSub, s.receivingFiles, s.autoAccept, s.autoAcceptSub,
      s.destination, s.destinationSub, s.autoStartFailed, s.ttl(null),
      s.connection, s.networkAdapter, s.networkAdapterSub, s.networkAutomatic,
      s.ttl(30), s.ttl(300), s.firewallTitle, s.firewallBody,
      s.firewallPublic, s.gotIt,
      // Clipboard page, side panel, tray menu
      s.copied, s.liveSyncAcross(3), s.autoSync, s.searchClips, s.all,
      s.recentHeader, s.noClipsMatch, s.fromDevice('Pixel 8', 'now'),
      s.copyAgain, s.suppressed(1), s.suppressed(2), s.nearbyDevices,
      s.onlineCount(2), s.noDevicesNearby, s.pairNewDevice, s.dropFiles,
      s.dropFilesSub, s.online, s.manual, s.syncLatency,
      s.latencyTarget(under: true), s.latencyTarget(under: false),
      s.connectedTo('Home'), s.clipboardSync, s.onlineDevices,
      for (final a in TrayAction.values) a.labelIn(s),
      // Dropzone
      s.dropHere, s.releaseToAdd, s.itemCount(2), s.sendTo,
      s.sendToDevice('Pixel 8'), s.dropzoneKeys,
      // Debug console
      s.debugConsole(3), s.noLogLines,
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

  testWidgets('Clipboard page, side panel and tray menu render in Thai',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StringsScope(
      strings: const ThStrings(),
      child: MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const Expanded(
                child: DropClipDesktopApp(
                    hiddenLaunch: false, status: demoShellStatus)),
            TrayMenu(
              status: demoShellStatus,
              syncEnabled: true,
              onSyncChanged: (_) {},
              onAction: (_) {},
              platform: TargetPlatform.windows,
            ),
          ]),
        ),
      ),
    ));
    for (final text in [
      'ซิงก์อัตโนมัติ', // header switch
      'ทั้งหมด', // filter chip
      'อุปกรณ์ใกล้เคียง', // side panel
      'ต่ำกว่าเป้า 1,000 ms', // latency card
      'อุปกรณ์ที่ออนไลน์', // tray header
      'ออกจาก DropClip', // tray action
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.textContaining('Nearby devices'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
