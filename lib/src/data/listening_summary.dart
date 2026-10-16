import 'listening_log.dart';
import 'listening_stats.dart';
import 'song_catalog.dart';

enum Season {
  spring('Wiosna', 'Twoja wiosna', 3),
  summer('Lato', 'Twoje lato', 6),
  autumn('Jesień', 'Twoja jesień', 9),
  winter('Zima', 'Twoja zima', 12);

  const Season(this.name, this.yours, this.firstMonth);

  final String name;

  /// "Twoja wiosna", for the first card.
  final String yours;

  /// Meteorological seasons: whole months, so a summary starts on the 1st.
  final int firstMonth;

  static Season of(DateTime at) => switch (at.month) {
    3 || 4 || 5 => spring,
    6 || 7 || 8 => summer,
    9 || 10 || 11 => autumn,
    _ => winter,
  };
}

/// A span a summary covers (like Spotify Wrapped, but also per season): a calendar year or a
/// season.
class SummaryPeriod {
  const SummaryPeriod._(this.from, this.to, this.season);

  factory SummaryPeriod.year(int year) =>
      SummaryPeriod._(DateTime(year), DateTime(year + 1), null);

  /// The season [at] is in; winter runs from December into the next year.
  factory SummaryPeriod.seasonOf(DateTime at) {
    final season = Season.of(at);
    final year = at.month <= 2 ? at.year - 1 : at.year;
    final from = DateTime(year, season.firstMonth);
    return SummaryPeriod._(from, DateTime(year, season.firstMonth + 3), season);
  }

  final DateTime from;

  /// The first moment after it.
  final DateTime to;

  /// `null` for a year.
  final Season? season;

  bool get isYear => season == null;

  /// "2026", or "2025/26" for a winter.
  String get yearLabel => season == Season.winter
      ? '${from.year}/${'${(from.year + 1) % 100}'.padLeft(2, '0')}'
      : '${from.year}';

  /// "Rok 2026", "Lato 2026", "Zima 2025/26".
  String get title => '${season?.name ?? 'Rok'} $yearLabel';

  /// "Twój rok 2026", "Twoje lato 2026".
  String get yourTitle => '${season?.yours ?? 'Twój rok'} $yearLabel';

  bool contains(DateTime at) => !at.isBefore(from) && at.isBefore(to);

  /// Still going on at [now]: summed up so far.
  bool inProgress(DateTime now) => now.isBefore(to);

  /// The periods [listens] have plays in, newest first: each year, then its seasons, newest
  /// first.
  static List<SummaryPeriod> available(Iterable<Listen> listens) {
    final periods = <SummaryPeriod>{};
    for (final listen in listens) {
      if (listen.listened < ListeningStats.playThreshold) continue;
      periods
        ..add(SummaryPeriod.year(listen.startedAt.year))
        ..add(SummaryPeriod.seasonOf(listen.startedAt));
    }
    // A year before the seasons that end in it.
    return periods.toList()..sort(
      (a, b) => a.to != b.to
          ? b.to.compareTo(a.to)
          : (a.isYear ? 0 : 1) - (b.isYear ? 0 : 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SummaryPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// What a year or a season's summary shows ("Twoje lato 2026"): the stats of its plays, how
/// the listening went month by month, and the artists first heard in it.
class ListeningSummary {
  ListeningSummary._(this.period, this.stats, this.months, this.newArtists);

  /// [listens] are every play (oldest first): the ones before [period] tell which artists are
  /// new in it.
  factory ListeningSummary.of(
    List<Listen> listens,
    SummaryPeriod period, {
    CatalogSong? Function(int id)? song,
  }) {
    final inside = [
      for (final l in listens)
        if (period.contains(l.startedAt)) l,
    ];
    final stats = ListeningStats.of(inside, song: song);
    final months = <DateTime, Duration>{
      for (
        var m = period.from;
        m.isBefore(period.to);
        m = DateTime(m.year, m.month + 1)
      )
        m: Duration.zero,
    };
    for (final l in inside) {
      final m = DateTime(l.startedAt.year, l.startedAt.month);
      months[m] = months[m]! + l.listened;
    }
    final before = [
      for (final l in listens)
        if (l.startedAt.isBefore(period.from) &&
            l.listened >= ListeningStats.playThreshold)
          l,
    ];
    List<StatsEntry>? newArtists;
    // With no plays before it, every artist would be new.
    if (before.isNotEmpty) {
      final known = {
        for (final l in before)
          for (final name in IdentifiedListen.of(l, song).artists)
            IdentifiedListen.artistKey(name),
      };
      newArtists = [
        for (final a in stats.artists)
          if (a.plays > 0 &&
              !known.contains(IdentifiedListen.artistKey(a.name)))
            a,
      ];
    }
    return ListeningSummary._(period, stats, [
      for (final e in months.entries) (month: e.key, listened: e.value),
    ], newArtists);
  }

  final SummaryPeriod period;
  final ListeningStats stats;

  /// Each month of the period, with what was heard in it.
  final List<({DateTime month, Duration listened})> months;

  /// Artists first heard in the period, most played first; `null` when the stats began in it
  /// (no way to tell).
  final List<StatsEntry>? newArtists;
}
