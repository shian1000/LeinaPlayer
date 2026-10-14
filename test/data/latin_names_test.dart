import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/latin_names.dart';

void main() {
  test(
    'another alphabet: Cyrillic, kana, Hangul, Greek — not Polish or fullwidth',
    () {
      for (final text in ['Кино', 'ゆらゆら', '벚꽃 엔딩', 'Ματαδώ', 'Family бізнес']) {
        expect(hasNonLatinLetters(text), isTrue, reason: text);
      }
      for (final text in ['Zażółć gęślą jaźń', 'ＨＥＡＲＴＢＲＯＫＥＮ', '', '2 + 2']) {
        expect(hasNonLatinLetters(text), isFalse, reason: text);
      }
    },
  );

  test('a Latin form only next to a name that needs one, and saying something else', () {
    expect(latinFormOf('Кино', ' Kino '), 'Kino');
    expect(latinFormOf('Kino', 'Kino 2'), isNull);
    expect(latinFormOf('Кино', ''), isNull);
    expect(latinFormOf('Кино', 'Кино'), isNull);
    expect(latinFormOf(null, 'Kino'), isNull);
  });

  test('the first synonym written only in Latin letters', () {
    expect(latinSynonym('Бумбокс, familyboombox, Bumboks'), 'familyboombox');
    expect(latinSynonym('ポルカドット, POLKADOT STINGRAY'), 'POLKADOT STINGRAY');
    expect(latinSynonym('Кино, 123'), isNull);
    expect(latinSynonym(null), isNull);
  });

  test('shown with the Latin form in brackets', () {
    expect(withLatin('Кино', 'Kino'), 'Кино (Kino)');
    expect(withLatin('Кино', null), 'Кино');
  });
}
