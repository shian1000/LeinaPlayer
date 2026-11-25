import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/language_codes.dart';

void main() {
  test('codes are shown by their names, an unknown code as it is', () {
    expect(languageNames('pol'), 'Polski');
    expect(languageNames('eng / jpn'), 'Angielski / Japoński');
    expect(languageNames('qpd'), 'Podlaski');
    expect(languageNames('xyz'), 'xyz');
  });

  test('old English names are read as codes', () {
    expect(languageValue('Japanese / English'), 'jpn / eng');
    expect(languageValue('Instrumental'), noWordsLanguage);
    expect(languageValue('No Language'), noWordsLanguage);
    expect(languageValue('Unknown'), unknownLanguage);
    expect(languageValue('Attic Greek'), 'grc');
    expect(languageValue('English (Jamaican)'), 'jam');
    expect(languageValue('  '), isNull);
    expect(languageValue(null), isNull);
  });

  test('"und" is no language to show', () {
    expect(isKnownLanguage('und'), isFalse);
    expect(isKnownLanguage(null), isFalse);
    expect(isKnownLanguage('und / pol'), isTrue);
  });

  test('a typed name in any app language becomes a code', () {
    expect(languageValueOfTyped('Polski / japonski'), 'pol / jpn');
    expect(languageValueOfTyped('English'), 'eng');
    expect(languageValueOfTyped('eng'), 'eng');
    expect(languageValueOfTyped('Klingon'), 'Klingon');
  });

  test('search text holds the code and every app language\'s name', () {
    final text = languageSearchText('jpn');
    expect(text, contains('jpn'));
    expect(text, contains('Japoński'));
    expect(text, contains('Japanese'));
    expect(languageSearchText('und'), isEmpty);
  });
}
