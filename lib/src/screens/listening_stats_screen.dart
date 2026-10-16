import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/latin_names.dart';
import '../data/listening_highlights.dart';
import '../data/listening_log.dart';
import '../data/listening_stats.dart';
import '../data/listening_summary.dart';
import '../data/local_library.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/listening_charts.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_names.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';
import 'listening_summary_screen.dart';

/// Ja › Statystyki słuchania: what was listened to over a period, from the plays the phone
/// records (`listening_log.dart`, synced with the MusicDatabase account) — minutes, top songs,
/// artists and albums, and shares of decades, languages, countries and sources.
class ListeningStatsScreen extends StatefulWidget {
  const ListeningStatsScreen({super.key});

  /// How many top songs show before "Pokaż więcej", and at most after it.
  static const shortList = 5;
  static const longList = 50;

  @override
  State<ListeningStatsScreen> createState() => _ListeningStatsScreenState();
}

class _ListeningStatsScreenState extends State<ListeningStatsScreen> {
  StatsPeriod _period = StatsPeriod.weeks4;

  /// Every play of the account, oldest first; the period is picked from them.
  List<Listen>? _listens;
  ListeningStats? _stats;
  List<Highlight>? _highlights;
  List<SummaryPeriod>? _summaries;
  bool _allSongs = false;

