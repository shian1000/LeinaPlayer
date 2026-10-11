import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';

/// "Zajęte miejsce" in the YouTube settings: the songs in the cache, most recently played first.
/// Tapping one plays it and then the rest of the list (all from the phone, so offline too); ⊖
/// deletes that song's audio.
class CacheContentsScreen extends StatefulWidget {
  const CacheContentsScreen({super.key});

  @override
  State<CacheContentsScreen> createState() => _CacheContentsScreenState();
}

class _CacheContentsScreenState extends State<CacheContentsScreen> {
  Map<String, ({String title, String? artist})> _titles = const {};
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    SongCatalogScope.of(context).ensureLoaded();
    final library = YouTubeLibraryScope.of(context);
    library
        .knownTitles([for (final e in library.cacheEntries) e.videoId])
        .then((titles) {
          if (mounted) setState(() => _titles = titles);
        })
        .catchError(
          (Object e) => debugPrint('Reading cached titles failed: $e'),
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final library = YouTubeLibraryScope.of(context);
    final catalog = SongCatalogScope.of(context);
    final local = LocalLibraryScope.of(context);
    final entries = library.cacheEntries;

    SearchHit hitFor(String videoId) {
      final phoneMatched = library.songForVideo(videoId);
      final song =
          catalog.findByYouTubeId(videoId) ??
          (phoneMatched == null ? null : catalog.byId(phoneMatched));
      if (song != null) {
        return SearchHit.main(
          song,
          local.filesOf(song.id),
          phoneMatch: song.youtubeVideoId == null ? videoId : null,
        );
      }
      final known = _titles[videoId];
      return SearchHit.youTubeOnly(
        title: known?.title ?? 'Film z YouTube',
        artistLabel: known?.artist ?? videoId,
        videoId: videoId,
      );
    }

    final hits = [for (final e in entries) hitFor(e.videoId)];
    String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Pamięć podręczna'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              entries.isEmpty
                  ? 'Pamięć podręczna jest pusta.'
                  : 'Utwory: ${entries.length}, ${mb(library.cachedBytes)} MB • '
                        'od ostatnio słuchanych',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
          for (final (i, entry) in entries.indexed)
            SongTile(
              key: ValueKey(entry.videoId),
              hit: hits[i],
              queue: hits,
              queueIndex: i,
              subtitle: '${hits[i].artistLabel} • ${mb(entry.sizeBytes)} MB',
              trailing: IconButton(
                tooltip: 'Usuń z pamięci podręcznej',
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: palette.textSecondary,
                ),
                onPressed: () => library.removeFromCache(entry.videoId),
              ),
            ),
        ],
      ),
    );
  }
}
