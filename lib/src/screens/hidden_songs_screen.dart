import 'package:flutter/material.dart';

import '../data/hidden_songs.dart';
import '../data/local_library.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';

/// "Ustawienia › Odtwarzanie › Ukryte utwory": the songs hidden with "Ukryj utwór", newest first,
/// each with "Przestań ukrywać".
class HiddenSongsScreen extends StatelessWidget {
  const HiddenSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hidden = HiddenSongsScope.maybeOf(context);
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final hits = [
      for (final ref in hidden?.songs ?? const <TrackRef>[])
        resolveTrack(ref, catalog, library, youTube),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Ukryte utwory'),
      ),
      body: hits.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Brak ukrytych utworów. Ukryjesz utwór z jego menu ⋮: „Ukryj utwór” — '
                'kolejka, Odkrywaj i radio utworu będą go pomijać.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final hit in hits)
                  SongTile(
                    hit: hit,
                    trailing: IconButton(
                      tooltip: 'Przestań ukrywać',
                      icon: const Icon(Icons.visibility_outlined),
                      onPressed: () => hidden?.toggle(hit),
                    ),
                  ),
              ],
            ),
    );
  }
}
