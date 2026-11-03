import 'package:dropclip_desktop/src/app.dart';
import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/onboarding.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('firewall card explains the prompt and can be dismissed (§3.1)',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildDropClipTheme(Brightness.dark),
      home: Scaffold(body: FirewallOnboardingCard(onDone: () => done++)),
    ));
    expect(find.textContaining('Private networks'), findsOneWidget);
    expect(find.textContaining('no cloud'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    expect(done, 1);
  });

  testWidgets('shell shows the banner above the page without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DropClipDesktopApp(
      hiddenLaunch: false,
      status: demoShellStatus,
      banner: FirewallOnboardingCard(onDone: () {}),
    ));
    expect(find.byType(FirewallOnboardingCard), findsOneWidget);
    expect(find.text('Clipboard'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
