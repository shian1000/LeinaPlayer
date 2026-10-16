import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/song_radio.dart';

CatalogSong _song(
  int id,
  String artist, {
  int? year,
  String? language,
  List<String> origins = const [],
  String? genre,
}) => CatalogSong(
  id: id,
  title: 'Song $id',
  artistLabel: artist,
  year: year,
  language: language,
  origins: origins,
  genre: genre,
);

void main() {
  test('the seed first, then the songs most like it; unlike ones left out', () {
    final seed = _song(1, 'Kino', year: 1986, language: 'Russian');
    final songs = [
      seed,
      _song(2, 'Kino', year: 1988, language: 'Russian'),
      _song(3, 'Akvarium', year: 1987, language: 'Russian'),
      _song(4, 'ABBA', year: 1976, language: 'English'),
      _song(5, 'Nirvana', year: 1991, language: 'English'),
    ];
    final radio = songRadio(seed, songs).map((s) => s.id).toList();
    expect(radio.first, 1);
    expect(radio, containsAllInOrder([1, 2, 3]));
    expect(radio, isNot(contains(4)));
    expect(radio, isNot(contains(5)));
  });

  test('shared moods count; one artist takes only so many places', () {
    final seed = _song(1, 'A');
    final songs = [
      seed,
      for (var id = 2; id <= 6; id++) _song(id, 'A'),
      _song(7, 'B'),
    ];
    final radio = songRadio(
      seed,
      songs,
      moodsOf: (id) => id == 1 || id == 7 ? {'g1'} : const {},
      perArtist: 2,
    ).map((s) => s.id).toList();
    expect(radio, contains(7));
    expect(radio.where((id) => id >= 2 && id <= 6), hasLength(2));
  });

  test('the same seed gives the same radio', () {
    final songs = [
      for (var id = 1; id <= 40; id++) _song(id, 'A', year: 2000 + id % 5),
    ];
    expect(
      songRadio(songs.first, songs).map((s) => s.id),
      songRadio(songs.first, songs).map((s) => s.id),
    );
  });

  test('genres: the same one counts most, a related one ("indie pop" – "pop") '
      'less, "… and …" alone not at all', () {
    final seed = _song(1, 'A', genre: 'indie pop, synth-pop');
    final songs = [
      seed,
      _song(2, 'B', genre: 'Indie Pop'),
      _song(3, 'C', genre: 'pop, indie pop'),
      _song(4, 'D', genre: 'pop'),
      _song(5, 'E', genre: 'drum and bass'),
    ];
    expect(genresOf(' indie pop , synth-pop,,indie pop'), [
      'indie pop',
      'synth-pop',
    ]);
    final radio = songRadio(seed, songs).map((s) => s.id).toList();
    expect(radio, containsAll([2, 3]));
    expect(radio, isNot(contains(5)));
    // One related genre alone is 1 point, under the radio's threshold of 2.
    expect(radio, isNot(contains(4)));
  });
}
