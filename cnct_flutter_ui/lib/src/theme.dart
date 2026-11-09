import 'dart:math' as math;

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/widgets.dart';

/// Light, dark, or whatever the device is set to.
enum CnctChatAppearance { light, dark, system }

/// The colour tokens, for one appearance. Every one is optional: what is left out comes from the
/// inbox's settings in the CNCT console, and then from the built-in defaults.
@immutable
class CnctChatColors {
  const CnctChatColors({
    this.primary,
    this.onPrimary,
    this.background,
    this.surface,
    this.text,
    this.textMuted,
    this.border,
    this.visitorBubble,
    this.onVisitorBubble,
    this.agentBubble,
    this.onAgentBubble,
  });

  /// The brand colour: the send button, links, the header accent. Default: the inbox's brand
  /// colour, else CNCT's `#b52d93`.
  final Color? primary;

  /// Text and icons on [primary]. Default: black or white, whichever reads on it.
  final Color? onPrimary;

  /// The screen. Default: `#ffffff` light, `#0f1115` dark.
  final Color? background;

  /// The header, the composer and cards. Default: `#f6f7f9` light, `#171a21` dark.
  final Color? surface;

  /// Main text. Default: `#111418` light, `#eef0f3` dark.
  final Color? text;

  /// Timestamps and hints. Default: `#5b6573` light, `#9aa3af` dark.
  final Color? textMuted;

  /// Dividers and outlines. Default: `#e3e6ea` light, `#2a2f38` dark.
  final Color? border;

  /// The customer's own messages. Default: [primary].
  final Color? visitorBubble;

  /// Text on [visitorBubble]. Default: [onPrimary].
  final Color? onVisitorBubble;

  /// The team's and the assistant's messages. Default: [surface].
  final Color? agentBubble;

  /// Text on [agentBubble]. Default: [text].
  final Color? onAgentBubble;
}

/// How the chat looks: the spec's tokens, with the same names on every CNCT SDK.
///
/// **Precedence: what the app passes here, then the inbox's widget settings on the server, then
/// the built-in defaults.** So a business can brand the chat from the CNCT console with no code at
/// all, or pin any part of it in code.
///
/// Colour tokens set directly here apply to both appearances; [light] and [dark] set them for one
/// appearance only, and win over the direct ones. An app may set either, both or neither.
///
/// The chat never reads the host app's `ThemeData`, and never changes it: it draws only from these
/// tokens, so it looks the same inside a Material app, a Cupertino app or neither.
///
/// ```dart
/// CnctChat(
///   client: chat,
///   theme: const CnctChatTheme(
///     primary: Color(0xFFD7262E),
///     cornerRadius: 8,
///     font: 'Inter',
///   ),
/// )
/// ```
@immutable
class CnctChatTheme extends CnctChatColors {
  const CnctChatTheme({
    super.primary,
    super.onPrimary,
    super.background,
    super.surface,
    super.text,
    super.textMuted,
    super.border,
    super.visitorBubble,
    super.onVisitorBubble,
    super.agentBubble,
    super.onAgentBubble,
    this.light,
    this.dark,
    this.cornerRadius,
    this.font,
    this.fontFallback,
    this.logo,
    this.title,
    this.appearance,
    this.showPoweredBy,
  });

  /// Colours for the light appearance only.
  final CnctChatColors? light;

  /// Colours for the dark appearance only.
  final CnctChatColors? dark;

  /// The corners of bubbles and cards, in logical pixels. Default: 18.
  final double? cornerRadius;

  /// The typeface, as a font family the app has registered (in its `pubspec.yaml`, or through a
  /// package that registers fonts). Default: the system's.
  final String? font;

  /// Families to try, in order, for characters [font] does not have — an Arabic face to go with a
  /// Latin brand font, say. The Flutter half of a CSS `font-family` list. Default: the system's own
  /// fallback, which on phones already covers Arabic.
  final List<String>? fontFallback;

  /// The header image. Default: the inbox's logo, else the business's first letter on [primary].
  final ImageProvider? logo;

  /// The header title. Default: the business's name.
  final String? title;

  /// Default: the inbox's appearance setting, where `auto` means [CnctChatAppearance.system].
  final CnctChatAppearance? appearance;

  /// Whether the "Powered by CNCT" line shows. Default: the inbox's branding setting.
  final bool? showPoweredBy;
}

/// Built-in defaults, light and dark — the hosted widget's own.
abstract final class CnctChatDefaults {
  static const primary = Color(0xFFB52D93);
  static const cornerRadius = 18.0;

  static const light = CnctChatColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F7F9),
    text: Color(0xFF111418),
    textMuted: Color(0xFF5B6573),
    border: Color(0xFFE3E6EA),
  );

  static const dark = CnctChatColors(
    background: Color(0xFF0F1115),
    surface: Color(0xFF171A21),
    text: Color(0xFFEEF0F3),
    textMuted: Color(0xFF9AA3AF),
    border: Color(0xFF2A2F38),
  );
}

