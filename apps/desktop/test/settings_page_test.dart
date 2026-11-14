import 'package:dropclip_desktop/src/app.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/l10n/strings.dart';
import 'package:dropclip_desktop/src/settings/auto_start.dart';
import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:dropclip_desktop/src/settings/settings_page.dart';
import 'package:dropclip_desktop/src/shell.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Switch on the same settings row as [title].
Finder _switchFor(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Wrap)).first,
    matching: find.byType(Switch));

void main() {
  late ValueNotifier<AppConfig> config;
  late List<AppConfig> saved;
  Object? failWith;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildDropClipTheme(Brightness.dark),
      home: Scaffold(
        body: SettingsPage(
          config: config,
          onChanged: (next) async {
            if (failWith != null) throw failWith!;
            saved.add(next);
            config.value = next;
          },
        ),
      ),
    ));
  }

  setUp(() {
    config = ValueNotifier(const AppConfig(deviceName: 'PC'));
    saved = [];
    failWith = null;
  });

  group('SettingsPage (FR-12)', () {
    testWidgets('shows the spec defaults', (tester) async {
      await pump(tester);
      Switch sw(String label) => tester.widget<Switch>(_switchFor(label));
      expect(sw('Start at login').value, isTrue);
      expect(sw('Web companion (/web)').value, isFalse);
      expect(sw('Sync clipboard automatically').value, isTrue);
      expect(sw('Accept files automatically').value, isFalse);
      expect(find.text('~/Downloads/DropClip'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
    });

    testWidgets('each control saves and applies at once', (tester) async {
      await pump(tester);

      await tester.tap(_switchFor('Accept files automatically'));
      await tester.pump();
      expect(saved.last.autoAccept, isTrue);

      await tester.tap(_switchFor('Web companion (/web)'));
      await tester.pump();
      expect(saved.last.webCompanionEnabled, isTrue);

      await tester.tap(find.text('Images'));
      await tester.pump();
      expect(saved.last.syncTypes, {SyncType.text, SyncType.url});

      await tester.tap(find.text('English'));
      await tester.pump();
      expect(saved.last.language, AppLanguage.en);

      await tester.tap(find.text('Never'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 minute').last);
      await tester.pumpAndSettle();
      expect(saved.last.clipboardTtlSeconds, 60);
      expect(find.text('1 minute'), findsOneWidget);
    });

    testWidgets('the device name is saved on Enter; empty keeps the old one',
        (tester) async {
      await pump(tester);
      final field = find.byKey(const Key('device-name'));
      await tester.enterText(field, '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved, isEmpty);
      await tester.enterText(field, 'Office PC');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved.single.deviceName, 'Office PC');
    });

    testWidgets('auto-start refused by the OS shows a message, keeps state',
        (tester) async {
      failWith = const AutoStartException('denied');
      await pump(tester);
      await tester.tap(_switchFor('Start at login'));
      await tester.pump();
      expect(find.textContaining('Could not change'), findsOneWidget);
      expect(config.value.autoStart, isTrue);
    });
  });

  test('TTL labels', () {
    expect([for (final s in ttlChoices) const EnStrings().ttl(s)],
        ['Never', '30 seconds', '1 minute', '5 minutes', '15 minutes']);
  });

  testWidgets('shell shows the settings page in the Settings section',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final section = ValueNotifier(ShellSection.settings);
    await tester.pumpWidget(DropClipDesktopApp(
      hiddenLaunch: false,
      status: demoShellStatus,
      section: section,
      settingsPage: SettingsPage(config: config, onChanged: (_) async {}),
    ));
    expect(find.text('Start at login'), findsOneWidget);
  });
}
