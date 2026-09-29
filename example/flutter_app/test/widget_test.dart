import 'package:cnct_chat_example/main.dart';
import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('without a key, the app says how to supply one, and that the host is optional',
      (tester) async {
    await tester.pumpWidget(ExampleApp(tokenStore: CnctTokenStore.memory()));
    // The key is a --dart-define, so an unconfigured build must say so rather than fail at a request.
    expect(find.textContaining('CNCT_PUBLIC_KEY'), findsOneWidget);
    // The host is not: without CNCT_BASE_URL the app talks to CNCT production.
    expect(find.textContaining('CNCT_BASE_URL is optional'), findsOneWidget);
    expect(find.textContaining('https://app.doo.ooo'), findsOneWidget);
  });
}
