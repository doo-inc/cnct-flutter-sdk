import 'dart:ui';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:cnct_flutter_ui/src/l10n/chat_l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// intl writes a narrow no-break space before AM and PM, as CLDR now does. Compared as a space.
String plain(String text) => text.replaceAll('\u202f', ' ');

void main() {
  setUpAll(initializeDateFormatting);

  group('choosing the language', () {
    test('the app’s choice wins', () {
      expect(
        pickLanguage(
          app: CnctChatLanguage.ar,
          server: CnctLanguageSetting.en,
          device: const [Locale('en')],
        ),
        'ar',
      );
    });

    test('then the business’s, from the console', () {
      expect(
        pickLanguage(server: CnctLanguageSetting.ar, device: const [Locale('en', 'GB')]),
        'ar',
      );
    });

    test('auto takes the first of the device’s languages that is Arabic or English', () {
      expect(
        pickLanguage(
          server: CnctLanguageSetting.auto,
          device: const [Locale('fr'), Locale('ar', 'BH'), Locale('en')],
        ),
        'ar',
      );
      expect(
        pickLanguage(device: const [Locale('de'), Locale('en', 'US'), Locale('ar')]),
        'en',
      );
    });

    test('and English when the device has neither', () {
      expect(pickLanguage(device: const [Locale('fr'), Locale('ur')]), 'en');
      expect(pickLanguage(device: const []), 'en');
    });

    test('an explicit auto from the app follows the device even over a pinned business', () {
      expect(
        pickLanguage(
          app: CnctChatLanguage.auto,
          server: CnctLanguageSetting.ar,
          device: const [Locale('en')],
        ),
        'en',
      );
    });
  });

  group('numbers and dates', () {
    test('Arabic uses Latin digits', () {
      final when = DateTime(2026, 9, 8, 14, 5);
      final clock = ChatL10n('ar').clock(when);
      expect(clock, contains('2:05'));
      expect(clock, isNot(matches(RegExp('[٠-٩]'))));
      expect(plain(ChatL10n('en').clock(when)), '2:05 PM');
    });

    test('days are words when they can be, in the chat’s language', () {
      final now = DateTime(2026, 9, 8, 15);
      final ar = ChatL10n('ar', now: () => now);
      expect(ar.day(DateTime(2026, 9, 8, 9)), 'اليوم');
      expect(ar.day(DateTime(2026, 9, 7, 9)), 'أمس');
      expect(ar.day(DateTime(2026, 8, 3, 9)), contains('3'));
      expect(ar.day(DateTime(2026, 8, 3, 9)), isNot(matches(RegExp('[٠-٩]'))));
      final en = ChatL10n('en', now: () => now);
      expect(en.day(DateTime(2026, 8, 3, 9)), '3 August');
      expect(en.endedWhen(DateTime(2026, 9, 7, 9)), 'Conversation ended yesterday');
    });

    test('sizes keep their number and unit together, left to right', () {
      final l10n = ChatL10n('ar');
      expect(l10n.size(1258291), '\u20661.2 MB\u2069');
      expect(l10n.size(225280), '\u2066220 KB\u2069');
      expect(l10n.size(900), '\u2066900 B\u2069');
      expect(l10n.size(null), '');
    });
  });

  group('availability: the widget’s sentence', () {
    final now = DateTime(2026, 9, 8, 15);
    final l10n = ChatL10n('en', now: () => now);

    test('closed, with when the team is back and whether the assistant helps meanwhile', () {
      expect(
        plain(l10n.availability(
            CnctChatAvailability(open: false, opensAt: DateTime(2026, 9, 9, 9), assistant: true))),
        'The team is back tomorrow at 9:00 AM · our assistant can help now',
      );
      expect(
        plain(l10n
            .availability(CnctChatAvailability(open: false, opensAt: DateTime(2026, 9, 8, 18)))),
        'The team is back today at 6:00 PM',
      );
      expect(
        plain(l10n
            .availability(CnctChatAvailability(open: false, opensAt: DateTime(2026, 9, 13, 9)))),
        'The team is back Sunday at 9:00 AM',
      );
    });

    test('open, by how fast replies have really come', () {
      expect(l10n.availability(const CnctChatAvailability(open: true, replyMinutes: 0.5)),
          'Usually replies in under a minute');
      expect(l10n.availability(const CnctChatAvailability(open: true, replyMinutes: 4)),
          'Usually replies in a few minutes');
      expect(l10n.availability(const CnctChatAvailability(open: true, replyMinutes: 15)),
          'Usually replies in under 20 minutes');
      expect(l10n.availability(const CnctChatAvailability(open: true, replyMinutes: 300)),
          'Usually replies within a day');
    });

    test('without a measurement, it promises nothing', () {
      expect(l10n.availability(null), 'The team will reply here as soon as they can');
      expect(l10n.availability(const CnctChatAvailability(assistant: true)),
          'Our assistant replies straight away');
    });
  });
}
