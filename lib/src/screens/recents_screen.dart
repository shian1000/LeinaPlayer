import 'package:flutter/material.dart';

import '../data/local_library.dart';
import '../data/play_history.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../dummy.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';
import 'history_settings_screen.dart';
import 'playlist_screen.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    // Songs are shown as their MusicDatabase rows, so music.db has to be read.
    SongCatalogScope.of(context).ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = groupRecents(
      PlayHistoryScope.of(context).entries,
      DateTime.now(),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.background,
        centerTitle: true,
        title: const Text('Ostatnie'),
        actions: [
          IconButton(
            tooltip: 'Wyczyść historię',
            icon: const Icon(Icons.delete_outline),
            onPressed: days.isEmpty ? null : () => confirmClearHistory(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                PillChip(
                  label: 'Muzyka',
                  onTap: () => showDummy(context, '$_id › Filtr: Muzyka'),
                ),
              ],
            ),
          ),
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
              child: Text(
                'Nic jeszcze nie odtworzono.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
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
        ],
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
      subtitle: [hit.artistLabel, ?playlist?.name].join(' • '),
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
