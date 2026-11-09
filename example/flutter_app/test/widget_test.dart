import 'package:cnct_chat_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('without a key, the app runs the fixture conversation in the chat UI',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ExampleApp());
    await settle(tester);

    expect(find.text('CNCT chat · fixture'), findsOneWidget);
    expect(find.textContaining('Can I pay by card?', findRichText: true), findsOneWidget);
    expect(find.text('Write a message…'), findsOneWidget);

    // The language switch: the whole interface, and the fixture's own words, in Arabic.
    await tester.tap(find.text('العربية'));
    await settle(tester);
    expect(find.textContaining('هل يمكنني الدفع بالبطاقة؟', findRichText: true), findsOneWidget);
    expect(find.text('اكتب رسالة…'), findsOneWidget);

    // The custom theme and the appearance switch are there to try.
    expect(find.text('Custom theme'), findsOneWidget);
    expect(find.byTooltip('Dark'), findsOneWidget);

    // Unmounted inside the test, so the fixture's timers stop before the test checks for them.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
