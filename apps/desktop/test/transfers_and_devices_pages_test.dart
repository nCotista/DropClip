import 'package:dropclip_desktop/src/demo_data.dart';
import 'package:dropclip_desktop/src/transfers_and_devices_pages.dart';
import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopTransfersPage & DesktopDevicesPage (T1.3, T1.10–T1.12)', () {
    testWidgets('DesktopTransfersPage streams sample and resumes .part file', (
      WidgetTester tester,
    ) async {
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

    testWidgets(
      'DesktopDevicesPage computes 639589 SAS and handles quarantine/revoke',
      (WidgetTester tester) async {
        var verified = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDropClipTheme(Brightness.dark),
            home: Scaffold(
              body: DesktopDevicesPage(
                nearby: demoShellStatus.nearby,
                onDeviceVerified: () => verified++,
              ),
            ),
          ),
        );

        expect(find.text('SAS: 639589'), findsOneWidget);
        await tester.tap(find.byKey(const Key('btn-desktop-confirm-sas')));
        await tester.pumpAndSettle();
        expect(verified, 1);
        expect(
          find.textContaining('Peer pinned in Trusted Peer Store'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('btn-quarantine-Pixel 8')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('btn-confirm-revoke-Pixel 8')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('btn-confirm-revoke-Pixel 8')));
        await tester.pumpAndSettle();
        expect(find.text('Status: REVOKED'), findsOneWidget);
      },
    );
  });
}
