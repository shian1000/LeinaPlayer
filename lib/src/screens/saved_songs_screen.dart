import 'package:flutter/material.dart';

import '../data/local_library.dart';
import '../data/saved_songs.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';

const _id = 'Na później';

/// Biblioteka › Na później: songs saved to listen to later ([SavedSongs]), newest first.
class SavedSongsScreen extends StatelessWidget {
  const SavedSongsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SavedSongsScreen()));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final saved = SavedSongsScope.maybeOf(context);
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final hits = [
      for (final ref in saved?.songs ?? const <TrackRef>[])
        resolveTrack(ref, catalog, library, youTube),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Na później')),
      body: SongSelectionArea(
        all: () => {for (final hit in hits) SongSelection.keyOf(hit): hit},
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (hits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nic tu jeszcze nie ma. Zapisz utwór zakładką w „Odkrywaj” albo '
                  'z menu ⋮ utworu: „Zapisz na później”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Odtwórz'),
                    onPressed: () {
                      final queue = PlaybackQueueScope.of(context);
                      runQueueAction(
                        context,
                        (onStatus) => queue.start(
                          hits,
                          0,
                          playlistName: _id,
                          onStatus: onStatus,
                        ),
                      );
                    },
                  ),
                ),
              ),
            for (final (i, hit) in hits.indexed)
              SongTile(
                hit: hit,
                queue: hits,
                queueIndex: i,
                playlistName: _id,
                trailing: IconButton(
                  tooltip: 'Menu utworu (⋮)',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showSongMenu(
                    context,
                    hit,
                    idPrefix: '$_id › Utwór › Menu (⋮)',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
