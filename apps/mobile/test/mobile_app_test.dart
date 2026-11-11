import 'package:dropclip_mobile/src/mobile_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropClipMobileApp (T2.5)', () {
    testWidgets('1-Tap Send Clipboard adds clip and invokes callback',
        (tester) async {
      String? sent;
      await tester.pumpWidget(
        DropClipMobileApp(onSendClipboard: (clip) => sent = clip),
      );

      expect(find.text('DropClip Mobile'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mobile_send_clipboard_btn')));
      await tester.pump();

      expect(sent, equals('Sent from DropClip Mobile 1-Tap Action'));
      expect(
        find.text('Sent from DropClip Mobile 1-Tap Action'),
        findsOneWidget,
      );
    });

    testWidgets('QR & Manual PIN SAS verification matches conformance vectors',
        (tester) async {
      await tester.pumpWidget(const DropClipMobileApp());

      await tester.tap(find.text('Pair (QR/PIN)'));
      await tester.pumpAndSettle();

      // 1. Conformance QR vector: 337017
      await tester.tap(find.byKey(const Key('verify_qr_sas_btn')));
      await tester.pump();
      expect(find.text('SAS Code: 337017'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_sas_match_btn')));
      await tester.pump();
      expect(find.text('Paired & Pinned (TLS 1.3)'), findsOneWidget);

      // 2. Conformance PIN vector (123456): 639589
      await tester.enterText(find.byKey(const Key('pin_input')), '123456');
      await tester.tap(find.byKey(const Key('verify_pin_sas_btn')));
      await tester.pump();
      expect(find.text('SAS Code: 639589'), findsOneWidget);

      // 3. Invalid PIN triggers validation error
      await tester.enterText(find.byKey(const Key('pin_input')), 'abc');
      await tester.tap(find.byKey(const Key('verify_pin_sas_btn')));
      await tester.pump();
      expect(find.byKey(const Key('pairing_error_text')), findsOneWidget);
    });

    testWidgets('Devices tab displays paired TLS 1.3 peers', (tester) async {
      await tester.pumpWidget(const DropClipMobileApp());

      await tester.tap(find.text('Devices'));
      await tester.pumpAndSettle();

      expect(find.text('MacBook-Pro.local'), findsOneWidget);
      expect(find.text('Workstation-Win11.local'), findsOneWidget);
    });
  });
}
