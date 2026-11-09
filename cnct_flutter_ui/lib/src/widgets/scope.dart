import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../controller.dart';
import '../l10n/chat_l10n.dart';
import '../theme.dart';

/// What every piece of the chat draws from: the controller, the tokens with their values decided,
/// the words in the chosen language, and the type scale.
class ChatScope extends InheritedWidget {
  const ChatScope({
    super.key,
    required this.controller,
    required this.theme,
    required this.l10n,
    required this.styles,
    required this.onClose,
    required this.onOpenLink,
    required super.child,
  });

  final ChatController controller;
  final ResolvedChatTheme theme;
  final ChatL10n l10n;
  final ChatTextStyles styles;
  final VoidCallback? onClose;
  final ValueChanged<Uri> onOpenLink;

  static ChatScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChatScope>();
    assert(scope != null, 'A CNCT chat widget was built outside CnctChat.');
    return scope!;
  }

  @override
  bool updateShouldNotify(ChatScope oldWidget) =>
      theme != oldWidget.theme ||
      l10n != oldWidget.l10n ||
      styles != oldWidget.styles ||
      onClose != oldWidget.onClose ||
      controller != oldWidget.controller;

  /// [child] with everything the chat applies around itself: its language, its direction, its own
  /// Material theme and type. For the sheets and routes the chat opens, which live under the app's
  /// navigator rather than under the chat, and would otherwise pick up the app's theme and the
  /// app's direction instead of the chat's.
  Widget wrap(Widget child) => ChatSurroundings(scope: this, child: child);
}

/// The type scale, in the theme's font, at the sizes the hosted widget uses. Every size scales with
/// the system's text size: nothing here is fixed height.
@immutable
class ChatTextStyles {
  const ChatTextStyles({
    required this.body,
    required this.small,
    required this.caption,
    required this.title,
    required this.heading,
  });

  factory ChatTextStyles.from(ResolvedChatTheme theme, ThemeData material) {
    final base = material.textTheme.bodyLarge!.copyWith(
      fontFamily: theme.font,
      fontFamilyFallback: theme.fontFallback,
      color: theme.text,
      fontSize: 15,
      height: 1.35,
      letterSpacing: 0,
    );
    return ChatTextStyles(
      body: base,
      small: base.copyWith(fontSize: 13, height: 1.3, color: theme.textMuted),
      caption: base.copyWith(fontSize: 12, height: 1.25, color: theme.textMuted),
      title: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25),
      heading: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
    );
  }

  final TextStyle body;
  final TextStyle small;
  final TextStyle caption;
  final TextStyle title;
  final TextStyle heading;
}

/// A Material theme made from the chat's tokens and nothing else, so the text fields, buttons and
/// ripples inside the chat look like the chat — not like the app around it. It applies only below
/// the chat; the app's own theme is untouched.
ThemeData chatMaterialTheme(ResolvedChatTheme theme) {
  final scheme = ColorScheme(
    brightness: theme.isDark ? Brightness.dark : Brightness.light,
    primary: theme.primary,
    onPrimary: theme.onPrimary,
    secondary: theme.primary,
    onSecondary: theme.onPrimary,
    error: theme.danger,
    onError: readableInk(theme.danger),
    surface: theme.background,
    onSurface: theme.text,
    surfaceContainerHighest: theme.surface,
    outline: theme.border,
    outlineVariant: theme.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: scheme.brightness,
    fontFamily: theme.font,
    fontFamilyFallback: theme.fontFallback,
    scaffoldBackgroundColor: theme.background,
    canvasColor: theme.background,
    dividerColor: theme.border,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: theme.accentOn(theme.background),
      selectionColor: theme.primary.withValues(alpha: 0.28),
      selectionHandleColor: theme.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: theme.primary),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: theme.background,
      modalBackgroundColor: theme.background,
      showDragHandle: true,
      dragHandleColor: theme.border,
    ),
  );
}

/// The locale, direction, theme and default text style of the chat, applied around [child].
class ChatSurroundings extends StatelessWidget {
  const ChatSurroundings({super.key, required this.scope, required this.child});

  final ChatScope scope;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final material = chatMaterialTheme(scope.theme);
    return ChatScope(
      controller: scope.controller,
      theme: scope.theme,
      l10n: scope.l10n,
      styles: scope.styles,
      onClose: scope.onClose,
      onOpenLink: scope.onOpenLink,
      // The Material, Cupertino and widgets localizations in the chat's language, for the few
      // words Flutter itself says — "Paste" over a text field, a tooltip — and for the direction.
      child: Localizations.override(
        context: context,
        locale: Locale(scope.l10n.language),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Directionality(
          textDirection: scope.l10n.direction,
          child: Theme(
            data: material,
            child: DefaultTextStyle(
              style: scope.styles.body,
              child: IconTheme(
                data: IconThemeData(color: scope.theme.text, size: 22),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
