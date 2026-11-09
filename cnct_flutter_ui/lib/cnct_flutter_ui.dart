/// CNCT live chat for Flutter, ready-made: [CnctChat] to embed anywhere and [CnctChatPage] as a
/// full-screen route, brandable with [CnctChatTheme], in English and Arabic, right to left, with
/// photos and files both ways.
///
/// ```dart
/// CnctChat.publicKey('your-inbox-public-key')
/// ```
///
/// Built on `cnct_flutter_sdk`, which this library re-exports: everything the headless client
/// offers is one import away, for an app that wants both.
library;

export 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';

export 'src/chat.dart' show CnctChat, CnctChatPage, cnctDeviceTimeZone, cnctPreferencesTokenStore;
export 'src/events.dart';
export 'src/l10n/chat_l10n.dart' show CnctChatLanguage;
export 'src/l10n/strings.g.dart' show cnctStrings;
export 'src/theme.dart'
    show CnctChatAppearance, CnctChatColors, CnctChatDefaults, CnctChatTheme, readableInk;
