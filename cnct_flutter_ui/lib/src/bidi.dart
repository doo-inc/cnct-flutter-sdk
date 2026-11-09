import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// The direction a piece of text reads in, from its first strong character — `dir="auto"` on the
/// web, `TextDirection.Content` on Android. Null when there is no strong character at all (digits,
/// punctuation, emoji), in which case the surrounding direction applies.
///
/// **Whatever the interface language**: an Arabic message in an English chat reads right to left,
/// and an English one in an Arabic chat left to right.
TextDirection? firstStrongDirection(String text) {
  for (final rune in text.runes) {
    if (_isRtl(rune)) return TextDirection.rtl;
    if (_isLtr(rune)) return TextDirection.ltr;
  }
  return null;
}

bool _isRtl(int c) =>
    (c >= 0x0590 && c <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic…
    (c >= 0xFB1D && c <= 0xFDFF) || // Hebrew and Arabic presentation forms A
    (c >= 0xFE70 && c <= 0xFEFF) || // Arabic presentation forms B
    (c >= 0x10800 && c <= 0x10FFF) ||
    (c >= 0x1E800 && c <= 0x1EFFF);

/// Letters of left-to-right scripts. Digits, punctuation, symbols, marks and emoji are not strong
/// and are skipped, as the Unicode bidi algorithm skips them.
bool _isLtr(int c) {
  if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) return true;
  if (c < 0xC0) return c == 0xAA || c == 0xB5 || c == 0xBA;
  if (c == 0xD7 || c == 0xF7) return false;
  if (c >= 0x0300 && c <= 0x036F) return false; // combining marks
  if (c >= 0x2000 && c <= 0x2BFF) return false; // punctuation, symbols, arrows, shapes, dingbats
  if (c >= 0x2E00 && c <= 0x2E7F) return false;
  if (c >= 0x3000 && c <= 0x303F) return false; // CJK punctuation
  if (c >= 0xFE00 && c <= 0xFE0F) return false; // variation selectors
  if (c >= 0xFF00 && c <= 0xFF20) return false;
  if (c >= 0x1F000 && c <= 0x1FAFF) return false; // emoji and pictographs
  if (c >= 0xE0000) return false;
  return true;
}

/// Left-to-right isolate and pop: wrapped around a run, they keep it in its own order whatever the
/// line around it does.
const _lri = '\u2066';
const _pdi = '\u2069';

/// **Phone numbers, emails and links stay left to right inside Arabic text.**
///
/// Without this, "+973 3311 2233" inside an Arabic sentence is drawn "2233 3311 973+": each group of
/// digits keeps its order, but the spaces between them take the sentence's direction, so the groups
/// come out reversed. Wrapping the run in a left-to-right isolate keeps it as typed.
final _ltrRun = RegExp(
  r'(?:[Hh][Tt][Tt][Pp][Ss]?://|\b[Ww][Ww][Ww]\.)\S+'
  r'|[\w.+-]+@[\w-]+(?:\.[\w-]+)+'
  r'|\+?\(?\d[\d\s\-().]*\d',
);

/// [text] with every phone number, email and link isolated left to right. A run of digits is only
/// treated as a phone number with seven digits or more, so "2pm to 10pm" and "#1042" are left alone.
String isolateLeftToRight(String text) {
  return text.replaceAllMapped(_ltrRun, (match) {
    final run = match[0]!;
    final addressOrEmail =
        run.contains('@') || RegExp('^(?:https?://|www\\.)', caseSensitive: false).hasMatch(run);
    if (!addressOrEmail && run.replaceAll(RegExp(r'\D'), '').length < 7) return run;
    return '$_lri$run$_pdi';
  });
}

/// [text] without the isolate marks, for a screen reader, which has no direction to keep.
String withoutIsolates(String text) => text.replaceAll(RegExp('[\u2066-\u2069]'), '');

/// **A link in a message is a link** — the hosted widget's pattern, kept the same so that a link is
/// found in the same place on every surface.
///
/// The address shown is the address opened, character for character, and only `http`/`https` are
/// ever produced, so a stranger's message cannot dress one place up as another. Starts at
/// `http://`, `https://` or `www.` in any case; ends before whitespace and before the punctuation a
/// sentence puts after it — a full stop, the Arabic comma, a closing bracket the address did not
/// open.
final webAddress = RegExp(
  r'''(?:[Hh][Tt][Tt][Pp][Ss]?:\/\/|\b[Ww][Ww][Ww]\.)(?:[^\s()<>"]|\([^\s()<>"]*\))*(?:[^\s()<>".,:;!?'’”»\]}*_~،؛؟…]|\([^\s()<>"]*\))''',
);

/// One piece of a line: words, or a link with the address it opens.
class TextPiece {
  const TextPiece(this.text, [this.href]);
  final String text;
  final Uri? href;
}

/// A line as words and links, in order.
List<TextPiece> linkPieces(String line) {
  final pieces = <TextPiece>[];
  var cursor = 0;
  for (final match in webAddress.allMatches(line)) {
    if (match.start > cursor) pieces.add(TextPiece(line.substring(cursor, match.start)));
    final text = match[0]!;
    final href = Uri.tryParse(
        RegExp('^https?://', caseSensitive: false).hasMatch(text) ? text : 'https://$text');
    pieces.add(TextPiece(text, href));
    cursor = match.end;
  }
  if (cursor < line.length) pieces.add(TextPiece(line.substring(cursor)));
  return pieces;
}

/// User text drawn the way the spec asks: its own direction from its first strong character,
/// phone numbers and links kept left to right, and links tappable.
class ChatText extends StatefulWidget {
  const ChatText(
    this.text, {
    super.key,
    required this.style,
    this.linkColor,
    this.onOpenLink,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final Color? linkColor;
  final ValueChanged<Uri>? onOpenLink;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;

  @override
  State<ChatText> createState() => _ChatTextState();
}

class _ChatTextState extends State<ChatText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final direction = firstStrongDirection(widget.text) ?? Directionality.of(context);
    final spans = <InlineSpan>[];
    for (final piece in linkPieces(widget.text)) {
      if (piece.href == null || widget.onOpenLink == null) {
        spans.add(TextSpan(text: isolateLeftToRight(piece.text)));
        continue;
      }
      final href = piece.href!;
      final recognizer = TapGestureRecognizer()..onTap = () => widget.onOpenLink!(href);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: '$_lri${piece.text}$_pdi',
        recognizer: recognizer,
        style: TextStyle(
          color: widget.linkColor,
          decoration: TextDecoration.underline,
          decorationColor: widget.linkColor ?? widget.style.color,
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: spans, style: widget.style),
      textDirection: direction,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
