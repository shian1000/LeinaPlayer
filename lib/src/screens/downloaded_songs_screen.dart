import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/server_downloads.dart';
import '../data/song_catalog.dart';
import '../data/text_normalizer.dart';
import '../data/youtube_library.dart';
import '../playback/downloads.dart';
import '../theme.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_names.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';

/// "Pamięć podręczna › Pobrane utwory": the songs kept with "Pobierz", by title. Tapping one plays
/// it and then the rest of the list; ⊖ or dragging it left takes it out of the downloads. A server
/// file music.db no longer has a song for can't be played, so it's listed by its file name, to be
/// removed.
class DownloadedSongsScreen extends StatefulWidget {
  const DownloadedSongsScreen({super.key});

  @override
  State<DownloadedSongsScreen> createState() => _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState extends State<DownloadedSongsScreen> {
  final _askedTitles = <String>{};
  Map<String, ({String title, String? artist})> _titles = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongCatalogScope.of(context).ensureLoaded();
    // Runs again when a download started earlier finishes while the list is open.
    final videoIds = [
      for (final e in DownloadsScope.maybeOf(context)!.youTubeEntries)
        if (_askedTitles.add(e.videoId)) e.videoId,
    ];
    if (videoIds.isEmpty) return;
    YouTubeLibraryScope.of(context)
        .knownTitles(videoIds)
        .then((titles) {
          if (mounted) setState(() => _titles = {..._titles, ...titles});
        })
        .catchError(
          (Object e) => debugPrint('Reading downloaded titles failed: $e'),
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final downloads = DownloadsScope.maybeOf(context)!;
    final catalog = SongCatalogScope.of(context);
    final local = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final byFile = <int, CatalogSong>{
      if (downloads.serverEntries.isNotEmpty)
        for (final song in catalog.songs)
          if (song.serverFile case final file?) file.id: song,
    };

    final songs = <_DownloadedSong>[];
    final orphans = <ServerDownload>[];
    for (final download in downloads.serverEntries) {
      final song = byFile[download.fileId];
      if (song == null) {
        orphans.add(download);
      } else {
        songs.add((
          hit: SearchHit.main(song, local.filesOf(song.id)),
          key: 'file-${download.fileId}',
          sizeBytes: download.sizeBytes,
          remove: () => downloads.removeServerFile(download.fileId),
        ));
      }
    }
    for (final entry in downloads.youTubeEntries) {
      songs.add((
        hit: hitForStoredVideo(
          entry.videoId,
          catalog,
          local,
          youTube,
          _titles[entry.videoId],
        ),
        key: 'video-${entry.videoId}',
        sizeBytes: entry.sizeBytes,
        remove: () => downloads.removeVideo(entry.videoId),
      ));
    }
    songs.sort(
      (a, b) =>
          compareNames(a.hit.shownTitle(context), b.hit.shownTitle(context)),
    );
    final hits = [for (final song in songs) song.hit];
    String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

    Widget removeButton(VoidCallback onPressed) => IconButton(
      tooltip: 'Usuń z pobranych',
      icon: Icon(Icons.remove_circle_outline, color: palette.textSecondary),
      onPressed: onPressed,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Pobrane utwory'),
      ),
      body: SongSelectionArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                downloads.count == 0
                    ? 'Nie ma pobranych utworów.'
                    : 'Utwory: ${downloads.count}, ${mb(downloads.bytes)} MB',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: AppFontSize.small,
                ),
              ),
            ),
            for (final (i, song) in songs.indexed)
              SongTile(
                key: ValueKey(song.key),
                hit: song.hit,
                queue: hits,
                queueIndex: i,
                subtitle:
                    '${song.hit.shownArtist(context)} • ${mb(song.sizeBytes)} MB',
                trailing: removeButton(song.remove),
                onSwipeRemove: song.remove,
                swipeRemoveLabel: 'Usuń z pobranych',
              ),
            for (final download in orphans)
              ListTile(
                key: ValueKey('file-${download.fileId}'),
                leading: const Icon(Icons.audio_file_outlined),
                title: ScrollingText(download.file.uri.pathSegments.last),
                subtitle: Text(
                  'Nie ma go już w bazie • ${mb(download.sizeBytes)} MB',
                ),
                trailing: removeButton(
                  () => downloads.removeServerFile(download.fileId),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _DownloadedSong = ({
  SearchHit hit,
  String key,
  int sizeBytes,
  VoidCallback remove,
});
