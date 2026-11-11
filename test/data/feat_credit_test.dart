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

  test('no credit, or nothing but one: null', () {
    expect(withoutFeatCredits('Dziwny jest ten świat (Bonus track)'), isNull);
    expect(withoutFeatCredits('Die With a Smile'), isNull);
    expect(withoutFeatCredits('Defeat'), isNull);
    expect(withoutFeatCredits('(feat. X)'), isNull);
  });
}
