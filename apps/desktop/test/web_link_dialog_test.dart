import 'dart:convert';
import 'dart:io';

import 'package:dropclip_desktop/src/web/web_companion.dart';
import 'package:dropclip_desktop/src/web/web_link_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

void main() {
  testWidgets('shows the link QR and lets the user remove a browser',
      (tester) async {
    final web = WebCompanion(
        downloads: Directory.systemTemp,
        page: '',
        writeClipboard: (_) async {},
        enabled: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebLinkDialog(
                web: web, baseUrl: () async => 'https://10.0.0.5:53317/web'))));
    await tester.pump();
    expect(find.byKey(const Key('web-qr')), findsOneWidget);
    expect(find.text('https://10.0.0.5:53317/web'), findsOneWidget);

    // A phone claims a code; it shows up and can be removed.
    final res = await web.handler(Request(
        'POST', Uri.parse('https://x/web/api/claim'),
        body: jsonEncode({'code': web.newCode(), 'name': 'iPhone'})));
    expect(res.statusCode, 200);
    await tester.pump();
    expect(find.text('iPhone'), findsOneWidget);
    await tester
        .tap(find.byKey(Key('web-remove-${web.sessions.value.single.id}')));
    await tester.pump();
    expect(find.text('iPhone'), findsNothing);
  });

  testWidgets('skips generating a code when companion turns off mid-refresh',
      (tester) async {
    var on = true;
    final web = WebCompanion(
      downloads: Directory.systemTemp,
      page: '',
      writeClipboard: (_) async {},
      isEnabled: () => on,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebLinkDialog(
          web: web,
          baseUrl: () async {
            on = false;
            return 'https://10.0.0.5:53317/web';
          },
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('web-qr')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
