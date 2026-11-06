import 'package:flutter/material.dart';

import '../data/local_library.dart';
import '../data/play_history.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/text_normalizer.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';
import 'history_settings_screen.dart';
import 'playlist_screen.dart';
import 'song_search_screen.dart';
import '../widgets/song_names.dart';

const _id = 'Ostatnie';

typedef RecentDay = ({String label, List<PlayedTrack> plays});

/// The history by day ("Dzisiaj", "Wczoraj", "5 października"): the songs played that day,
/// newest first, each once — the same song played from another playlist (or on its own) is
/// another row, since tapping it leads somewhere else. [entries] are newest first.
List<RecentDay> groupRecents(List<PlayedTrack> entries, DateTime now) {
  final days = <RecentDay>[];
  DateTime? day;
  var plays = <PlayedTrack>[];
  var seen = <String>{};
  for (final entry in entries) {
    final at = entry.playedAt;
    final entryDay = DateTime(at.year, at.month, at.day);
    if (entryDay != day) {
      day = entryDay;
      plays = [];
      seen = {};
      days.add((label: _dayLabel(entryDay, now), plays: plays));
    }
    if (seen.add('${entry.track.key}|${entry.playlistId}')) plays.add(entry);
  }
  return days;
}

const _months = [
  'stycznia',
  'lutego',
  'marca',
  'kwietnia',
  'maja',
  'czerwca',
  'lipca',
  'sierpnia',
  'września',
  'października',
  'listopada',
  'grudnia',
];

String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Dzisiaj';
  if (day == DateTime(today.year, today.month, today.day - 1)) return 'Wczoraj';
  final label = '${day.day} ${_months[day.month - 1]}';
  return day.year == now.year ? label : '$label ${day.year}';
}

/// "Ostatnie", opened from the profile menu: what was played, newest first.
class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  bool _loading = false;

  /// Searching the history, as within a playlist: the app bar becomes a search field and only
  /// matching songs are listed; Back (the arrow or the system one) closes it first.
  LocalHistoryEntry? _searchEntry;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    // Songs are shown as their MusicDatabase rows, so music.db has to be read.
    SongCatalogScope.of(context).ensureLoaded();
  }

  bool get _searching => _searchEntry != null;

  void _startSearch() {
    final entry = LocalHistoryEntry(
      onRemove: () {
        if (!mounted) return;
        setState(() {
          _searchEntry = null;
          _query.clear();
        });
      },
    );
    ModalRoute.of(context)!.addLocalHistoryEntry(entry);
    setState(() => _searchEntry = entry);
  }

  PreferredSizeWidget _searchBar(AppPalette palette) => AppBar(
    backgroundColor: palette.background,
    leading: IconButton(
      tooltip: 'Zamknij wyszukiwanie',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pop(),
    ),
    titleSpacing: 0,
    title: TextField(
      controller: _query,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: 'Szukaj w ostatnich',
        border: InputBorder.none,
      ),
    ),
    actions: [
      if (_query.text.trim().isNotEmpty)
        SearchEverywhereButton(query: _query.text),
      if (_query.text.isNotEmpty)
        IconButton(
          tooltip: 'Wyczyść',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_query.clear),
        ),
    ],
  );

  /// The days' songs whose title, artist or album contain every word of the query (both
  /// normalised like song search), under their days; a day with none left is left out.
  Widget _searchResults(List<RecentDay> days) {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final words = normalizeForSearch(_query.text)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final matching = <RecentDay>[];
    for (final day in days) {
      final plays = day.plays.where((play) {
        final hit = resolveTrack(play.track, catalog, library, youTube);
        return words.every(
          normalizeForSearch(
            [hit.title, hit.artistLabel, hit.album ?? ''].join(' '),
          ).contains,
        );
      }).toList();
      if (plays.isNotEmpty) matching.add((label: day.label, plays: plays));
    }
    if (matching.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Brak wyników dla „${_query.text.trim()}”',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: _dayRows(matching),
    );
  }

  List<Widget> _dayRows(List<RecentDay> days) => [
    for (final day in days) ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          day.label,
          style: const TextStyle(
            fontSize: AppFontSize.section,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      for (final play in day.plays) _PlayRow(play: play),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = groupRecents(
      PlayHistoryScope.of(context).entries,
      DateTime.now(),
    );
    return Scaffold(
      appBar: _searching
          ? _searchBar(palette)
          : AppBar(
              backgroundColor: palette.background,
              centerTitle: true,
              title: const Text('Ostatnie'),
              actions: [
                IconButton(
                  tooltip: 'Szukaj w ostatnich',
                  icon: const Icon(Icons.search),
                  onPressed: days.isEmpty ? null : _startSearch,
                ),
                IconButton(
                  tooltip: 'Wyczyść historię',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: days.isEmpty
                      ? null
                      : () => confirmClearHistory(context),
                ),
              ],
            ),
      // The history stays built under the search, so closing it returns to the same place.
      body: SongSelectionArea(
        child: IndexedStack(
          index: _searching ? 1 : 0,
          children: [
            TickerMode(
              enabled: !_searching,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (days.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
                      child: Text(
                        'Nic jeszcze nie odtworzono.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  ..._dayRows(days),
                ],
              ),
            ),
            if (_searching) _searchResults(days),
          ],
        ),
      ),
    );
  }
}

/// A song from the history; one played from a playlist names it and opens it (at that song)
/// instead of playing.
class _PlayRow extends StatelessWidget {
  const _PlayRow({required this.play});

  final PlayedTrack play;

  @override
  Widget build(BuildContext context) {
    final hit = resolveTrack(
      play.track,
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      YouTubeLibraryScope.of(context),
    );
    final playlistId = play.playlistId;
    final playlist = playlistId == null
        ? null
        : PlaylistLibraryScope.of(context).playlists
              .where((p) => p.id == playlistId)
              .firstOrNull;
    return SongTile(
      hit: hit,
      subtitle: [hit.shownArtist(context), ?playlist?.name].join(' • '),
      trailing: SongMenuButton(hit: hit, idPrefix: '$_id › Utwór › Menu (⋮)'),
      menuIdPrefix: '$_id › Utwór › Menu (⋮)',
      // A playlist deleted since: the song just plays.
      onTap: playlist == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    PlaylistScreen(playlist: playlist, reveal: play.track),
              ),
            ),
    );
  }
}