  /// What [_listens] were read for: another account or new plays read them again.
  Object? _readFor;
  int _reading = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongCatalogScope.of(context).ensureLoaded();
    // A new music.db changes names and merges songs.
    _stats = null;
    _highlights = null;
    _summaries = null;
    _reload();
  }

  /// Reads the plays again when the account or the plays changed.
  void _reload() {
    final log = ListeningLogScope.maybeOf(context);
    final user = AccountScope.maybeOf(context)?.userName;
    final readFor = (user, log?.current?.uid, log?.syncing);
    if (readFor == _readFor) return;
    _readFor = readFor;
    _read(log, user);
  }

  Future<void> _read(ListeningLog? log, String? user) async {
    if (log == null) return;
    final reading = ++_reading;
    final listens = await log.listens(account: user);
    if (!mounted || reading != _reading) return;
    setState(() {
      _listens = listens;
      _stats = null;
      _highlights = null;
      _summaries = null;
    });
  }

  void _pick(StatsPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _allSongs = false;
      _stats = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = SongCatalogScope.of(context);
    final listens = _listens;
    final now = DateTime.now();
    final from = _period.from(now);
    final stats = listens == null
        ? null
        : _stats ??= ListeningStats.of(
            from == null
                ? listens
                : listens.where((l) => !l.startedAt.isBefore(from)),
            song: catalog.current,
          );
    final highlights = listens == null
        ? const <Highlight>[]
        : _highlights ??= ListeningHighlights.of(
            listens,
            now: now,
            song: catalog.current,
          );
    final summaries = listens == null
        ? const <SummaryPeriod>[]
        : _summaries ??= SummaryPeriod.available(listens);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.background,
        centerTitle: true,
        title: const Text('Statystyki słuchania'),
      ),
      body: SongSelectionArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (highlights.isNotEmpty) ...[
              const SectionTitle('Ten tydzień'),
              _HighlightRow(
                highlights: highlights,
                hitOf: (s) => _hitOf(context, s),
              ),
              const SizedBox(height: 8),
            ],
            if (summaries.isNotEmpty) ...[
              const SectionTitle('Podsumowania'),
              _SummaryRow(
                periods: summaries,
                onOpen: (period) => ListeningSummaryScreen.open(
                  context,
                  ListeningSummary.of(listens!, period, song: catalog.current),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  for (final period in StatsPeriod.values) ...[
                    PillChip(
                      label: period.label,
                      selected: period == _period,
                      onTap: () => _pick(period),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (stats == null)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (stats.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
                child: Text(
                  'Nic jeszcze nie przesłuchano w tym okresie.\n\n'
                  'Statystyki liczą się od wersji aplikacji, która je zapisuje: każdy utwór '
                  'z tym, ile go naprawdę słuchano.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              )
            else
              ..._sections(context, stats),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, ListeningStats stats) {
    final songs = stats.songs.take(ListeningStatsScreen.longList).toList();
    final hits = [for (final s in songs) _hitOf(context, s)];
    final shown = _allSongs
        ? hits.length
        : ListeningStatsScreen.shortList.clamp(0, hits.length);
    final queueName = 'Najczęściej słuchane: ${_period.label.toLowerCase()}';
    return [
      _Summary(stats: stats, period: _period),
      SectionTitle(
        'Utwory',
        trailing: TextButton(
          onPressed: () => runQueueAction(
            context,
            (onStatus) => PlaybackQueueScope.of(context)
                .start(hits, 0, playlistName: queueName, onStatus: onStatus),
          ),
          child: const Text('Odtwórz'),
        ),
      ),
      for (var i = 0; i < shown; i++)
        Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: AppFontSize.listTitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: SongTile(
                hit: hits[i],
                queue: hits,
                queueIndex: i,
                playlistName: queueName,
                subtitle:
                    '${hits[i].shownArtist(context)} • ${_playsAndTime(songs[i].plays, songs[i].listened)}',
              ),
            ),
          ],
        ),
      if (hits.length > ListeningStatsScreen.shortList)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _allSongs = !_allSongs),
            child: Text(_allSongs ? 'Pokaż mniej' : 'Pokaż więcej'),
          ),
        ),
      if (stats.artists.isNotEmpty) ...[
        const SectionTitle('Wykonawcy'),
        _CoverRow(
          entries: stats.artists.take(10).toList(),
          round: true,
          hitOf: (s) => _hitOf(context, s),
          onTap: (e) => openArtistSongs(context, e.name),
        ),
      ],
      if (stats.albums.isNotEmpty) ...[
        const SectionTitle('Albumy'),
        _CoverRow(
          entries: stats.albums.take(10).toList(),
          round: false,
          hitOf: (s) => _hitOf(context, s),
          onTap: (e) => openAlbumSongs(context, e.name),
        ),
      ],
      const SectionTitle('Pory dnia'),
      HourChart(hours: stats.hours),
      for (final (title, entries) in [
        ('Dekady', stats.decades),
        ('Języki', stats.languages),
        ('Kraje wykonawców', stats.countries),
      ])
        if (entries.isNotEmpty) ...[
          SectionTitle(title),
          _Shares(
            shares: [
              for (final e in entries.take(5)) (name: e.name, time: e.listened),
            ],
            total: stats.listened,
          ),
        ],
      const SectionTitle('Skąd grało'),
      _Shares(
        shares: [
          for (final source in ListenSource.values)
            if (stats.sources[source] case final time?)
              (
                name: switch (source) {
                  ListenSource.phone => 'Pliki na telefonie',
                  ListenSource.server => 'Serwer MusicDatabase',
                  ListenSource.youtube => 'YouTube',
                },
                time: time,
              ),
        ]..sort((a, b) => b.time.compareTo(a.time)),
        total: stats.listened,
      ),
    ];
  }

  /// [song] as a playable row, with what the phone knows about it now.
  static SearchHit _hitOf(BuildContext context, StatsSong song) =>
      hitOfStatsSong(context, song);
}

/// A [StatsSong] as a playable row, with what the phone knows about it now.
SearchHit hitOfStatsSong(BuildContext context, StatsSong song) => resolveTrack(
  TrackRef(
    title: song.title,
    artist: song.artist,
    mainDbId: song.songId,
    videoId: song.youtubeVideoId,
    spotifyTrackId: song.spotifyTrackId,
  ),
  SongCatalogScope.of(context),
  LocalLibraryScope.of(context),
  YouTubeLibraryScope.of(context),
);

/// "12 odtw. • 45 min" — short, after the artist in a song row.
String _playsAndTime(int plays, Duration listened) =>
    '$plays odtw. • ${minutesLabel(listened)}';

