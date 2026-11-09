import 'package:cnct_flutter_ui/src/bidi.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a piece of text takes its direction from its first strong character', () {
    test('Arabic reads right to left, whatever the interface', () {
      expect(firstStrongDirection('هل تفتحون يوم الجمعة؟'), TextDirection.rtl);
      expect(firstStrongDirection('  2 «مرحبا» hello'), TextDirection.rtl);
    });

    test('Latin reads left to right, even in an Arabic chat', () {
      expect(firstStrongDirection('Do you open on Fridays?'), TextDirection.ltr);
      expect(firstStrongDirection('+973 call مرحبا'), TextDirection.ltr);
      expect(firstStrongDirection('Ça va'), TextDirection.ltr);
    });

    test('digits, punctuation and emoji alone say nothing', () {
      expect(firstStrongDirection('+973 3311 2233'), isNull);
      expect(firstStrongDirection('👍 !!'), isNull);
      expect(firstStrongDirection(''), isNull);
    });
  });

  group('phone numbers, emails and links stay left to right', () {
    const lri = '\u2066';
    const pdi = '\u2069';

    test('a phone number in an Arabic line is isolated', () {
      expect(
        isolateLeftToRight('اتصلوا بي على +973 3311 2233 من فضلك'),
        'اتصلوا بي على $lri+973 3311 2233$pdi من فضلك',
      );
    });

    test('so are emails and links', () {
      expect(isolateLeftToRight('راسلنا على help@example.com'),
          'راسلنا على ${lri}help@example.com$pdi');
      expect(isolateLeftToRight('www.example.com/menu'), '${lri}www.example.com/menu$pdi');
    });

    test('but short numbers are left alone', () {
      expect(isolateLeftToRight('من 2 ظهرًا حتى 10 مساءً'), 'من 2 ظهرًا حتى 10 مساءً');
      expect(isolateLeftToRight('ticket #1042'), 'ticket #1042');
    });

    testWidgets('and the number is drawn in the order it was typed', (tester) async {
      await tester.runAsync(loadTestFonts);
      const style = TextStyle(fontFamily: 'Roboto', fontFamilyFallback: ['Noto Sans Arabic']);
      double left(String text, String needle) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.rtl,
        )..layout();
        final at = text.indexOf(needle);
        return painter
            .getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + needle.length))
            .first
            .left;
      }

      const line = 'اتصلوا بي على +973 3311 2233 من فضلك';
      final isolated = isolateLeftToRight(line);
      // Isolated: +973 is left of 3311, which is left of 2233 — as typed.
      expect(left(isolated, '+973'), lessThan(left(isolated, '3311')));
      expect(left(isolated, '3311'), lessThan(left(isolated, '2233')));
      // Not isolated, the groups come out reversed — the bug this exists for.
      expect(left(line, '+973'), greaterThan(left(line, '2233')));
    });
  });

  group('links', () {
    test('an address is a link, and the punctuation after it is not part of it', () {
      final pieces = linkPieces('Pay here: https://pay.example.com/i/42. Thanks');
      expect(pieces.map((piece) => piece.text),
          ['Pay here: ', 'https://pay.example.com/i/42', '. Thanks']);
      expect(pieces[1].href, Uri.parse('https://pay.example.com/i/42'));
    });

    test('www. becomes https, and the Arabic comma ends an address', () {
      final pieces = linkPieces('الرابط www.example.com، شكرًا');
      expect(pieces[1].text, 'www.example.com');
      expect(pieces[1].href, Uri.parse('https://www.example.com'));
    });

    test('only http and https are ever produced', () {
      expect(linkPieces('javascript:alert(1)').where((piece) => piece.href != null), isEmpty);
    });
  });
}
