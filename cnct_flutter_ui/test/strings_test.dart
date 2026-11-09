import 'dart:convert';
import 'dart:io';

import 'package:cnct_flutter_ui/src/l10n/chat_l10n.dart';
import 'package:cnct_flutter_ui/src/l10n/extra_strings.dart';
import 'package:cnct_flutter_ui/src/l10n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Dart table is exactly the shared strings.json — run tool/generate_strings.dart', () {
    final shared = (jsonDecode(File('../docs/chat-ui/strings.json').readAsStringSync())
            as Map<String, dynamic>)
        .map((language, words) =>
            MapEntry(language, (words as Map<String, dynamic>).cast<String, String>()));
    expect(cnctStrings, equals(shared));
  });

  test('English and Arabic have the same keys, and no Arabic word is empty', () {
    expect(cnctStrings['en']!.keys.toSet(), cnctStrings['ar']!.keys.toSet());
    expect(cnctStrings['en']!, hasLength(129));
    for (final MapEntry(:key, :value) in cnctStrings['ar']!.entries) {
      expect(value.trim(), isNotEmpty, reason: 'Arabic "$key" is empty');
    }
  });

  test('the Flutter-only words follow the same rules, and never shadow a shared key', () {
    expect(cnctExtraStrings['en']!.keys.toSet(), cnctExtraStrings['ar']!.keys.toSet());
    for (final language in ['en', 'ar']) {
      for (final MapEntry(:key, :value) in cnctExtraStrings[language]!.entries) {
        expect(value.trim(), isNotEmpty, reason: '$language "$key" is empty');
        expect(cnctStrings[language]!.containsKey(key), isFalse, reason: '"$key" is shared');
      }
    }
  });

  test('every placeholder in an English word is in its Arabic one', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final table in [cnctStrings, cnctExtraStrings]) {
      for (final MapEntry(:key, :value) in table['en']!.entries) {
        final english = placeholder.allMatches(value).map((m) => m[1]).toSet();
        final arabic = placeholder.allMatches(table['ar']![key]!).map((m) => m[1]).toSet();
        expect(arabic, english, reason: '"$key" has different placeholders');
      }
    }
  });

  group('looking a word up', () {
    test('fills placeholders', () {
      expect(ChatL10n('en').t('tooBig', {'name': 'film.mp4'}), 'film.mp4 is over 50 MB.');
      expect(ChatL10n('ar').t('removeFile', {'name': 'invoice.pdf'}), 'إزالة invoice.pdf');
    });

    test('an app override wins, in its own language only', () {
      final l10n = ChatL10n('ar', overrides: {
        'ar': {'writeMessage': 'اكتب هنا'},
        'en': {'send': 'Go'},
      });
      expect(l10n.t('writeMessage'), 'اكتب هنا');
      expect(l10n.t('send'), 'إرسال');
    });

    test('a missing word falls back to English, never to the key', () {
      // A key only the English override knows: the Arabic chat says it in English.
      final l10n = ChatL10n('ar', overrides: {
        'en': {'brandNew': 'Something new'},
      });
      expect(l10n.t('brandNew'), 'Something new');
      expect(ChatL10n('ar').t('notAKey'), isNot('notAKey'));
    });
  });
}
