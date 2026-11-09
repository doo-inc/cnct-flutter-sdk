import 'package:cnct_flutter_ui/cnct_flutter_ui.dart';
import 'package:cnct_flutter_ui/fixture.dart';
import 'package:flutter/material.dart';

/// Both are `--dart-define`s rather than constants in the source. Without a key the app runs the
/// fixture conversation — CNCT's scripted chat, on a fake transport — so it can be tried with no
/// account and no network. The host is optional: without it the SDK goes to CNCT production,
/// `https://app.doo.ooo`.
const publicKey = String.fromEnvironment('CNCT_PUBLIC_KEY');
const baseUrl = String.fromEnvironment('CNCT_BASE_URL');

void main() => runApp(const ExampleApp());

/// The red, small-cornered look of the spec's "custom" screenshots: what a business pins in code
/// when it does not want the console to decide.
const customTheme = CnctChatTheme(primary: Color(0xFFD7262E), cornerRadius: 8);

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.inboxKey = publicKey});

  /// The inbox's public key. Empty runs the fixture.
  final String inboxKey;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  CnctChatLanguage _language = CnctChatLanguage.auto;
  CnctChatAppearance _appearance = CnctChatAppearance.system;
  bool _custom = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CNCT chat',
      debugShowCheckedModeBanner: false,
      // The app's own theme. The chat ignores it: what it looks like is the inbox's settings, then
      // whatever CnctChatTheme says below.
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1F6FEB), useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: Text(widget.inboxKey.isEmpty ? 'CNCT chat · fixture' : 'CNCT chat'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: _Switches(
              language: _language,
              appearance: _appearance,
              custom: _custom,
              onLanguage: (value) => setState(() => _language = value),
              onAppearance: (value) => setState(() => _appearance = value),
              onCustom: (value) => setState(() => _custom = value),
            ),
          ),
        ),
        body: widget.inboxKey.isEmpty
            ? _FixtureChat(
                // The fixture's own words follow the language too, so Arabic shows the whole
                // Arabic conversation. Switch an English one to the Arabic interface to see each
                // message keep its own direction.
                key: ValueKey(_language),
                language: _language,
                theme: _theme,
              )
            : CnctChat.publicKey(
                widget.inboxKey,
                cnct: baseUrl.isEmpty ? Cnct() : Cnct.host(baseUrl),
                language: _language,
                theme: _theme,
                onEvent: (event) => debugPrint('[example] $event'),
              ),
      ),
    );
  }

  CnctChatTheme get _theme => _custom
      ? CnctChatTheme(
          primary: customTheme.primary,
          cornerRadius: customTheme.cornerRadius,
          appearance: _appearance,
        )
      : CnctChatTheme(appearance: _appearance);
}

/// The fixture conversation in a real CnctChat, answering what is sent.
class _FixtureChat extends StatefulWidget {
  const _FixtureChat({super.key, required this.language, required this.theme});

  final CnctChatLanguage language;
  final CnctChatTheme theme;

  @override
  State<_FixtureChat> createState() => _FixtureChatState();
}

class _FixtureChatState extends State<_FixtureChat> {
  late final CnctChatFixture _fixture = CnctChatFixture(
    language: widget.language == CnctChatLanguage.ar ? 'ar' : 'en',
    interactive: true,
  );
  late final Future<void> _ready = _fixture.prepare();

  @override
  void dispose() {
    _fixture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) => snapshot.connectionState != ConnectionState.done
          ? const Center(child: CircularProgressIndicator())
          : CnctChat(
              client: _fixture.client,
              language: widget.language,
              theme: widget.theme,
              onEvent: (event) => debugPrint('[example] $event'),
            ),
    );
  }
}

class _Switches extends StatelessWidget {
  const _Switches({
    required this.language,
    required this.appearance,
    required this.custom,
    required this.onLanguage,
    required this.onAppearance,
    required this.onCustom,
  });

  final CnctChatLanguage language;
  final CnctChatAppearance appearance;
  final bool custom;
  final ValueChanged<CnctChatLanguage> onLanguage;
  final ValueChanged<CnctChatAppearance> onAppearance;
  final ValueChanged<bool> onCustom;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          SegmentedButton<CnctChatLanguage>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: CnctChatLanguage.auto, label: Text('Auto')),
              ButtonSegment(value: CnctChatLanguage.en, label: Text('English')),
              ButtonSegment(value: CnctChatLanguage.ar, label: Text('العربية')),
            ],
            selected: {language},
            onSelectionChanged: (value) => onLanguage(value.single),
          ),
          const SizedBox(width: 12),
          SegmentedButton<CnctChatAppearance>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: CnctChatAppearance.system,
                icon: Icon(Icons.brightness_auto),
                tooltip: 'Follow the device',
              ),
              ButtonSegment(
                value: CnctChatAppearance.light,
                icon: Icon(Icons.light_mode),
                tooltip: 'Light',
              ),
              ButtonSegment(
                value: CnctChatAppearance.dark,
                icon: Icon(Icons.dark_mode),
                tooltip: 'Dark',
              ),
            ],
            selected: {appearance},
            onSelectionChanged: (value) => onAppearance(value.single),
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Custom theme'),
            selected: custom,
            onSelected: onCustom,
          ),
        ],
      ),
    );
  }
}
