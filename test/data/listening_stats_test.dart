import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/listening_log.dart';
import 'package:music_database_app/src/data/listening_stats.dart';
import 'package:music_database_app/src/data/song_catalog.dart';

var _uid = 0;

Listen _listen(
  String title, {
  int seconds = 200,
  String artist = 'Kino',
  String? album,
  int? songId,
  int hour = 12,
  ListenSource source = ListenSource.phone,
}) => Listen(
  uid: '${_uid++}',
  startedAt: DateTime(2026, 10, 16, hour),
  title: title,
  artist: artist,
  album: album,
  songId: songId,
  source: source,
  listened: Duration(seconds: seconds),
);

void main() {
  final kukushka = CatalogSong(
    id: 2,
    title: 'Kukushka',
    artistLabel: 'Кино',
    artistLatin: 'Kino',
    album: 'Чёрный альбом',
    year: 1990,
    language: 'Russian',
    origins: ['Russia - Leningrad'],
  );

  test('plays count from 30 s, every second counts towards the time', () {
    final stats = ListeningStats.of([
      _listen('A', seconds: 200),
      _listen('A', seconds: 29),
      _listen('B', seconds: 30),
    ]);
    expect(stats.plays, 2);
    expect(stats.listened, const Duration(seconds: 259));
    expect(
      [for (final s in stats.songs) (s.title, s.plays)],
      [('A', 1), ('B', 1)],
    );
    // A tie in plays goes to the longer listened.
    expect(stats.songs.first.listened, const Duration(seconds: 229));
  });

  test('a merged song is counted once, with music.db\'s names', () {
    final stats = ListeningStats.of([
      _listen('Kukushka (old)', songId: 1),
      _listen('Kukushka', songId: 2),
      _listen('Skip', seconds: 0),
    ], song: (id) => id == 1 || id == 2 ? kukushka : null);
    expect(stats.songs, hasLength(1));
    final song = stats.songs.single;
    expect(
      (song.title, song.artist, song.songId, song.plays),
      ('Kukushka', 'Кино', 2, 2),
    );
    expect(stats.artists.single.name, 'Кино');
    expect(stats.artists.single.latin, 'Kino');
    expect(stats.albums.single.name, 'Чёрный альбом');
    expect(stats.decades.single.name, 'Lata 90.');
    expect(stats.languages.single.name, 'Russian');
    expect(stats.countries.single.name, 'Russia');
  });

  test('artists are split from the label; Singles is not an album', () {
    final stats = ListeningStats.of([
      _listen('X', artist: 'Mata feat. Young Leosia', album: 'Singles'),
      _listen('Y', artist: 'Mata', album: '100 dni do matury'),
      _listen('Z', artist: 'Mata', album: '100 dni do matury'),
    ]);
    expect(
      [for (final a in stats.artists) (a.name, a.plays)],
      [('Mata', 3), ('Young Leosia', 1)],
    );
    expect(
      [for (final a in stats.albums) (a.name, a.plays, a.detail)],
      [('100 dni do matury', 2, 'Mata')],
    );
    expect(stats.artists.first.song?.title, 'X');
  });

  test('hours and sources sum the listened time', () {
    final stats = ListeningStats.of([
      _listen('A', hour: 7, seconds: 60, source: ListenSource.youtube),
      _listen('B', hour: 7, seconds: 60),
      _listen('C', hour: 22, seconds: 30, source: ListenSource.server),
    ]);
    expect(stats.hours[7], const Duration(minutes: 2));
    expect(stats.hours[22], const Duration(seconds: 30));
    expect(stats.sources, {
      ListenSource.youtube: const Duration(minutes: 1),
      ListenSource.phone: const Duration(minutes: 1),
      ListenSource.server: const Duration(seconds: 30),
    });
    expect(stats.firstPlay, DateTime(2026, 10, 16, 7));
  });

  test('periods start back from now', () {
    final now = DateTime(2026, 10, 16, 12);
    expect(StatsPeriod.weeks4.from(now), DateTime(2026, 9, 18, 12));
    expect(StatsPeriod.months6.from(now), DateTime(2026, 4, 16, 12));
    expect(StatsPeriod.year.from(now), DateTime(2025, 10, 16, 12));
    expect(StatsPeriod.all.from(now), isNull);
  });
}
