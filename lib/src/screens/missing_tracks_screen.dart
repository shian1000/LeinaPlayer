import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';

/// "Wyświetl utwory, których nie ma w bazie danych" from a playlist's ⋮: its tracks not
/// recognised as MusicDatabase songs. Only a list for now; later the place to ask
/// MusicDatabase to add them.
class MissingTracksScreen extends StatelessWidget {
  const MissingTracksScreen({
    super.key,
    required this.playlist,
    required this.tracks,
    this.saved = true,
  });

  final PlaylistSummary playlist;
  final List<PlaylistTrack> tracks;

  /// `false`: a playlist found by search and not in Biblioteka ([PlaylistSummary.id] means
  /// nothing).
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final hits = [
      for (final track in tracks) playlistHit(track, catalog, library, youTube),
    ];
    // Positions in the playlist, so a tap plays on through the whole playlist from there.
    final missing = [
      for (final (i, hit) in hits.indexed)
        if (!hit.inMainDatabase) i,
    ];

    final String summary;
    switch (catalog.status) {
      case CatalogStatus.ready:
        summary = missing.isEmpty
            ? 'Wszystkie utwory tej playlisty są w bazie danych.'
            : 'Poza bazą danych: ${missing.length} z ${hits.length}';
      case CatalogStatus.noDatabase:
        summary =
            'Baza danych nie jest jeszcze pobrana (Ustawienia › Źródła muzyki › '
            'Baza danych), więc żaden utwór nie został rozpoznany.';
      case CatalogStatus.error:
        summary = 'Nie udało się wczytać bazy danych.';
      case CatalogStatus.notLoaded || CatalogStatus.loading:
        summary = 'Wczytuję bazę danych…';
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Utwory spoza bazy danych'),
            Text(
              playlist.name,
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              summary,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
          if (catalog.status == CatalogStatus.ready)
            for (final i in missing)
              SongTile(
                hit: hits[i],
                queue: hits,
                queueIndex: i,
                playlistId: saved ? playlist.id : null,
                youTubeListId: playlist.youTubeId,
                playlistName: playlist.name,
                subtitle: hits[i].artistLabel,
              ),
        ],
      ),
    );
  }
}
