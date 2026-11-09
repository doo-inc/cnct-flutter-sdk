import 'package:cnct_flutter_ui/cnct_flutter_ui.dart';
import 'package:cnct_flutter_ui/src/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

CnctChatInbox inboxWith(Map<String, Object?> brand) => CnctChatInbox.fromJson({
      'business': 'Bayside Café',
      'isActive': true,
      'widget': {'brand': brand},
    });

void main() {
  group('precedence: the app, then the server, then the defaults', () {
    test('with nothing anywhere, the built-in defaults', () {
      final theme = ResolvedChatTheme.resolve(platformBrightness: Brightness.light);
      expect(theme.primary, const Color(0xFFB52D93));
      expect(theme.background, const Color(0xFFFFFFFF));
      expect(theme.surface, const Color(0xFFF6F7F9));
      expect(theme.text, const Color(0xFF111418));
      expect(theme.textMuted, const Color(0xFF5B6573));
      expect(theme.border, const Color(0xFFE3E6EA));
      expect(theme.cornerRadius, 18);
      expect(theme.visitorBubble, theme.primary);
      expect(theme.onVisitorBubble, theme.onPrimary);
      expect(theme.agentBubble, theme.surface);
      expect(theme.onAgentBubble, theme.text);
      expect(theme.showPoweredBy, isTrue);
    });

    test('the inbox’s settings, where the app says nothing', () {
      final theme = ResolvedChatTheme.resolve(
        inbox: inboxWith({
          'color': '#1f6feb',
          'appearance': 'dark',
          'avatarUrl': 'https://cdn.test/logo.png',
          'showBranding': false,
        }),
        platformBrightness: Brightness.light,
      );
      expect(theme.primary, const Color(0xFF1F6FEB));
      expect(theme.isDark, isTrue);
      expect(theme.background, const Color(0xFF0F1115));
      expect(theme.logo, isA<NetworkImage>());
      expect(theme.title, 'Bayside Café');
      expect(theme.showPoweredBy, isFalse);
    });

    test('the app wins over the inbox, token by token', () {
      final theme = ResolvedChatTheme.resolve(
        app: const CnctChatTheme(
          primary: Color(0xFFD7262E),
          cornerRadius: 8,
          title: 'Support',
          appearance: CnctChatAppearance.light,
          showPoweredBy: true,
        ),
        inbox: inboxWith({'color': '#1f6feb', 'appearance': 'dark', 'showBranding': false}),
        platformBrightness: Brightness.dark,
      );
      expect(theme.primary, const Color(0xFFD7262E));
      expect(theme.cornerRadius, 8);
      expect(theme.title, 'Support');
      expect(theme.isDark, isFalse);
      expect(theme.showPoweredBy, isTrue);
      // What the app left out still comes from the inbox, then the defaults.
      expect(theme.background, const Color(0xFFFFFFFF));
    });

    test('light and dark colours apply to their own appearance, over the shared ones', () {
      const app = CnctChatTheme(
        primary: Color(0xFF00AA00),
        light: CnctChatColors(background: Color(0xFFFAFAFA)),
        dark: CnctChatColors(primary: Color(0xFF88FF88), background: Color(0xFF000000)),
      );
      final light = ResolvedChatTheme.resolve(app: app, platformBrightness: Brightness.light);
      final dark = ResolvedChatTheme.resolve(
        app: const CnctChatTheme(
          primary: Color(0xFF00AA00),
          appearance: CnctChatAppearance.dark,
          dark: CnctChatColors(primary: Color(0xFF88FF88), background: Color(0xFF000000)),
        ),
        platformBrightness: Brightness.light,
      );
      expect(light.primary, const Color(0xFF00AA00));
      expect(light.background, const Color(0xFFFAFAFA));
      expect(dark.primary, const Color(0xFF88FF88));
      expect(dark.background, const Color(0xFF000000));
      expect(dark.surface, const Color(0xFF171A21));
    });

    test('auto follows the device', () {
      final inbox = inboxWith({'appearance': 'auto'});
      expect(
        ResolvedChatTheme.resolve(inbox: inbox, platformBrightness: Brightness.dark).isDark,
        isTrue,
      );
      expect(
        ResolvedChatTheme.resolve(inbox: inbox, platformBrightness: Brightness.light).isDark,
        isFalse,
      );
    });

    test('a bubble colour of the app’s own gets the ink that reads on it', () {
      final theme = ResolvedChatTheme.resolve(
        app: const CnctChatTheme(visitorBubble: Color(0xFFFFE066)),
        platformBrightness: Brightness.light,
      );
      expect(theme.onVisitorBubble, const Color(0xFF141414));
      expect(theme.onPrimary, const Color(0xFFFFFFFF));
    });
  });

  group('onPrimary: the widget’s contrast rule', () {
    test('white on a dark colour, near-black on a light one', () {
      expect(readableInk(const Color(0xFFB52D93)), const Color(0xFFFFFFFF));
      expect(readableInk(const Color(0xFFD7262E)), const Color(0xFFFFFFFF));
      expect(readableInk(const Color(0xFF000000)), const Color(0xFFFFFFFF));
      expect(readableInk(const Color(0xFFFFE066)), const Color(0xFF141414));
      expect(readableInk(const Color(0xFFFFFFFF)), const Color(0xFF141414));
      expect(readableInk(const Color(0xFF7FDBFF)), const Color(0xFF141414));
    });

    test('the threshold is the server’s: luminance above 0.55', () {
      // #c4c4c4 has a luminance of 0.552; #c2c2c2, of 0.539.
      expect(readableInk(const Color(0xFFC4C4C4)), const Color(0xFF141414));
      expect(readableInk(const Color(0xFFC2C2C2)), const Color(0xFFFFFFFF));
    });
  });

  test('the default text colours read at 4.5:1 or better, in both appearances', () {
    for (final brightness in Brightness.values) {
      final theme = ResolvedChatTheme.resolve(
        app: CnctChatTheme(
          appearance:
              brightness == Brightness.dark ? CnctChatAppearance.dark : CnctChatAppearance.light,
        ),
        platformBrightness: brightness,
      );
      for (final (ink, ground) in [
        (theme.text, theme.background),
        (theme.text, theme.surface),
        (theme.textMuted, theme.background),
        (theme.textMuted, theme.surface),
        (theme.onPrimary, theme.primary),
        (theme.danger, theme.background),
      ]) {
        expect(contrastRatio(ink, ground), greaterThanOrEqualTo(4.5),
            reason: '$ink on $ground, ${brightness.name}');
      }
    }
  });

  test('the accent falls back to the text colour where the brand would not read', () {
    final dark = ResolvedChatTheme.resolve(
      app: const CnctChatTheme(appearance: CnctChatAppearance.dark),
      platformBrightness: Brightness.dark,
    );
    expect(dark.accentOn(dark.surface), dark.text);
    final light = ResolvedChatTheme.resolve(platformBrightness: Brightness.light);
    expect(light.accentOn(light.background), light.primary);
  });
}
