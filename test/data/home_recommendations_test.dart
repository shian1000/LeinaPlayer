import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/home_recommendations.dart';
import 'package:music_database_app/src/data/listening_log.dart';
import 'package:music_database_app/src/data/song_catalog.dart';

void main() {
  final now = DateTime(2026, 10, 16);
  final songs = {
    1: CatalogSong(
      id: 1,
      title: 'A',
      artistLabel: 'X',
      genre: 'synth-pop, pop',
    ),
    2: CatalogSong(id: 2, title: 'B', artistLabel: 'Y', genre: 'rock'),
  };
  var n = 0;
  Listen heard(int songId, DateTime at) => Listen(
    uid: 'u${n++}',
    startedAt: at,
    listened: const Duration(minutes: 3),
    title: songs[songId]!.title,
    artist: songs[songId]!.artistLabel,
    songId: songId,
    source: ListenSource.phone,
  );

  test('forgotten: heard twice or more, not for two months', () {
    final listens = [
      heard(1, DateTime(2026, 5, 1)),
      heard(1, DateTime(2026, 5, 2)),
      heard(2, DateTime(2026, 5, 1)),
      heard(2, DateTime(2026, 10, 10)),
    ];
    final recommended = HomeRecommendations.of(
      listens,
      song: (id) => songs[id],
      now: now,
    );
    expect([for (final s in recommended.forgotten) s.songId], [1]);
  });

  test('your genres: of what was heard, the most played first', () {
    final listens = [heard(2, now), heard(2, now), heard(1, now)];
    final recommended = HomeRecommendations.of(
      listens,
      song: (id) => songs[id],
      now: now,
    );
    expect(recommended.genres, ['rock', 'synth-pop', 'pop']);
  });
}
