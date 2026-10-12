import 'dart:async';

import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/local_library.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../data/youtube_search.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';
import 'database_source_screen.dart';
import 'search_fields_sheet.dart';
import '../data/album_covers.dart';
import '../widgets/song_cover.dart';

/// Song search over the downloaded MusicDatabase (`music.db`), opened from the
/// "Czego chcesz posłuchać?" field on the Wyszukaj tab. Results update on every keystroke.
class SongSearchScreen extends StatefulWidget {
  const SongSearchScreen({super.key});

  @override
  State<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends State<SongSearchScreen> {
  final _query = TextEditingController();

  /// The last "Wyszukaj na YouTubie" search; dropped as soon as the query changes.
  _YouTubeResults? _youTube;

  void _onQueryChanged() {
    setState(() {
      if (_youTube?.query != _query.text.trim()) _youTube = null;
    });
  }

  Future<void> _searchYouTube() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    final search = YouTubeScope.searchOf(context);
    final settings = SourceSettingsScope.of(context);
    final pending = _YouTubeResults(query);
    setState(() => _youTube = pending);
    try {
      pending.videos = await search.search(query, settings);
    } on YouTubeSearchException catch (e) {
      pending.error = e.message;
    }
    if (mounted && _youTube == pending) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongCatalogScope.of(context).ensureLoaded();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Wstecz',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          cursorColor: palette.accent,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: AppFontSize.listTitle,
          ),
          decoration: InputDecoration(
            hintText: 'Czego chcesz posłuchać?',
            hintStyle: TextStyle(color: palette.textSecondary),
            border: InputBorder.none,
          ),
          onChanged: (_) => _onQueryChanged(),
        ),
        actions: [
          const SearchFieldsButton(),
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: 'Wyczyść',
              icon: const Icon(Icons.close),
              onPressed: () {
                _query.clear();
                _onQueryChanged();
              },
            ),
        ],
      ),
      body: _Results(
        query: _query.text,
        youTube: _youTube,
        onSearchYouTube: _searchYouTube,
      ),
    );
  }
}

/// State of one "Wyszukaj na YouTubie" search: loading until [videos] or [error] is set.
class _YouTubeResults {
  _YouTubeResults(this.query);

  final String query;
  List<YouTubeVideo>? videos;
  String? error;

  bool get loading => videos == null && error == null;
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.youTube,
    required this.onSearchYouTube,
  });

  final String query;
  final _YouTubeResults? youTube;
  final VoidCallback onSearchYouTube;

  @override
  Widget build(BuildContext context) {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final youTubeEnabled = SourceSettingsScope.of(context).youTubeSearchEnabled;
    final mainReady = catalog.status == CatalogStatus.ready;

    // Without MusicDatabase's file, phone songs can still be searched; only explain the missing
    // database when there's nothing at all to search.
    if (!mainReady && library.songCount == 0) {
      switch (catalog.status) {
        case CatalogStatus.notLoaded || CatalogStatus.loading:
          return const _Message(
            icon: Icons.hourglass_empty,
            title: 'Wczytywanie bazy danych…',
            busy: true,
          );
        case CatalogStatus.noDatabase:
          if (sync.downloading) {
            return const _Message(
              icon: Icons.cloud_download_outlined,
              title: 'Trwa pobieranie bazy danych…',
              busy: true,
            );
          }
          return _Message(
            icon: Icons.storage_outlined,
            title: 'Brak pobranej bazy danych',
            details: !sync.hasSource
                ? 'Ustaw adres bazy w Ustawienia › Źródła muzyki › Baza danych.'
                : (sync.lastError ?? 'Baza nie została jeszcze pobrana.'),
            action: _OpenDatabaseSettings(),
          );
        case CatalogStatus.error:
          return _Message(
            icon: Icons.error_outline,
            title: 'Nie udało się odczytać bazy danych',
            details: 'Spróbuj pobrać ją ponownie.',
            action: _OpenDatabaseSettings(),
          );
        case CatalogStatus.ready:
          break;
      }
    }

    if (query.trim().isEmpty) {
      final total = (mainReady ? catalog.songCount : 0) + library.pendingCount;
      return _Message(
        icon: Icons.search,
        title: 'Szukaj wśród $total utworów',
        details: 'Wpisz tytuł utworu albo wykonawcę.',
      );
    }
    final youTubeLibrary = YouTubeLibraryScope.of(context);
    final results = searchEverywhere(
      query,
      catalog,
      library,
      youTube: youTubeLibrary,
    );
    final youTubeSection = youTubeEnabled
        ? _YouTubeSection(
            results: youTube,
            query: query.trim(),
            onSearch: onSearchYouTube,
          )
        : null;
    if (results.isEmpty && youTubeSection == null) {
      return _Message(
        icon: Icons.search_off,
        title: 'Brak wyników dla „${query.trim()}”',
      );
    }
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        results.isEmpty
            ? 'Brak utworów dla „${query.trim()}” w bazie i na telefonie'
            : 'Utwory: ${results.length}',
        style: TextStyle(
          color: context.palette.textSecondary,
          fontSize: AppFontSize.small,
        ),
      ),
    );
    final leading = [?youTubeSection, header];
    return ListView.builder(
      itemCount: results.length + leading.length,
      itemBuilder: (context, i) => i < leading.length
          ? leading[i]
          : SongTile(
              hit: results[i - leading.length],
              searchQuery: query.trim(),
              trailing: SongMenuButton(
                hit: results[i - leading.length],
                idPrefix: 'Wyszukaj › Utwór › Menu (⋮)',
              ),
            ),
    );
  }
}

