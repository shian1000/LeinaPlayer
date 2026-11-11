import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/feat_credit.dart';

void main() {
  test('drops featured-artist credits, bracketed or not', () {
    expect(
      withoutFeatCredits('Tamagotchi feat. Dawid Podsiadło'),
      'Tamagotchi',
    );
    expect(withoutFeatCredits('Выше головы (feat. Тося)'), 'Выше головы');
    expect(withoutFeatCredits('Billionaire ft. Bruno Mars'), 'Billionaire');
    expect(withoutFeatCredits('Water [with Mahalia]'), 'Water');
    expect(withoutFeatCredits('Song (feat. X) (Remix)'), 'Song (Remix)');
    expect(withoutFeatCredits('Song feat. X (Remix)'), 'Song (Remix)');
  });

  test('a joined credit splits into its artists', () {
    expect(artistCreditParts('Dawid Podsiadło i Kaśka Sochacka'), [
      'Dawid Podsiadło',
      'Kaśka Sochacka',
    ]);
    expect(artistCreditParts('Sw@da x Maxim, Kizo & Bletka'), [
      'Sw@da',
      'Maxim',
      'Kizo',
      'Bletka',
    ]);
    expect(artistCreditParts('Hall AND Oates'), ['Hall', 'Oates']);
    expect(artistCreditParts('Malcolm X'), isNull);
    expect(artistCreditParts('Coldplay X BTS'), isNull);
    expect(artistCreditParts('AC/DC'), isNull);
    expect(artistCreditParts('Kaśka Sochacka'), isNull);
  });

  test('no credit, or nothing but one: null', () {
    expect(withoutFeatCredits('Dziwny jest ten świat (Bonus track)'), isNull);
    expect(withoutFeatCredits('Die With a Smile'), isNull);
    expect(withoutFeatCredits('Defeat'), isNull);
    expect(withoutFeatCredits('(feat. X)'), isNull);
  });
}
