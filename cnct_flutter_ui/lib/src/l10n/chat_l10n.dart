import 'dart:ui' show Locale, TextDirection;

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'extra_strings.dart';
import 'strings.g.dart';

/// The chat's language: English, Arabic, or whichever of the two the device prefers.
enum CnctChatLanguage { auto, en, ar }

/// Which language the chat speaks.
///
/// The app's choice wins; then the business's, from the CNCT console; and `auto` at either step
/// means the device: the first of its preferred languages that is Arabic or English, else English.
/// A `null` [app] is "not chosen", which defers to the business — an explicit
/// [CnctChatLanguage.auto] is the app asking for the device even where the business pinned one.
String pickLanguage({
  CnctChatLanguage? app,
  CnctLanguageSetting? server,
  required List<Locale> device,
}) {
  if (app == CnctChatLanguage.en || app == CnctChatLanguage.ar) return app!.name;
  if (app == null) {
    if (server == CnctLanguageSetting.en) return 'en';
    if (server == CnctLanguageSetting.ar) return 'ar';
  }
  for (final locale in device) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'ar' || code == 'en') return code;
  }
  return 'en';
}

/// Every word, time and size the chat shows, in one language.
class ChatL10n {
  ChatL10n(this.language, {Map<String, Map<String, String>>? overrides, DateTime Function()? now})
      : _overrides = overrides ?? const {},
        _now = now ?? DateTime.now;

  /// `en` or `ar`.
  final String language;
  final Map<String, Map<String, String>> _overrides;
  final DateTime Function() _now;

  bool get isArabic => language == 'ar';

  /// The whole interface's direction. Pieces of user text take their own — see `bidi.dart`.
  TextDirection get direction => isArabic ? TextDirection.rtl : TextDirection.ltr;

  /// The word for [key], with `{name}` placeholders filled from [vars].
  ///
  /// The app's override for this language first, then the table, then English — the app's English
  /// override, then the table's. **Never the key itself**: a missing Arabic word is an English
  /// word, not `notSent` on a customer's screen.
  String t(String key, [Map<String, Object> vars = const {}]) {
    var text = _overrides[language]?[key] ??
        cnctStrings[language]?[key] ??
        cnctExtraStrings[language]?[key] ??
        _overrides['en']?[key] ??
        cnctStrings['en']?[key] ??
        cnctExtraStrings['en']?[key] ??
        '';
    for (final MapEntry(:key, :value) in vars.entries) {
      text = text.replaceAll('{$key}', '$value');
    }
    return text;
  }

  /// A date format in this language with **Latin digits**, as Gulf apps write them
  /// (`ar-u-nu-latn`): "2:30 م" rather than "٢:٣٠ م".
  DateFormat _format(DateFormat Function(String locale) make) {
    final format = make(language);
    if (isArabic) format.useNativeDigits = false;
    return format;
  }

  /// "2:30 PM", "2:30 م".
  String clock(DateTime when) => _format(DateFormat.jm).format(when.toLocal());

  /// "Today", "Yesterday", or "8 September".
  String day(DateTime when) {
    final date = when.toLocal();
    final today = _now();
    if (_sameDay(date, today)) return t('today');
    if (_sameDay(date, today.subtract(const Duration(days: 1)))) return t('yesterday');
    return _format((locale) => DateFormat('d MMMM', locale)).format(date);
  }

  /// "Conversation ended today", "… yesterday", "… on 8 September".
  String endedWhen(DateTime when) {
    final label = day(when);
    final word = label == t('today')
        ? t('endedToday')
        : label == t('yesterday')
            ? t('endedYesterday')
            : t('endedOn', {'date': label});
    return t('ended', {'when': word});
  }

  /// "Sunday", for "the team is back Sunday at 9:00".
  String weekday(DateTime when) => _format(DateFormat.EEEE).format(when.toLocal());

  /// "220 KB", "1.2 MB" — Latin digits and the Latin units in both languages, as file sizes are
  /// written on Gulf phones.
  ///
  /// Isolated left to right, so in an Arabic line the number and its unit stay one piece rather
  /// than being split around the words beside them.
  String size(int? bytes) {
    if (bytes == null || bytes < 0) return '';
    final String text;
    if (bytes < 1024) {
      text = '$bytes B';
    } else if (bytes < 1024 * 1024) {
      text = '${(bytes / 1024).round()} KB';
    } else {
      final megabytes = bytes / (1024 * 1024);
      text = '${megabytes >= 10 ? megabytes.round() : megabytes.toStringAsFixed(1)} MB';
    }
    return '\u2066$text\u2069';
  }

  /// **What the visitor can expect, said honestly** — the hosted widget's sentence. Closed: when the
  /// team is back, in the visitor's own clock, and whether the assistant can help meanwhile. Open:
  /// how fast replies have really come. Without a measurement it promises nothing.
  String availability(CnctChatAvailability? now) {
    if (now == null) return t('replyUnknown');
    final opensAt = now.opensAt;
    if (now.open == false && opensAt != null) {
      final back = _backAt(opensAt);
      return now.assistant ? t('backAssistant', {'back': back}) : back;
    }
    final minutes = now.replyMinutes;
    if (minutes == null) return now.assistant ? t('assistantNow') : t('replyUnknown');
    if (minutes < 1) return now.assistant ? t('assistantNow') : t('replyUnder1');
    if (minutes <= 5) return t('replyFew');
    if (minutes <= 20) return t('reply20');
    if (minutes <= 60) return t('replyHour');
    if (minutes <= 240) return t('replyHours');
    return t('replyDay');
  }

  String _backAt(DateTime when) {
    final time = clock(when);
    final today = _now();
    if (_sameDay(when.toLocal(), today)) return t('backToday', {'time': time});
    if (_sameDay(when.toLocal(), today.add(const Duration(days: 1)))) {
      return t('backTomorrow', {'time': time});
    }
    return t('backOn', {'day': weekday(when), 'time': time});
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
