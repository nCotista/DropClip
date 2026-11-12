import 'package:dropclip_desktop/src/transfers_and_devices_pages.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopTransfersPage (T1.10–T1.12)', () {
    testWidgets('streams sample and resumes .part file', (tester) async {
      var sampleSent = 0;
      var dropzoneOpened = 0;
      String? resumedId;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDropClipTheme(Brightness.dark),
          home: Scaffold(
            body: DesktopTransfersPage(
              transfers: const [
                DesktopTransferRecord(
                  id: 'tx-part',
                  fileName: 'video.mp4.part',
                  peerName: 'Pixel 8',
                  totalBytes: 100,
                  transferredBytes: 50,
                  resumablePart: true,
                ),
              ],
              onSendSampleFile: () => sampleSent++,
              onOpenDropzone: () => dropzoneOpened++,
              onResumeTransfer: (id) => resumedId = id,
            ),
          ),
        ),
      );

      expect(find.text('video.mp4.part'), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn-desktop-send-sample')));
      expect(sampleSent, 1);

      await tester.tap(find.byKey(const Key('btn-desktop-open-dropzone')));
      expect(dropzoneOpened, 1);

      await tester.tap(find.byKey(const Key('btn-desktop-resume-tx-part')));
      expect(resumedId, 'tx-part');
    });
  });
}