/// Top of the results while YouTube search is on: the "Wyszukaj na YouTubie" button, then what
/// it found. YouTube is only searched on request, never while typing.
class _YouTubeSection extends StatelessWidget {
  const _YouTubeSection({
    required this.results,
    required this.query,
    required this.onSearch,
  });

  final _YouTubeResults? results;
  final String query;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final results = this.results;
    if (results == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.textPrimary,
            shape: palette.pillShape,
            side: BorderSide(color: palette.outline ?? palette.textSecondary),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.smart_display_outlined),
          label: const Text('Wyszukaj na YouTubie'),
          onPressed: onSearch,
        ),
      );
    }
    final videos = results.videos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            videos == null ? 'YouTube' : 'YouTube: ${videos.length}',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: AppFontSize.small,
            ),
          ),
        ),
        if (results.loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          )
        else if (results.error != null)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(results.error!),
            trailing: IconButton(
              tooltip: 'Spróbuj ponownie',
              icon: const Icon(Icons.refresh),
              onPressed: onSearch,
            ),
          )
        else if (videos!.isEmpty)
          ListTile(
            leading: const Icon(Icons.search_off),
            title: Text('Brak wyników na YouTube dla „$query”'),
          )
        else
          for (final video in videos) _YouTubeTile(video: video, query: query),
        const Divider(height: 16),
      ],
    );
  }
}

class _YouTubeTile extends StatelessWidget {
  const _YouTubeTile({required this.video, required this.query});

  final YouTubeVideo video;
  final String query;

  @override
  Widget build(BuildContext context) {
    final duration = video.duration;
    final isCurrent =
        PlayerScope.of(context).current?.youtubeVideoId == video.id;
    final hit = SearchHit.youTubeOnly(
      title: video.title,
      artistLabel: video.channel,
      videoId: video.id,
    );
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      trailing: SongMenuButton(
        hit: hit,
        idPrefix: 'Wyszukaj › Utwór › Menu (⋮)',
      ),
      leading: SongCover(
        cover: CoverRequest(
          artist: video.channel,
          title: video.title,
          videoId: video.id,
          seed: video.id,
          searchable: false,
        ),
        size: SongTile.coverSize,
      ),
      title: CurrentTitle(text: video.title, isCurrent: isCurrent),
      subtitle: Text(
        [
          video.channel,
          ?(duration == null ? null : formatDuration(duration)),
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        FocusScope.of(context).unfocus();
        final queue = PlaybackQueueScope.of(context);
        runQueueAction(
          context,
          (onStatus) =>
              queue.start([hit], 0, searchQuery: query, onStatus: onStatus),
        );
      },
    );
  }
}

class _OpenDatabaseSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.textPrimary,
        shape: context.palette.pillShape,
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DatabaseSourceScreen()),
      ),
      child: const Text('Ustawienia bazy danych'),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.details,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? details;
  final Widget? action;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Icon(icon, size: 48, color: palette.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppFontSize.listTitle,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
