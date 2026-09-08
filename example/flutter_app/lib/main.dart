import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'token_store.dart';

/// Both are `--dart-define`s rather than constants in the source. The host especially: it is the one
/// value that changes between a laptop, a staging box and production, and the whole point of
/// [CnctConfig.baseUrl] is that changing it is a build flag rather than a code change.
const baseUrl = String.fromEnvironment('CNCT_BASE_URL');
const publicKey = String.fromEnvironment('CNCT_PUBLIC_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokenStore = await sharedPreferencesTokenStore();
  runApp(ExampleApp(tokenStore: tokenStore));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({required this.tokenStore, super.key});

  final CnctTokenStore tokenStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CNCT chat',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1F6FEB), useMaterial3: true),
      home: baseUrl.isEmpty || publicKey.isEmpty
          ? const _Missing()
          : ChatScreen(
              // One place holds the host. Everything the SDK does — HTTP and the socket alike —
              // follows it, because the socket origin is derived rather than configured separately.
              cnct: Cnct.host(baseUrl),
              publicKey: publicKey,
              tokenStore: tokenStore,
            ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Run with:\n\n'
            'flutter run \\\n'
            '  --dart-define=CNCT_BASE_URL=https://your-cnct-host \\\n'
            '  --dart-define=CNCT_PUBLIC_KEY=your-inbox-public-key',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
