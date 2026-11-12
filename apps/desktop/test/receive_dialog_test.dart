import 'package:dropclip_desktop/src/transfer/receive_dialog.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _items = [
  FileOfferItem(
      itemId: 'i0',
      path: 'video.mp4',
      size: 2500000,
      sha256: '0' * 64,
      mime: 'video/mp4',
      modifiedAt: 0),
];

Future<Future<bool>> _ask(WidgetTester tester) async {
  late Future<bool> answer;
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
              onPressed: () =>
                  answer = askToReceive(context, 'Office PC', _items),
              child: const Text('go')))));
  await tester.tap(find.text('go'));
  await tester.pump();
  return answer;
}

void main() {
  testWidgets('Accept and Decline answer the offer', (tester) async {
    var answer = await _ask(tester);
    expect(find.text('Office PC wants to send you'), findsOneWidget);
    expect(find.text('video.mp4 · 2.5 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('receive-yes')));
    await tester.pump();
    expect(await answer, isTrue);

    answer = await _ask(tester);
    await tester.tap(find.byKey(const Key('receive-no')));
    await tester.pump();
    expect(await answer, isFalse);
  });

  testWidgets('no answer in 60 s declines (§7.4.5)', (tester) async {
    final answer = await _ask(tester);
    await tester.pump(const Duration(seconds: 61));
    expect(await answer, isFalse);
  });
}
