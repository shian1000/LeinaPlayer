import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/soundtrack_works.dart';

void main() {
  test('reads the work a name ending in a soundtrack word is about, '
      'as MusicDatabase does', () {
    // MusicDatabase's tests/test_soundtrack_albums.py, test_soundtrack_work.
    const cases = <String?, String?>{
      'Tekken 5 OST': 'Tekken 5',
      'Tekken 5 Soundtrack': 'Tekken 5',
      'Cyberpunk: Edgerunners [OST]': 'Cyberpunk: Edgerunners',
      'Final Fantasy VII O.S.T.': 'Final Fantasy VII',
      'Fallout 4 (Original Game Soundtrack)': 'Fallout 4',
      'SILENT HILL 3 ORIGINAL SOUNDTRACKS': 'SILENT HILL 3',
      'Hotline Miami - Official Soundtrack': 'Hotline Miami',
      'Charmed: The Soundtrack': 'Charmed',
      'Call Me By Your Name (Original Motion Picture Soundtrack)':
          'Call Me By Your Name',
      // Not at the end: what follows tells apart several albums of one work.
      'Noir OST I': null,
      'Cyberpunk Edgerunners Soundtrack Vol.1 (Ep1+2)': null,
      // Nothing left to name a work.
      'Soundtrack': null,
      'Original Soundtrack': null,
      // Not soundtrack words.
      'Ghost': null,
      'O.S.T.R.': null,
      null: null,
    };
    for (final MapEntry(key: name, value: work) in cases.entries) {
      expect(soundtrackWork(name), work, reason: '$name');
    }
  });

  test('a work is named by whole words only', () {
    expect(
      namesWork("Anna Tsuchiya Inspi' NANA (Black Stones)", {'nana'}),
      isTrue,
    );
    expect(namesWork('Nana OST', {'nana'}), isTrue);
    expect(namesWork('Nanami', {'nana'}), isFalse);
    expect(namesWork(null, {'nana'}), isFalse);
  });

  test('a listed work is one as a whole name, with its other spellings', () {
    const works = SoundtrackWorks({'nana': 'Nana', 'nana anime': 'Nana'});
    expect(works.creditedWork('NANA'), 'Nana');
    expect(works.creditedWork('Nana Anime'), 'Nana');
    expect(works.creditedWork('Nana Mouskouri'), isNull);
    expect(works.creditedWork('Tekken 5 OST'), 'Tekken 5');
    expect(works.spellingsOf('Nana'), {'nana', 'nana anime'});
    expect(works.spellingsOf('Tekken 5'), {'tekken 5'});
  });
}
