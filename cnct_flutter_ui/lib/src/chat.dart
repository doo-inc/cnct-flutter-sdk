import 'dart:async';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'events.dart';
import 'files/prepare.dart';
import 'files/source.dart';
import 'l10n/chat_l10n.dart';
import 'theme.dart';
import 'widgets/scope.dart';
import 'widgets/screens.dart';

/// The device's IANA time zone — `Asia/Bahrain` — for a chat client an app makes itself:
///
/// ```dart
/// final chat = Cnct().chat(CnctChatPublicKey(key), timeZone: cnctDeviceTimeZone);
/// ```
///
/// [CnctChat.publicKey] wires it for you. Null where the platform cannot say, which sends nothing.
Future<String?> cnctDeviceTimeZone() async {
  try {
    final zone = await FlutterTimezone.getLocalTimezone().timeout(const Duration(seconds: 2));
    return zone.identifier.isEmpty ? null : zone.identifier;
  } catch (_) {
    return null;
  }
}

/// A visitor's session token in the app's shared preferences, so somebody who chatted last week
/// comes back to their own conversation. What [CnctChat.publicKey] uses unless told otherwise.
CnctTokenStore cnctPreferencesTokenStore() => CnctTokenStore.delegate(
      read: (key) async => (await SharedPreferences.getInstance()).getString(key),
      write: (key, value) async => (await SharedPreferences.getInstance()).setString(key, value),
      clear: (key) async => (await SharedPreferences.getInstance()).remove(key),
    );

/// **CNCT live chat, ready-made**: a conversation screen to put anywhere in a Flutter app — a tab,
/// a sheet, a page of its own ([CnctChatPage]).
///
/// It takes the same options as the chat UI of every CNCT SDK:
///
/// | Option     | What it does                                                                  |
/// | ---------- | ----------------------------------------------------------------------------- |
/// | `client`   | The headless chat client — or a public key, with [CnctChat.publicKey].        |
/// | `theme`    | Brand colours, font, corners, logo, title, appearance. See [CnctChatTheme].   |
/// | `language` | English, Arabic, or `auto`. Default: the inbox's setting, then the device.    |
/// | `strings`  | Your own words for any key, per language: `{'en': {'writeMessage': '…'}}`.    |
/// | `identity` | One of your signed-in users. See [CnctChatIdentity].                          |
/// | `onClose`  | The header's close button. Hidden when this is null.                          |
/// | `onEvent`  | Analytics: opened, started, sent, attachment sent, ended, rated.              |
///
/// ```dart
/// CnctChat.publicKey('your-inbox-public-key', onClose: () => Navigator.pop(context))
/// ```
///
/// It brings its own look and never reads or changes the app's `ThemeData`; the app's Material,
/// Cupertino or custom theme stays exactly as it was around it.
class CnctChat extends StatefulWidget {
  /// The chat on a client the app made — to share it with a badge that counts unread replies, say,
  /// or to point it at another host. The app owns the client and disposes of it.
  const CnctChat({
    super.key,
    required CnctChatClient this.client,
    this.theme,
    this.language,
    this.strings,
    this.identity,
    this.onClose,
    this.onEvent,
  })  : publicKey = null,
        cnct = null,
        tokenStore = null,
        fileSource = null,
        imageDecoder = null;

  /// The chat on an inbox's public key. The chat makes its client, keeps the visitor's session in
  /// shared preferences unless [tokenStore] says otherwise, sends the device's time zone, and
  /// closes the client when it goes.
  const CnctChat.publicKey(
    String this.publicKey, {
    super.key,
    this.cnct,
    this.tokenStore,
    this.theme,
    this.language,
    this.strings,
    this.identity,
    this.onClose,
    this.onEvent,
  })  : client = null,
        fileSource = null,
        imageDecoder = null;

  /// For tests: a scripted picker and a stand-in image decoder.
  @visibleForTesting
  const CnctChat.debug({
    super.key,
    required CnctChatClient this.client,
    this.theme,
    this.language,
    this.strings,
    this.identity,
    this.onClose,
    this.onEvent,
    this.fileSource,
    this.imageDecoder,
  })  : publicKey = null,
        cnct = null,
        tokenStore = null;

  final CnctChatClient? client;
  final String? publicKey;

  /// The host and configuration, for [CnctChat.publicKey]. Default: CNCT production.
  final Cnct? cnct;

  /// Where the visitor's session is kept, for [CnctChat.publicKey]. Default: shared preferences.
  final CnctTokenStore? tokenStore;

  /// How the chat looks. Anything left out comes from the inbox's settings, then the defaults.
  final CnctChatTheme? theme;

  /// Null follows the inbox's setting and then the device; [CnctChatLanguage.auto] follows the
  /// device even where the business pinned a language.
  final CnctChatLanguage? language;

  /// Your own words for any key, per language: `{'en': {...}, 'ar': {...}}`. The keys are those of
  /// `docs/chat-ui/strings.json`.
  final Map<String, Map<String, String>>? strings;

  /// One of your signed-in users. Applied before anything else is read, so the conversation shown
  /// is theirs. A failure is logged and the visitor carries on anonymously.
  final CnctChatIdentity? identity;

  /// The header's close button. Hidden when null.
  final VoidCallback? onClose;

