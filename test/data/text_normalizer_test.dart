import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/text_normalizer.dart';

void main() {
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
