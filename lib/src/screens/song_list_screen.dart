import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';

/// A plain list of songs picked by something other than a playlist (a decade, a language, a
/// country in Wyszukaj's "Przeglądaj"): "Odtwórz", "Losowo" and the song rows.
class SongListScreen extends StatelessWidget {
  const SongListScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songs,
  });

  final String title;
  final String subtitle;

  /// Read when the screen builds, so it follows a new music.db.
  final List<SearchHit> Function(BuildContext context) songs;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<SearchHit> Function(BuildContext context) songs,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SongListScreen(title: title, subtitle: subtitle, songs: songs),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hits = songs(context);
    void play({required bool shuffled}) {
      final queue = PlaybackQueueScope.of(context);
      runQueueAction(
        context,
        (onStatus) => shuffled
            ? queue.startShuffled(hits, playlistName: title, onStatus: onStatus)
            : queue.start(hits, 0, playlistName: title, onStatus: onStatus),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SongSelectionArea(
        all: () => {for (final hit in hits) SongSelection.keyOf(hit): hit},
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '$subtitle • ${hits.length} utw.',
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Odtwórz'),
                    onPressed: hits.isEmpty
                        ? null
                        : () => play(shuffled: false),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Losowo'),
                    onPressed: hits.isEmpty ? null : () => play(shuffled: true),
                  ),
                ],
              ),
            ),
            for (final (i, hit) in hits.indexed)
              SongTile(
                hit: hit,
                queue: hits,
                queueIndex: i,
                playlistName: title,
                trailing: SongMenuButton(
                  hit: hit,
                  idPrefix: '$title › Utwór › Menu (⋮)',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
