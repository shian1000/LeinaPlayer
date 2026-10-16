import 'album_covers.dart';
import 'latin_names.dart';
import 'listening_log.dart';
import 'song_catalog.dart';
import 'text_normalizer.dart';

/// The time spans Statystyki słuchania sums up, like Spotify's: rolling, ending now.
enum StatsPeriod {
  weeks4('4 tygodnie'),
  months6('6 miesięcy'),
  year('Rok'),
  all('Od początku');

  const StatsPeriod(this.label);

  final String label;

  /// Where the span starts; `null`: every play.
  DateTime? from(DateTime now) => switch (this) {
    weeks4 => now.subtract(const Duration(days: 28)),
    months6 => DateTime(now.year, now.month - 6, now.day, now.hour),
    year => DateTime(now.year - 1, now.month, now.day, now.hour),
    all => null,
  };
}

/// One song of [ListeningStats.songs]: the names as music.db has them now (else as the phone
/// showed them when it played), how often and how long it was heard.
class StatsSong {
  StatsSong({
    required this.title,
    required this.artist,
    this.album,
    this.songId,
    this.youtubeVideoId,
    this.spotifyTrackId,
  });

  final String title;
  final String artist;
  final String? album;

  /// music.db's `songs.id` today (after any merge).
  final int? songId;
  final String? youtubeVideoId;
  final String? spotifyTrackId;
  int plays = 0;
  Duration listened = Duration.zero;
}

/// An artist, album, decade, language, country or source of [ListeningStats]: how often and how
/// long it was heard.
class StatsEntry {
  StatsEntry(this.name, {this.latin, this.detail});

  final String name;

  /// The Latin form of [name] (an artist's, from music.db) — shown with the setting on.
  final String? latin;

  /// What else says which one it is: an album's artist.
  final String? detail;

  /// Its most played song (for a cover).
  StatsSong? song;
  int plays = 0;
  Duration listened = Duration.zero;
}

/// The listening stats of some plays (Ja › Statystyki słuchania): totals and rankings. Ranked
/// by plays, ties by listened time — like Spotify, which counts a play from [playThreshold].
/// Every second heard counts towards the minutes, a play only from the threshold on.
class ListeningStats {
  ListeningStats._();

  static const playThreshold = Duration(seconds: 30);

  Duration listened = Duration.zero;
  int plays = 0;

  /// The first play counted (the stats start with the version that records them).
  DateTime? firstPlay;

  /// Every song played, most played first; likewise the lists below.
  late final List<StatsSong> songs;
  late final List<StatsEntry> artists;
  late final List<StatsEntry> albums;
  late final List<StatsEntry> decades;
  late final List<StatsEntry> languages;
  late final List<StatsEntry> countries;

  /// The share of each source: phone files, MusicDatabase's server, YouTube.
  late final Map<ListenSource, Duration> sources;

  /// Listened time by the hour of day it started (24 entries).
  final hours = List<Duration>.filled(24, Duration.zero);

  bool get isEmpty => listened == Duration.zero;