  /// What happened, for analytics. Never carries what anybody wrote.
  final ValueChanged<CnctChatUiEvent>? onEvent;

  final FileSource? fileSource;
  final ImageDecoder? imageDecoder;

  @override
  State<CnctChat> createState() => _CnctChatState();
}

class _CnctChatState extends State<CnctChat> with WidgetsBindingObserver {
  late ChatController _controller;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = _makeController();
    unawaited(_controller.open());
  }

  ChatController _makeController() {
    final given = widget.client;
    final client = given ??
        (widget.cnct ?? Cnct()).chat(
          CnctChatPublicKey(widget.publicKey!),
          tokenStore: widget.tokenStore ?? cnctPreferencesTokenStore(),
          timeZone: cnctDeviceTimeZone,
        );
    return ChatController(
      client: client,
      ownsClient: given == null,
      identity: widget.identity,
      onEvent: (event) => widget.onEvent?.call(event),
      files: widget.fileSource,
      decode: widget.imageDecoder,
    );
  }

  @override
  void didUpdateWidget(CnctChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client || oldWidget.publicKey != widget.publicKey) {
      _controller.dispose();
      _controller = _makeController();
      unawaited(_controller.open());
      return;
    }
    if (oldWidget.identity?.userId != widget.identity?.userId ||
        oldWidget.identity?.userHash != widget.identity?.userHash) {
      unawaited(_controller.setIdentity(widget.identity));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openLink(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[cnct] Could not open $uri: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final inbox = _controller.inbox;
        final theme = ResolvedChatTheme.resolve(
          app: widget.theme,
          inbox: inbox,
          platformBrightness: MediaQuery.platformBrightnessOf(context),
        );
        final l10n = ChatL10n(
          pickLanguage(
            app: widget.language,
            server: inbox?.widget.brand.language,
            device: WidgetsBinding.instance.platformDispatcher.locales,
          ),
          overrides: widget.strings,
        );
        // Only a reply on screen, in an app in the foreground, has been read.
        // ignore: deprecated_member_use — `valuesOf` replaced it in 3.35; this still runs on 3.27.
        _controller.onScreen = _foreground && TickerMode.of(context);

        final scope = ChatScope(
          controller: _controller,
          theme: theme,
          l10n: l10n,
          styles: ChatTextStyles.from(theme, chatMaterialTheme(theme)),
          onClose: widget.onClose,
          onOpenLink: _openLink,
          child: const SizedBox.shrink(),
        );
        return scope.wrap(
          Material(
            color: theme.background,
            child: Padding(
              // The composer rides above the keyboard wherever the chat is — inside a Scaffold that
              // already makes room (which leaves nothing here), or anywhere that does not.
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: switch (_controller.phase) {
                ChatPhase.loading => const LoadingScreen(),
                ChatPhase.unavailable => const UnavailableScreen(),
                ChatPhase.intro => const IntroScreen(),
                ChatPhase.chat => const ConversationScreen(),
              },
            ),
          ),
        );
      },
    );
  }
}

/// [CnctChat] as a full-screen page, for apps that open the chat rather than embed it.
///
/// ```dart
/// Navigator.of(context).push(CnctChatPage.route(publicKey: 'your-inbox-public-key'));
/// ```
///
/// Its close button pops the page unless [onClose] says otherwise.
class CnctChatPage extends StatelessWidget {
  const CnctChatPage({
    super.key,
    this.client,
    this.publicKey,
    this.cnct,
    this.tokenStore,
    this.theme,
    this.language,
    this.strings,
    this.identity,
    this.onClose,
    this.onEvent,
  }) : assert((client == null) != (publicKey == null), 'Pass a client or a public key, not both.');

  final CnctChatClient? client;
  final String? publicKey;
  final Cnct? cnct;
  final CnctTokenStore? tokenStore;
  final CnctChatTheme? theme;
  final CnctChatLanguage? language;
  final Map<String, Map<String, String>>? strings;
  final CnctChatIdentity? identity;
  final VoidCallback? onClose;
  final ValueChanged<CnctChatUiEvent>? onEvent;

  /// The page as a route, ready to push.
  static Route<void> route({
    CnctChatClient? client,
    String? publicKey,
    Cnct? cnct,
    CnctTokenStore? tokenStore,
    CnctChatTheme? theme,
    CnctChatLanguage? language,
    Map<String, Map<String, String>>? strings,
    CnctChatIdentity? identity,
    VoidCallback? onClose,
    ValueChanged<CnctChatUiEvent>? onEvent,
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => CnctChatPage(
          client: client,
          publicKey: publicKey,
          cnct: cnct,
          tokenStore: tokenStore,
          theme: theme,
          language: language,
          strings: strings,
          identity: identity,
          onClose: onClose,
          onEvent: onEvent,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final close = onClose ?? () => Navigator.of(context).maybePop();
    return client != null
        ? CnctChat(
            client: client!,
            theme: theme,
            language: language,
            strings: strings,
            identity: identity,
            onClose: close,
            onEvent: onEvent,
          )
        : CnctChat.publicKey(
            publicKey!,
            cnct: cnct,
            tokenStore: tokenStore,
            theme: theme,
            language: language,
            strings: strings,
            identity: identity,
            onClose: close,
            onEvent: onEvent,
          );
  }
}
