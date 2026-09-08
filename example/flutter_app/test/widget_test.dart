import 'package:cnct_chat_example/main.dart';
import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('without a host and a key, the app says how to supply them', (tester) async {
    await tester.pumpWidget(ExampleApp(tokenStore: CnctTokenStore.memory()));
    // Both are --dart-defines, so an unconfigured build must say so rather than fail at a request.
    expect(find.textContaining('CNCT_BASE_URL'), findsOneWidget);
    expect(find.textContaining('CNCT_PUBLIC_KEY'), findsOneWidget);
  });
}
