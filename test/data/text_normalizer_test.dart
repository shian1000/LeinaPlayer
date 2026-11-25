import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/text_normalizer.dart';

void main() {
  test(
    'normalizeForSearch folds Greek and Cyrillic letters as normalize() does',
    () {
      // Values from MusicDatabase's normalize().
      expect(normalizeForSearch('Вахтёрам'), 'вахтерам');
      expect(normalizeForSearch('Летний'), 'летнии');
      expect(normalizeForSearch('Їжак Ўладзімір'), 'іжак уладзімір');
      expect(normalizeForSearch('Άλφα Ϊσος ϐήτα'), 'αλφα ισος βητα');
      expect(normalizeForSearch('Апостроф\u02b9 \u0374 ok'), 'апостроф ok');
    },
  );

  test('normalizeForSearch drops combining marks and voiced kana marks as '
      'normalize() does', () {
    // Values from MusicDatabase's normalize().
    expect(normalizeForSearch('レイディ・ブルース.'), 'レイティ フルース');
    expect(normalizeForSearch('レイテ\u3099ィ・フ\u3099ルース'), 'レイティ フルース');
    expect(normalizeForSearch('Cafe\u0301 Cz\u200bôrny'), 'cafe czorny');
    expect(normalizeForSearch('ゆらゆら'), 'ゆらゆら');
    expect(normalizeForSearch('ポップ'), 'ホッフ');
  });

  test('normalizeWithAnd reads "&" and "+" as "and"', () {
    expect(
      normalizeWithAnd('Florence + the Machine'),
      'florence and the machine',
    );
    expect(normalizeWithAnd('The Ball&Chain'), 'the ball and chain');
    expect(normalizeWithAnd('The Ball And Chain'), 'the ball and chain');
    expect(
      normalizeForSearch('Florence + the Machine'),
      'florence the machine',
    );
  });

  test('compareNames orders numbers by value', () {
    final names = [
      '10. Pidvalia',
      '2. Telefon - nowsza',
      '0. Fixed',
      '1. Z telefonu',
      'Żurawie',
      'Abba',
      '02. Zero przed',
    ]..sort(compareNames);
    expect(names, [
      '0. Fixed',
      '1. Z telefonu',
      '2. Telefon - nowsza',
      '02. Zero przed',
      '10. Pidvalia',
      'Abba',
      'Żurawie',
    ]);
  });

  test('nameResembles tells a spelling fix from another name', () {
    expect(nameResembles('Afina', 'AFINA'), isTrue);
    expect(nameResembles('Kazik Staszewski', 'Kazik Staszewsky'), isTrue);
    expect(nameResembles('Bjork', 'Björk'), isTrue);
    expect(nameResembles('Paramore', 'David Byrne'), isFalse);
    expect(nameResembles('Armia', 'Armja'), isFalse);
  });
}
