import 'listening_log.dart';
import 'listening_stats.dart';
import 'song_catalog.dart';

enum HighlightKind {
  /// The listening of all time passed [Highlight.count] hours.
  hours,

  /// A song's [Highlight.count]th play.
  songMilestone,

  /// An artist's [Highlight.count]th play.
  artistMilestone,

  /// An artist first heard this week, [Highlight.count] plays already.
  discovery,

  /// A song played again after [Highlight.gap].
  comeback,

  /// The week's most played song, [Highlight.count] plays.
  songOfWeek,

  /// A song played [Highlight.count] times in one day.
  onRepeat,
}

/// Something worth telling about the past week's listening, like Spotify's weekly highlights in
/// its listening stats: a milestone, a discovery, a comeback.
class Highlight {
  const Highlight({
    required this.kind,
    required this.at,
    this.count = 0,
    this.song,
    this.artist,
    this.artistLatin,
    this.gap,
  });

  final HighlightKind kind;

  /// When it happened (the play that made it).
  final DateTime at;
  final int count;

  /// The song it's about; for an artist, their song that made it (for a cover).
  final StatsSong? song;
  final String? artist;
  final String? artistLatin;
  final Duration? gap;
}

/// The past week's [Highlight]s, worked out from every play (`listening_log.dart`); the rules
/// are the phone's own, after Spotify's (milestones, new discoveries, comebacks).
abstract final class ListeningHighlights {
  static const week = Duration(days: 7);
  static const songMilestones = [10, 25, 50, 100, 250, 500, 1000];
  static const artistMilestones = [25, 50, 100, 250, 500, 1000, 2500, 5000];
  static const hourMilestones = [1, 10, 24, 50, 100, 250, 500, 1000, 2500];

  /// An artist is a discovery only when the stats are older than this: in the first weeks
  /// every artist is new.
  static const discoveryHistory = Duration(days: 14);
  static const discoveryPlays = 3;
  static const comebackGap = Duration(days: 90);
  static const songOfWeekPlays = 3;
  static const onRepeatPlays = 5;

  /// At most this many of each kind about songs or artists.
  static const perKind = 3;

  /// [listens] (every play, oldest first) as highlights of the week before [now], the most
  /// telling first; [song] as for [ListeningStats.of].
  static List<Highlight> of(
    List<Listen> listens, {
    required DateTime now,
    CatalogSong? Function(int id)? song,
  }) {
    final weekStart = now.subtract(week);
    final songs = <String, StatsSong>{};
    final songPlays = <String, int>{};
    final lastPlay = <String, DateTime>{};
    final artistPlays = <String, int>{};
    final artistFirst = <String, DateTime>{};
    final artistNames = <String, (String, String?)>{};
    var total = Duration.zero;
    DateTime? firstPlay;

    Highlight? hours;
    final songMilestone = <String, Highlight>{};
    final artistMilestone = <String, Highlight>{};
    final comebacks = <String, Highlight>{};
    final weekPlays = <String, int>{};
    final weekArtistPlays = <String, int>{};
    final weekArtistSong = <String, StatsSong>{};
    final dayPlays = <(String, DateTime), int>{};

    for (final listen in listens) {
      if (listen.listened <= Duration.zero) continue;
      final at = listen.startedAt;
      final inWeek = !at.isBefore(weekStart) && !at.isAfter(now);
      firstPlay ??= at;

      final before = total;
      total += listen.listened;
      if (inWeek) {
        for (final h in hourMilestones) {
          final mark = Duration(hours: h);
          if (before < mark && total >= mark) {
            hours = Highlight(kind: HighlightKind.hours, at: at, count: h);
          }
        }
      }
      if (listen.listened < ListeningStats.playThreshold) continue;

      final id = IdentifiedListen.of(listen, song);
      final s = songs[id.key] ??= id.newSong();
      final plays = songPlays[id.key] = (songPlays[id.key] ?? 0) + 1;
      final previous = lastPlay[id.key];
      lastPlay[id.key] = at;
      for (final (i, name) in id.artists.indexed) {
        final key = IdentifiedListen.artistKey(name);
        artistNames.putIfAbsent(key, () => (name, id.artistLatin[i]));
        artistFirst.putIfAbsent(key, () => at);
        final n = artistPlays[key] = (artistPlays[key] ?? 0) + 1;
        if (!inWeek) continue;
        weekArtistPlays[key] = (weekArtistPlays[key] ?? 0) + 1;
        weekArtistSong.putIfAbsent(key, () => s);
        if (artistMilestones.contains(n)) {
          artistMilestone[key] = Highlight(
            kind: HighlightKind.artistMilestone,
            at: at,
            count: n,
            song: s,
            artist: name,
            artistLatin: id.artistLatin[i],
          );
        }
      }
      if (!inWeek) continue;

      if (songMilestones.contains(plays)) {
        songMilestone[id.key] = Highlight(
          kind: HighlightKind.songMilestone,
          at: at,
          count: plays,
          song: s,
        );
      }
      if (previous != null && at.difference(previous) >= comebackGap) {
        final gap = at.difference(previous);
        if ((comebacks[id.key]?.gap ?? Duration.zero) < gap) {
          comebacks[id.key] = Highlight(
            kind: HighlightKind.comeback,
            at: at,
            song: s,
            gap: gap,
          );
        }
      }
      weekPlays[id.key] = (weekPlays[id.key] ?? 0) + 1;
      final day = (id.key, DateTime(at.year, at.month, at.day));
      dayPlays[day] = (dayPlays[day] ?? 0) + 1;
    }

    List<Highlight> top(Iterable<Highlight> all, int Function(Highlight) by) =>
        (all.toList()..sort((a, b) => by(b) - by(a))).take(perKind).toList();

    final discoveries = <Highlight>[
      if (firstPlay != null &&
          weekStart.difference(firstPlay) >= discoveryHistory)
        for (final MapEntry(key: key, value: first) in artistFirst.entries)
          if (!first.isBefore(weekStart) &&
              (weekArtistPlays[key] ?? 0) >= discoveryPlays)
            Highlight(
              kind: HighlightKind.discovery,
              at: first,
              count: weekArtistPlays[key]!,
              song: weekArtistSong[key],
              artist: artistNames[key]!.$1,
              artistLatin: artistNames[key]!.$2,
            ),
    ];

    Highlight? songOfWeek;
    final best = weekPlays.entries
        .where((e) => e.value >= songOfWeekPlays)
        .fold<MapEntry<String, int>?>(
          null,
          (best, e) => best == null || e.value > best.value ? e : best,
        );
    if (best != null) {
      songOfWeek = Highlight(
        kind: HighlightKind.songOfWeek,
        at: lastPlay[best.key]!,
        count: best.value,
        song: songs[best.key],
      );
    }

    final onRepeat = <String, Highlight>{};
    for (final MapEntry(key: (key, day), value: n) in dayPlays.entries) {
      // The song of the week is told about once.
      if (n < onRepeatPlays || key == best?.key) continue;
      if ((onRepeat[key]?.count ?? 0) < n) {
        onRepeat[key] = Highlight(
          kind: HighlightKind.onRepeat,
          at: day,
          count: n,
          song: songs[key],
        );
      }
    }

    return [
      ?hours,
      ...top(songMilestone.values, (h) => h.count),
      ...top(artistMilestone.values, (h) => h.count),
      ...top(discoveries, (h) => h.count),
      ...top(comebacks.values, (h) => h.gap!.inDays),
      ?songOfWeek,
      ...top(onRepeat.values, (h) => h.count),
    ];
  }
}
