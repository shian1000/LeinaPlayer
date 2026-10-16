import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_name.dart';
import '../data/album_covers.dart';
import '../data/latin_names.dart';
import '../data/listening_stats.dart';
import '../data/listening_summary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/listening_charts.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_names.dart';
import 'listening_stats_screen.dart';

/// A year's or a season's summary as full-screen cards, after Spotify Wrapped: a tap on the
/// right goes on, on the left back (swiping too); the last card can be shared as a picture.
class ListeningSummaryScreen extends StatefulWidget {
  const ListeningSummaryScreen({super.key, required this.summary});

  final ListeningSummary summary;

  /// Over the whole app, bottom bar included, like a story.
  static Future<void> open(BuildContext context, ListeningSummary summary) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ListeningSummaryScreen(summary: summary),
        ),
      );

  @override
  State<ListeningSummaryScreen> createState() => _ListeningSummaryScreenState();
}

class _ListeningSummaryScreenState extends State<ListeningSummaryScreen> {
  final _pages = PageController();
  final _shareKey = GlobalKey();
  int _page = 0;
  bool _sharing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int by, int count) {
    final page = _page + by;
    if (page < 0) return;
    if (page >= count) {
      Navigator.of(context).pop();
      return;
    }
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// The last card as a PNG, handed to Android's share sheet.
  Future<void> _share() async {
    final boundary =
        _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/podsumowanie.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.summary.period.yourTitle} — $appName',
        ),
      );
    } catch (e) {
      debugPrint('Sharing the summary failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się udostępnić podsumowania'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cards = _cards(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final width = context.size?.width ?? 1;
                _go(
                  details.localPosition.dx < width / 3 ? -1 : 1,
                  cards.length,
                );
              },
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() => _page = page),
                children: cards,
              ),
            ),
            Positioned(
              left: 12,
              right: 4,
              top: 8,
              child: Row(
                children: [
                  for (var i = 0; i < cards.length; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: palette.textPrimary.withValues(
                            alpha: i <= _page ? 0.9 : 0.25,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Zamknij',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (_page == cards.length - 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: const Icon(Icons.share),
                    label: const Text('Udostępnij'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(BuildContext context) {
    final summary = widget.summary;
    final stats = summary.stats;
    final period = summary.period;
    final now = DateTime.now();
    final songs = stats.songs.where((s) => s.plays > 0).take(5).toList();
    final artists = stats.artists.where((a) => a.plays > 0).take(5).toList();
    final albums = stats.albums.where((a) => a.plays > 0).take(5).toList();
    final newArtists = summary.newArtists;
    final sound = [
      if (stats.decades.firstOrNull case final d?) ('Dekada', d),
      if (stats.languages.firstOrNull case final l?) ('Język', l),
      if (stats.countries.firstOrNull case final c?) ('Kraj wykonawców', c),
    ];
    final last = period.to.subtract(const Duration(days: 1));
    final spanDays =
        (now.isBefore(period.to) ? now : period.to)
            .difference(period.from)
            .inDays +
        1;
    final minutes = (stats.listened.inSeconds / 60).round();
    final word = period.isYear ? 'roku' : 'sezonu';

    return [
      _Card(
        seed: '${period.title} intro',
        children: [
          _Label(period.isYear ? 'Podsumowanie roku' : 'Podsumowanie sezonu'),
          _Big(period.yourTitle),
          const SizedBox(height: 12),
          Text(
            '${dayMonthLabel(period.from)} – ${dayMonthLabel(last, year: true)}',
          ),
          if (period.inProgress(now)) ...[
            const SizedBox(height: 24),
            Text(
              period.isYear
                  ? 'Rok jeszcze trwa — to podsumowanie do dziś.'
                  : 'Sezon jeszcze trwa — to podsumowanie do dziś.',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 48),
          _Hint('Dotknij, aby przejść dalej'),
        ],
      ),
      _Card(
        seed: '${period.title} minutes',
        children: [
          const _Label('Czas słuchania'),
          _Big('$minutes ${pluralWord(minutes, 'minuta', 'minuty', 'minut')}'),
          const SizedBox(height: 12),
          Text(
            [
              ?_hoursText(stats.listened),
              'średnio ${minutesLabel(stats.listened ~/ spanDays)} dziennie',
              '${stats.plays} ${pluralWord(stats.plays, 'odtworzenie', 'odtworzenia', 'odtworzeń')}',
            ].join('\n'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          MonthChart(months: summary.months),
        ],
      ),
      if (songs.isNotEmpty)
        _Card(
          seed: '${period.title} song',
          children: [
            _Label('Utwór $word'),
            _SongCover(song: songs.first, size: 220),
            const SizedBox(height: 16),
            _SongNames(song: songs.first, big: true),
            const SizedBox(height: 8),
            Text(_playsLine(songs.first.plays, songs.first.listened)),
          ],
        ),
      if (songs.length > 1)
        _Card(
          seed: '${period.title} songs',
          children: [
            const _Label('Najczęściej słuchane utwory'),
            const SizedBox(height: 8),
            for (final (i, song) in songs.indexed)
              _Row(
                rank: i + 1,
                leading: _SongCover(song: song, size: 52),
                body: _SongNames(song: song),
                trailing: '${song.plays}×',
              ),
          ],
        ),
      if (artists.isNotEmpty)
        _Card(
          seed: '${period.title} artist',
          children: [
            _Label('Wykonawca $word'),
            ClipOval(child: _EntryCover(entry: artists.first, size: 220)),
            const SizedBox(height: 16),
            _Big(_name(context, artists.first)),
            const SizedBox(height: 8),
            Text(_playsLine(artists.first.plays, artists.first.listened)),
          ],
        ),
      if (artists.length > 1)
        _Card(
          seed: '${period.title} artists',
          children: [
            const _Label('Najczęściej słuchani wykonawcy'),
            const SizedBox(height: 8),
            for (final (i, a) in artists.indexed)
              _Row(
                rank: i + 1,
                leading: ClipOval(child: _EntryCover(entry: a, size: 52)),
                body: Text(
                  _name(context, a),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.listTitle,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: '${a.plays}×',
              ),
          ],
        ),
      if (albums.isNotEmpty)
        _Card(
          seed: '${period.title} albums',
          children: [
            _Label('Album $word'),
            _EntryCover(entry: albums.first, size: 180),
            const SizedBox(height: 12),
            _Big(_name(context, albums.first), small: true),
            if (albums.first.detail case final artist?) Text(artist),
            const SizedBox(height: 24),
            for (final (i, a) in albums.skip(1).indexed)
              _Row(
                rank: i + 2,
                leading: _EntryCover(entry: a, size: 44),
                body: Text(
                  _name(context, a),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: '${a.plays}×',
              ),
          ],
        ),
      if (sound.isNotEmpty)
        _Card(
          seed: '${period.title} sound',
          children: [
            const _Label('Twoje brzmienie'),
            for (final (label, entry) in sound) ...[
              const SizedBox(height: 16),
              Text(label),
              _Big(entry.name, small: true),
              Text(
                '${(entry.listened.inMilliseconds * 100 / stats.listened.inMilliseconds).round()}% '
                'czasu słuchania',
              ),
            ],
          ],
        ),
      _Card(
        seed: '${period.title} hours',
        children: [
          const _Label('Pory dnia'),
          const SizedBox(height: 16),
          HourChart(hours: stats.hours),
        ],
      ),
      if (newArtists != null && newArtists.isNotEmpty)
        _Card(
          seed: '${period.title} new',
          children: [
            _Label('Odkrycia $word'),
            _Big(
              '${newArtists.length} ${pluralWord(newArtists.length, 'nowy wykonawca', 'nowych wykonawców', 'nowych wykonawców')}',
              small: true,
            ),
            const SizedBox(height: 8),
            const Text(
              'Słuchani pierwszy raz w statystykach',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            for (final (i, a) in newArtists.take(3).indexed)
              _Row(
                rank: i + 1,
                leading: ClipOval(child: _EntryCover(entry: a, size: 52)),
                body: Text(
                  _name(context, a),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: '${a.plays}×',
              ),
          ],
        ),
      RepaintBoundary(
        key: _shareKey,
        child: _Card(
          seed: '${period.title} share',
          // Room for the share button under it.
          bottomPadding: 72,
          children: [
            if (songs.isNotEmpty) ...[
              _SongCover(song: songs.first, size: 140),
              const SizedBox(height: 16),
            ],
            _Big(period.yourTitle, small: true),
            const SizedBox(height: 4),
            Text(
              '$minutes ${pluralWord(minutes, 'minuta', 'minuty', 'minut')} słuchania',
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TopList(
                    title: 'Wykonawcy',
                    names: [for (final a in artists) _name(context, a)],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TopList(
                    title: 'Utwory',
                    names: [
                      for (final s in songs)
                        hitOfStatsSong(context, s).shownTitle(context),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _Hint(appName),
          ],
        ),
      ),
    ];
  }

  static String _name(BuildContext context, StatsEntry e) =>
      showsLatinNames(context) ? withLatin(e.name, e.latin) : e.name;

  static String _playsLine(int plays, Duration listened) =>
      '$plays ${pluralWord(plays, 'odtworzenie', 'odtworzenia', 'odtworzeń')} • '
      '${minutesLabel(listened)}';

  /// "To 2 dni i 5 godz." / "To 3 godz. 20 min"; `null` under an hour (the minutes say it).
  static String? _hoursText(Duration d) {
    if (d.inDays >= 1) {
      final hours = d.inHours % 24;
      return 'To ${d.inDays} ${pluralWord(d.inDays, 'dzień', 'dni', 'dni')}'
          '${hours > 0 ? ' i $hours godz.' : ''}';
    }
    if (d.inHours == 0) return null;
    return 'To ${d.inHours} godz. ${d.inMinutes % 60} min';
  }
}

/// One full-screen card: a colour of the theme's own (kept near the background, so its text
/// stays readable), everything centred.
class _Card extends StatelessWidget {
  const _Card({
    required this.seed,
    required this.children,
    this.bottomPadding = 24,
  });

  final String seed;
  final List<Widget> children;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: Color.lerp(palette.colorForSeed(seed), palette.background, 0.45)!,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: AppFontSize.listTitle,
          color: palette.textPrimary,
        ),
        textAlign: TextAlign.center,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 56, 24, bottomPadding),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: AppFontSize.small,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    ),
  );
}

class _Big extends StatelessWidget {
  const _Big(this.text, {this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: small ? AppFontSize.largeTitle : AppFontSize.hero * 1.4,
      fontWeight: FontWeight.bold,
      height: 1.15,
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: AppFontSize.small,
      color: context.palette.textPrimary.withValues(alpha: 0.7),
    ),
  );
}

/// A ranked row: number, cover, names, how often.
class _Row extends StatelessWidget {
  const _Row({
    required this.rank,
    required this.leading,
    required this.body,
    required this.trailing,
  });

  final int rank;
  final Widget leading;

  /// The names.
  final Widget body;
  final String trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$rank',
            style: const TextStyle(
              fontSize: AppFontSize.emphasis,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: body),
        ),
        const SizedBox(width: 8),
        Text(trailing),
      ],
    ),
  );
}

class _SongCover extends StatelessWidget {
  const _SongCover({required this.song, required this.size});

  final StatsSong song;
  final double size;

  @override
  Widget build(BuildContext context) => SongCover(
    cover: CoverRequest.of(hitOfStatsSong(context, song)),
    size: size,
  );
}

/// An artist's or album's cover: its most played song's.
class _EntryCover extends StatelessWidget {
  const _EntryCover({required this.entry, required this.size});

  final StatsEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) => entry.song == null
      ? SizedBox.square(dimension: size)
      : _SongCover(song: entry.song!, size: size);
}

class _SongNames extends StatelessWidget {
  const _SongNames({required this.song, this.big = false});

  final StatsSong song;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final hit = hitOfStatsSong(context, song);
    return Column(
      crossAxisAlignment: big
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          hit.shownTitle(context),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: big ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: big ? AppFontSize.largeTitle : AppFontSize.listTitle,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          hit.shownArtist(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: big ? TextAlign.center : TextAlign.start,
        ),
      ],
    );
  }
}

/// The share card's columns: a heading and up to five names, numbered.
class _TopList extends StatelessWidget {
  const _TopList({required this.title, required this.names});

  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: AppFontSize.small,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      for (final (i, name) in names.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${i + 1}. $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
          ),
        ),
    ],
  );
}
