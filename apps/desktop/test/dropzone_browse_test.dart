import 'dart:io';

import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_controller.dart';
import 'package:dropclip_desktop/src/dropzone/dropzone_host.dart';
import 'package:dropclip_desktop/src/dropzone/file_dialog.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows open-file result: one path, or a folder plus names', () {
    expect(parseOpenFileResult([r'C:\a\one.pdf']), [r'C:\a\one.pdf']);
    expect(parseOpenFileResult([r'C:\a', 'x.png', 'y.txt']),
        [r'C:\a\x.png', r'C:\a\y.txt']);
    expect(parseOpenFileResult([r'C:\', 'x.png', 'y.txt']),
        [r'C:\x.png', r'C:\y.txt']);
    expect(parseOpenFileResult(const []), isEmpty);
  });

  testWidgets('clicking the drop area adds the chosen files', (tester) async {
    final dir = Directory.systemTemp.createTempSync('dc_browse_');
    addTearDown(
        () => dir.delete(recursive: true).catchError((Object _) => dir));
    final file = File('${dir.path}/report.pdf')..writeAsBytesSync([1, 2, 3]);
    final dz = DropzoneController();
    var asked = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildDropClipTheme(Brightness.dark),
      builder: (_, child) => DropzoneHost(
        controller: dz,
        devices: ValueNotifier(const <NearbyDevice>[]),
        nativeDrop: false,
        pickFiles: () async {
          asked++;
          return [file.path];
        },
        child: child!,
      ),
      home: const Scaffold(body: Text('app')),
    ));

    // Opening the Dropzone does not open the dialog by itself.
    dz.show();
    await tester.pumpAndSettle();
    expect(asked, 0);
    expect(find.text('or click to choose files'), findsOneWidget);

    // A click on the drop area does.
    await tester.tap(find.byKey(const Key('dropzone-browse')));
    await _settle(tester, () => dz.items.isNotEmpty);
    expect(asked, 1);
    expect(dz.items.single.name, 'report.pdf');
    expect(dz.items.single.bytes, 3);
  });
}

/// Real file I/O (the size of the chosen file) runs outside the fake clock.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}
