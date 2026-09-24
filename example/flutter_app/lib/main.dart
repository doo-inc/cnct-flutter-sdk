import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'token_store.dart';

/// Both are `--dart-define`s rather than constants in the source. The host is optional — without it
/// the SDK goes to CNCT production, `https://app.doo.ooo` — and is a build flag for the times it is
/// something else, like a CNCT on your own laptop.
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
      home: publicKey.isEmpty
          ? const _Missing()
          : ChatScreen(
              // One place holds the host. Everything the SDK does — HTTP and the socket alike —
              // follows it, because the socket origin is derived rather than configured separately.
              cnct: baseUrl.isEmpty ? Cnct() : Cnct.host(baseUrl),
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
            '  --dart-define=CNCT_PUBLIC_KEY=your-inbox-public-key\n\n'
            'CNCT_BASE_URL is optional: without it the app talks to https://app.doo.ooo.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