  /// [listens] summed up; [song] finds a music.db song by any id it ever had
  /// ([SongCatalog.current]), so a merged song is counted once and shown as it is now.
  factory ListeningStats.of(
    Iterable<Listen> listens, {
    CatalogSong? Function(int id)? song,
  }) {
    final stats = ListeningStats._();
    final songs = <String, StatsSong>{};
    final artists = <String, StatsEntry>{};
    final albums = <String, StatsEntry>{};
    final decades = <String, StatsEntry>{};
    final languages = <String, StatsEntry>{};
    final countries = <String, StatsEntry>{};
    final sources = <ListenSource, Duration>{};

    void count(
      Map<String, StatsEntry> into,
      String key,
      StatsEntry Function() entry,
      bool played,
      Duration listened,
      StatsSong song,
    ) {
      final e = into[key] ??= entry();
      e.listened += listened;
      if (played) e.plays++;
      // Counts only grow, so the song that last overtook the others is the most played.
      if (e.song == null || song.plays > e.song!.plays) e.song = song;
    }

    for (final listen in listens) {
      if (listen.listened <= Duration.zero) continue;
      final heard = listen.listened;
      final played = heard >= playThreshold;
      stats.listened += heard;
      if (played) stats.plays++;
      final first = stats.firstPlay;
      if (first == null || listen.startedAt.isBefore(first)) {
        stats.firstPlay = listen.startedAt;
      }
      stats.hours[listen.startedAt.hour] += heard;
      sources.update(listen.source, (d) => d + heard, ifAbsent: () => heard);

      final id = IdentifiedListen.of(listen, song);
      final known = id.known;
      final album = id.album;
      final s = songs[id.key] ??= id.newSong();
      s.listened += heard;
      if (played) s.plays++;

      final names = id.artists;
      for (final (i, name) in names.indexed) {
        count(
          artists,
          IdentifiedListen.artistKey(name),
          () => StatsEntry(name, latin: id.artistLatin[i]),
          played,
          heard,
          s,
        );
      }
      if (CoverRequest.realAlbum(album) case final a?) {
        count(
          albums,
          normalizeForSearch(a),
          () => StatsEntry(
            a,
            latin: known?.albumLatin,
            detail: names.firstOrNull,
          ),
          played,
          heard,
          s,
        );
      }
      final year = known?.year;
      // A year still to come is a mistake in music.db, not a decade.
      if (year != null && year > 0 && year <= DateTime.now().year) {
        final decade = year ~/ 10 * 10;
        count(
          decades,
          '$decade',
          () => StatsEntry(decadeName(decade)),
          played,
          heard,
          s,
        );
      }
      // "Unknown" is MusicDatabase's placeholder, not a language.
      if (known?.language case final language? when language != 'Unknown') {
        count(
          languages,
          language,
          () => StatsEntry(language),
          played,
          heard,
          s,
        );
      }
      for (final country in known?.countries ?? const <String>[]) {
        count(countries, country, () => StatsEntry(country), played, heard, s);
      }
    }

    int byPlays(int playsA, Duration a, int playsB, Duration b) =>
        playsA != playsB ? playsB - playsA : b.compareTo(a);
    List<StatsEntry> ranked(Map<String, StatsEntry> entries) =>
        entries.values.toList()
          ..sort((a, b) => byPlays(a.plays, a.listened, b.plays, b.listened));
    stats.songs = songs.values.toList()
      ..sort((a, b) => byPlays(a.plays, a.listened, b.plays, b.listened));
    stats.artists = ranked(artists);
    stats.albums = ranked(albums);
    // Decades, languages and countries by time: a share of the listening.
    List<StatsEntry> byTime(Map<String, StatsEntry> entries) =>
        entries.values.toList()
          ..sort((a, b) => b.listened.compareTo(a.listened));
    stats.decades = byTime(decades);
    stats.languages = byTime(languages);
    stats.countries = byTime(countries);
    stats.sources = sources;
    return stats;
  }

  /// "Lata 90." / "2010–2019", as Wyszukaj's "Przeglądaj" names decades.
  static String decadeName(int decade) =>
      decade < 2000 ? 'Lata ${decade % 100}.' : '$decade–${decade + 9}';
}

/// What song and artists a play was of, the same way for the stats and the highlights: music.db's
/// song (after merges) with its names when it has it, else what the phone showed.
class IdentifiedListen {
  IdentifiedListen._({
    required this.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.known,
    required this.listen,
    required this.artists,
    required this.artistLatin,
  });

  factory IdentifiedListen.of(
    Listen listen,
    CatalogSong? Function(int id)? song,
  ) {
    final known = listen.songId == null ? null : song?.call(listen.songId!);
    final title = known?.title ?? listen.title;
    final artist = known?.artistLabel ?? listen.artist ?? 'Nieznany wykonawca';
    final names = artistNamesOf(artist);
    final latinNames = artistNamesOf(known?.artistLatin ?? '');
    return IdentifiedListen._(
      key: known != null
          ? 'db:${known.id}'
          : listen.youtubeVideoId != null
          ? 'yt:${listen.youtubeVideoId}'
          : 'name:${normalizeForSearch(artist)}|${normalizeForSearch(title)}',
      title: title,
      artist: artist,
      album: known != null ? known.album : listen.album,
      known: known,
      listen: listen,
      artists: names,
      artistLatin: [
        for (final (i, name) in names.indexed)
          latinNames.length == names.length
              ? latinFormOf(name, latinNames[i])
              : null,
      ],
    );
  }

  /// The same song for every play of it.
  final String key;
  final String title;
  final String artist;
  final String? album;
  final CatalogSong? known;
  final Listen listen;

  /// The artists in [artist] ("A feat. B" → A, B), as "Przejdź do wykonawców" lists them.
  final List<String> artists;

  /// The Latin form of each of [artists], if music.db has one.
  final List<String?> artistLatin;

  /// The same artist for every play of theirs.
  static String artistKey(String name) => normalizeForSearch(name);

  StatsSong newSong() => StatsSong(
    title: title,
    artist: artist,
    album: album,
    songId: known?.id,
    youtubeVideoId: listen.youtubeVideoId,
    spotifyTrackId: listen.spotifyTrackId,
  );
}
