import 'package:flutter/material.dart';

import '../data/local_library.dart';
import '../data/saved_songs.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';

/// Biblioteka › Na później ([SavedSongs]) and Polubione utwory ([LikedSongs]): the songs,
/// newest first.
class SavedSongsScreen extends StatelessWidget {
  const SavedSongsScreen({super.key}) : liked = false;

  const SavedSongsScreen.liked({super.key}) : liked = true;

  final bool liked;

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SavedSongsScreen()));

  static Future<void> openLiked(BuildContext context) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(builder: (_) => const SavedSongsScreen.liked()),
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final StoredSongList? saved = liked
        ? LikedSongsScope.maybeOf(context)
        : SavedSongsScope.maybeOf(context);
    final id = liked ? likedSongsLabel : 'Na później';
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final hits = [
      for (final ref in saved?.songs ?? const <TrackRef>[])
        resolveTrack(ref, catalog, library, youTube),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(id),
        actions: [
          if (hits.isNotEmpty)
            IconButton(
              tooltip: 'Menu (⋮)',
              icon: const Icon(Icons.more_vert),
              onPressed: () => showMenuSheet(
                context,
                idPrefix: '$id › Menu (⋮)',
                entries: queueAllEntries(
                  context,
                  hits,
                  origin: QueueOrigin(playlistName: id),
                ),
              ),
            ),
        ],
      ),
      body: SongSelectionArea(
        all: () => {for (final hit in hits) SongSelection.keyOf(hit): hit},
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (hits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  liked
                      ? 'Nic tu jeszcze nie ma. Polub utwór w „Dodaj do playlisty” '
                            '— przyciskiem ⊕ przy tytule w odtwarzaczu albo z menu ⋮ '
                            'utworu.'
                      : 'Nic tu jeszcze nie ma. Zapisz utwór zakładką w „Odkrywaj” '
                            'albo z menu ⋮ utworu: „Zapisz na później”.',
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
                          playlistName: id,
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
                playlistName: id,
                trailing: IconButton(
                  tooltip: 'Menu utworu (⋮)',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showSongMenu(
                    context,
                    hit,
                    idPrefix: '$id › Utwór › Menu (⋮)',
                  ),
                ),
                onSwipeRemove: saved == null ? null : () => saved.toggle(hit),
                swipeRemoveLabel: 'Usuń z „$id”',
              ),
          ],
        ),
      ),
    );
  }
}