/// The big number: minutes listened, with plays, songs and artists under it.
class _Summary extends StatelessWidget {
  const _Summary({required this.stats, required this.period});

  final ListeningStats stats;
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final minutes = (stats.listened.inSeconds / 60).round();
    final first = stats.firstPlay;
    final from = period.from(DateTime.now());
    final songs = stats.songs.where((s) => s.plays > 0).length;
    final artists = stats.artists.where((a) => a.plays > 0).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: palette.surface,
        shape: palette.boxShape(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$minutes ${pluralWord(minutes, 'minuta', 'minuty', 'minut')}',
                style: TextStyle(
                  fontSize: AppFontSize.hero,
                  fontWeight: FontWeight.bold,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '${stats.plays} ${pluralWord(stats.plays, 'odtworzenie', 'odtworzenia', 'odtworzeń')}',
                  '$songs ${songsWord(songs)}',
                  '$artists ${pluralWord(artists, 'wykonawca', 'wykonawców', 'wykonawców')}',
                ].join(' • '),
                style: const TextStyle(fontSize: AppFontSize.body),
              ),
              // The stats began after the period did: say from when they count.
              if (first != null && (from == null || first.isAfter(from))) ...[
                const SizedBox(height: 8),
                Text(
                  'Liczone od ${dayMonthLabel(first, year: true)}. '
                  'Odtworzenie liczy się od '
                  '${ListeningStats.playThreshold.inSeconds} s słuchania.',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Artists or albums in a sideways row: the cover of their most played song, the name and how
/// often they were played.
class _CoverRow extends StatelessWidget {
  const _CoverRow({
    required this.entries,
    required this.round,
    required this.hitOf,
    required this.onTap,
  });

  static const _cover = 120.0;

  final List<StatsEntry> entries;

  /// Round covers for artists, as Spotify shows them.
  final bool round;
  final SearchHit Function(StatsSong song) hitOf;
  final void Function(StatsEntry entry) onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final latin = showsLatinNames(context);
    return SizedBox(
      // Albums: two lines of name and the artist under it.
      height: _cover + (round ? 52 : 92),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final entry = entries[i];
          final song = entry.song;
          final cover = song == null
              ? SizedBox.square(dimension: _cover)
              : SongCover(cover: CoverRequest.of(hitOf(song)), size: _cover);
          return InkWell(
            borderRadius: palette.radius(4),
            onTap: () => onTap(entry),
            child: SizedBox(
              width: _cover,
              child: Column(
                crossAxisAlignment: round
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  round ? ClipOval(child: cover) : cover,
                  const SizedBox(height: 6),
                  Text(
                    '${i + 1}. ${latin ? withLatin(entry.name, entry.latin) : entry.name}',
                    maxLines: round ? 1 : 2,
                    textAlign: round ? TextAlign.center : TextAlign.start,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.small,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  for (final line in [?entry.detail, _playsOf(entry)])
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.small,
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _playsOf(StatsEntry e) =>
      '${e.plays} ${pluralWord(e.plays, 'odtworzenie', 'odtworzenia', 'odtworzeń')}';
}

/// Shares of the listened time: a name, its share as a bar and a percentage.
class _Shares extends StatelessWidget {
  const _Shares({required this.shares, required this.total});

  final List<({String name, Duration time})> shares;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final share in shares)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Builder(
                builder: (context) {
                  final part = total == Duration.zero
                      ? 0.0
                      : share.time.inMilliseconds / total.inMilliseconds;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              share.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppFontSize.body,
                              ),
                            ),
                          ),
                          Text(
                            '${(part * 100).round()}% • ${minutesLabel(share.time)}',
                            style: TextStyle(
                              fontSize: AppFontSize.small,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: palette.radius(4),
                        child: LinearProgressIndicator(
                          value: part,
                          minHeight: 6,
                          color: palette.accent,
                          backgroundColor: palette.surfaceHigh,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The week's highlights as cards in a sideways row; a song's plays it, an artist's opens
/// their songs.
class _HighlightRow extends StatelessWidget {
  const _HighlightRow({required this.highlights, required this.hitOf});

  static const _width = 240.0;
  static const _cover = 56.0;

  final List<Highlight> highlights;
  final SearchHit Function(StatsSong song) hitOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final latin = showsLatinNames(context);
    return SizedBox(
      height: _cover + 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: highlights.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final h = highlights[i];
          final song = h.song;
          final hit = song == null ? null : hitOf(song);
          final artist = h.artist == null
              ? null
              : latin
              ? withLatin(h.artist!, h.artistLatin)
              : h.artist!;
          final songLine = hit == null
              ? ''
              : '„${hit.shownTitle(context)}” • ${hit.shownArtist(context)}';
          final (icon, title, detail) = switch (h.kind) {
            HighlightKind.hours => (
              Icons.schedule,
              '${h.count} ${pluralWord(h.count, 'godzina', 'godziny', 'godzin')} słuchania',
              'Tyle już razem w statystykach',
            ),
            HighlightKind.songMilestone => (
              Icons.emoji_events_outlined,
              '${h.count}. odtworzenie',
              songLine,
            ),
            HighlightKind.artistMilestone => (
              Icons.emoji_events_outlined,
              '${h.count} odtworzeń',
              artist!,
            ),
            HighlightKind.discovery => (
              Icons.explore_outlined,
              'Nowe odkrycie',
              '$artist • ${h.count} odtw. w tym tygodniu',
            ),
            HighlightKind.comeback => (
              Icons.replay,
              'Powrót ${_after(h.gap!)}',
              songLine,
            ),
            HighlightKind.songOfWeek => (
              Icons.star_outline,
              'Utwór tygodnia',
              '$songLine • ${h.count} odtw.',
            ),
            HighlightKind.onRepeat => (
              Icons.repeat,
              'Na zapętleniu',
              '$songLine • ${h.count} razy jednego dnia',
            ),
          };
          final byArtist =
              h.kind == HighlightKind.artistMilestone ||
              h.kind == HighlightKind.discovery;
          final cover = hit == null
              ? Icon(icon, size: 32, color: palette.accent)
              : SongCover(cover: CoverRequest.of(hit), size: _cover);
          return Material(
            color: palette.surface,
            shape: palette.boxShape(12),
            child: InkWell(
              customBorder: palette.boxShape(12),
              onTap: byArtist
                  ? () => openArtistSongs(context, h.artist!)
                  : hit == null
                  ? null
                  : () => runQueueAction(
                      context,
                      (onStatus) =>
                          PlaybackQueueScope.of(context)
                              .start([hit], 0, onStatus: onStatus),
                    ),
              child: SizedBox(
                width: _width,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: _cover,
                        child: Center(
                          child: byArtist && hit != null
                              ? ClipOval(child: cover)
                              : cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(icon, size: 16, color: palette.accent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: AppFontSize.small,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.small,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// "po 4 miesiącach", "po roku", "po 2 latach".
  static String _after(Duration gap) {
    final days = gap.inDays;
    if (days >= 365) {
      final years = days ~/ 365;
      return years == 1 ? 'po roku' : 'po $years latach';
    }
    final months = days ~/ 30;
    return months == 1 ? 'po miesiącu' : 'po $months miesiącach';
  }
}

/// The years and seasons with plays, as tiles opening their Wrapped-like summary.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.periods, required this.onOpen});

  final List<SummaryPeriod> periods;
  final void Function(SummaryPeriod period) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: periods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final period = periods[i];
          return Material(
            color: Color.lerp(
              palette.colorForSeed(period.title),
              palette.background,
              0.3,
            ),
            shape: palette.boxShape(12),
            child: InkWell(
              customBorder: palette.boxShape(12),
              onTap: () => onOpen(period),
              child: SizedBox(
                width: 150,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        period.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSize.listTitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        period.inProgress(now) ? 'Trwa' : 'Zobacz',
                        style: const TextStyle(fontSize: AppFontSize.small),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
