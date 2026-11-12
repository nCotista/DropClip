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
    addTearDown(() => dir.deleteSync(recursive: true));
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

    // The sidebar's "Drop files" opens the overlay and the dialog at once.
    dz.browse();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(dz.items.single.name, 'report.pdf');
    expect(dz.items.single.bytes, 3);

    // Inside the Dropzone, the area itself is clickable too.
    dz.close();
    dz.show();
    await tester.pumpAndSettle();
    expect(find.text('or click to choose files'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dropzone-browse')));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(asked, 2);
    expect(dz.items, hasLength(1));
  });
}