/// Which ink reads on a colour: near-black or white, by the sRGB luminance the CNCT server computes
/// and the hosted widget repeats. Half the palette a non-designer reaches for makes white text
/// unreadable, and the alternative is a second colour picker asking them to solve contrast by eye.
Color readableInk(Color background) =>
    _luminance(background) > 0.55 ? const Color(0xFF141414) : const Color(0xFFFFFFFF);

/// The WCAG contrast ratio between two colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final first = _luminance(a);
  final second = _luminance(b);
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

double _luminance(Color color) {
  double channel(int value) {
    final c = value / 255;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = color.toARGB32();
  return 0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
}

/// `#rrggbb` to a colour, or null for anything else.
Color? parseHexColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// The system font's fallback in tests, where there is no system font: the screenshot test loads
/// an Arabic face and names it here. Null — no extra fallback — everywhere else.
@visibleForTesting
List<String>? debugSystemFontFallback;

/// Every token with its value decided: the app's, the server's or the default. What the widgets
/// draw from — nothing below this reads `CnctChatTheme` or the inbox directly.
@immutable
class ResolvedChatTheme {
  const ResolvedChatTheme({
    required this.isDark,
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.visitorBubble,
    required this.onVisitorBubble,
    required this.agentBubble,
    required this.onAgentBubble,
    required this.cornerRadius,
    required this.font,
    required this.fontFallback,
    required this.logo,
    required this.title,
    required this.showPoweredBy,
  });

  /// Decide every token. [inbox] is null until `boot()` has answered, when only the app's tokens
  /// and the defaults apply.
  factory ResolvedChatTheme.resolve({
    CnctChatTheme? app,
    CnctChatInbox? inbox,
    required Brightness platformBrightness,
  }) {
    final brand = inbox?.widget.brand;
    final appearance = app?.appearance ??
        switch (brand?.appearance) {
          CnctAppearanceSetting.dark => CnctChatAppearance.dark,
          CnctAppearanceSetting.auto => CnctChatAppearance.system,
          _ => CnctChatAppearance.light,
        };
    final isDark = appearance == CnctChatAppearance.dark ||
        (appearance == CnctChatAppearance.system && platformBrightness == Brightness.dark);
    final mode = isDark ? app?.dark : app?.light;
    final defaults = isDark ? CnctChatDefaults.dark : CnctChatDefaults.light;

    Color? pick(Color? Function(CnctChatColors colors) token) =>
        (mode == null ? null : token(mode)) ?? (app == null ? null : token(app));

    final primary =
        pick((c) => c.primary) ?? parseHexColor(brand?.color) ?? CnctChatDefaults.primary;
    final onPrimary = pick((c) => c.onPrimary) ?? readableInk(primary);
    final surface = pick((c) => c.surface) ?? defaults.surface!;
    final text = pick((c) => c.text) ?? defaults.text!;
    final visitorBubble = pick((c) => c.visitorBubble);
    final agentBubble = pick((c) => c.agentBubble) ?? surface;

    return ResolvedChatTheme(
      isDark: isDark,
      primary: primary,
      onPrimary: onPrimary,
      background: pick((c) => c.background) ?? defaults.background!,
      surface: surface,
      text: text,
      textMuted: pick((c) => c.textMuted) ?? defaults.textMuted!,
      border: pick((c) => c.border) ?? defaults.border!,
      visitorBubble: visitorBubble ?? primary,
      // A bubble colour of the app's own, with no ink for it, gets the ink that reads on it rather
      // than the ink chosen for a different colour.
      onVisitorBubble: pick((c) => c.onVisitorBubble) ??
          (visitorBubble == null ? onPrimary : readableInk(visitorBubble)),
      agentBubble: agentBubble,
      onAgentBubble: pick((c) => c.onAgentBubble) ?? text,
      cornerRadius: app?.cornerRadius ?? CnctChatDefaults.cornerRadius,
      font: app?.font,
      fontFallback: app?.fontFallback ?? debugSystemFontFallback,
      logo: app?.logo ??
          (brand?.avatarUrl == null ? null : NetworkImage(brand!.avatarUrl!) as ImageProvider),
      title: app?.title ?? inbox?.business ?? '',
      showPoweredBy: app?.showPoweredBy ?? brand?.showBranding ?? true,
    );
  }

  final bool isDark;
  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color visitorBubble;
  final Color onVisitorBubble;
  final Color agentBubble;
  final Color onAgentBubble;
  final double cornerRadius;
  final String? font;
  final List<String>? fontFallback;
  final ImageProvider? logo;
  final String title;
  final bool showPoweredBy;

  /// The brand colour where it reads on [on] — links, outlined buttons — and the plain text colour
  /// where it would not. A brand pink is fine on white and unreadable on a dark card; the spec asks
  /// for 4.5:1 for text, whatever colour the business picked.
  Color accentOn(Color on, {Color? otherwise}) =>
      contrastRatio(primary, on) >= 4.5 ? primary : (otherwise ?? text);

  /// The red of a message that did not send. Not a token: it means the same thing for every brand.
  Color get danger => isDark ? const Color(0xFFF97066) : const Color(0xFFB42318);
}
