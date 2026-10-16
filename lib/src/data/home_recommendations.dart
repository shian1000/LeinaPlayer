import 'listening_log.dart';
import 'listening_stats.dart';
import 'song_catalog.dart';

/// Home's recommendation rows (Dostosuj stronę główną › Rekomendacje), worked out on the phone
/// from the listening stats and music.db — MusicDatabase has no recommendations of its own.
class HomeRecommendations {
  HomeRecommendations._(this.stats, this.forgotten, this.genres);

  /// [listens] are every play, oldest first; [song] finds a music.db song by id (after
  /// merges).
  factory HomeRecommendations.of(
    List<Listen> listens, {
    required CatalogSong? Function(int id) song,
    DateTime? now,
  }) {
    final stats = ListeningStats.of(listens, song: song);
    return HomeRecommendations._(
      stats,
      _forgotten(listens, stats, song, now ?? DateTime.now()),
      _genres(stats, song),
    );
  }

  /// How long a song not heard counts as forgotten.
  static const forgottenAfter = Duration(days: 60);

  /// Over everything: the artists and albums most listened to.
  final ListeningStats stats;

  /// "Zapomniane": songs heard at least twice, but not for [forgottenAfter] — the most played
  /// first.
  final List<StatsSong> forgotten;

  /// "Twoje gatunki": the genres (`songs.genre`) of what was heard, the most played first.
  final List<String> genres;

  static List<StatsSong> _forgotten(
    List<Listen> listens,
    ListeningStats stats,
    CatalogSong? Function(int id) song,
    DateTime now,
  ) {
    final last = <String, DateTime>{};
    for (final listen in listens) {
      if (listen.listened < ListeningStats.playThreshold) continue;
      final id = listen.songId;
      last[_key(
            id == null ? null : song(id)?.id ?? id,
            listen.title,
            listen.artist,
          )] =
          listen.startedAt;
    }
    final before = now.subtract(forgottenAfter);
    return [
      for (final song in stats.songs)
        if (song.plays >= 2 &&
            (last[_key(song.songId, song.title, song.artist)] ?? DateTime(0))
                .isBefore(before))
          song,
    ];
  }

  // A song kept by music.db's id when it has one, else by its names (as ListeningStats does).
  static String _key(int? songId, String title, String? artist) =>
      songId != null ? '#$songId' : '$title\u0000${artist ?? ''}';

  static List<String> _genres(
    ListeningStats stats,
    CatalogSong? Function(int id) song,
  ) {
    final plays = <String, int>{};
    for (final heard in stats.songs) {
      final id = heard.songId;
      if (id == null || heard.plays == 0) continue;
      for (final genre in song(id)?.genres ?? const <String>[]) {
        plays.update(
          genre,
          (n) => n + heard.plays,
          ifAbsent: () => heard.plays,
        );
      }
    }
    return (plays.entries.toList()..sort((a, b) => b.value - a.value))
        .map((e) => e.key)
        .toList();
  }
}
