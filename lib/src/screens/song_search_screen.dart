import 'dart:async';

import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/playlist_search.dart';
import '../data/spotify_playlist.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../data/youtube_search.dart';
import '../theme.dart';
import '../widgets/collection_cover.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/swipe_actions.dart';
import 'database_source_screen.dart';
import 'playlist_screen.dart';
import 'search_fields_sheet.dart';
import '../data/album_covers.dart';
import '../widgets/song_cover.dart';

/// Song search over the downloaded MusicDatabase (`music.db`), opened from the
/// "Czego chcesz posłuchać?" field on the Wyszukaj tab. Results — songs and Biblioteka
/// playlists — update on every keystroke; YouTube (videos, playlists) and Spotify (playlists)
/// are searched only with the button.
class SongSearchScreen extends StatefulWidget {
  const SongSearchScreen({super.key});

  @override
  State<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends State<SongSearchScreen> {
  final _query = TextEditingController();

  /// The last online search (the button); dropped as soon as the query changes.
  _OnlineResults? _online;

  void _onQueryChanged() {
    setState(() {
      if (_online?.query != _query.text.trim()) _online = null;
    });
  }

  /// Searches whatever the settings switch on — YouTube videos, YouTube playlists, Spotify
  /// playlists — all at once; each section shows its results as they come.
  Future<void> _searchOnline() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    final search = YouTubeScope.searchOf(context);
    final spotify = YouTubeScope.spotifyOf(context);
    final settings = SourceSettingsScope.of(context);
    final pending = _OnlineResults(
      query,
      videos: settings.youTubeSearchEnabled ? _Pending() : null,
      youTubePlaylists: settings.searchesYouTubePlaylists ? _Pending() : null,
      spotifyPlaylists: settings.searchesSpotifyPlaylists ? _Pending() : null,
    );
    setState(() => _online = pending);

    Future<void> run<T>(_Pending<T>? slot, Future<T> Function() work) async {
      if (slot == null) return;
      try {
        slot.value = await work();
      } on YouTubeSearchException catch (e) {
        slot.error = e.message;
      } on SpotifyException catch (e) {
        slot.error = e.message;
      } catch (e) {
        debugPrint('Online search for "$query" failed: $e');
        slot.error = 'Wyszukiwanie się nie udało.';
      }
      if (mounted && _online == pending) setState(() {});
    }

    await Future.wait([
      run(pending.videos, () => search.search(query, settings)),
      run(
        pending.youTubePlaylists,
        () => search.searchPlaylists(query, settings),
      ),
      run(
        pending.spotifyPlaylists,
        () => spotify.search(query, apiKey: settings.spotifyApiKey),
      ),
    ]);
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
        online: _online,
        onSearchOnline: _searchOnline,
      ),
    );
  }
}

/// One part of an online search: loading until [value] or [error] is set.
class _Pending<T> {
  T? value;
  String? error;

  bool get loading => value == null && error == null;
}

/// One press of the online search button; a part is `null` when it wasn't searched.
class _OnlineResults {
  _OnlineResults(
    this.query, {
    this.videos,
    this.youTubePlaylists,
    this.spotifyPlaylists,
  });

  final String query;
  final _Pending<List<YouTubeVideo>>? videos;
  final _Pending<List<FoundPlaylist>>? youTubePlaylists;
  final _Pending<List<FoundPlaylist>>? spotifyPlaylists;
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.online,
    required this.onSearchOnline,
  });

  final String query;
  final _OnlineResults? online;
  final VoidCallback onSearchOnline;

  @override
  Widget build(BuildContext context) {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final settings = SourceSettingsScope.of(context);
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
    final youTube = settings.youTubeSearchEnabled;
    final spotify = settings.searchesSpotifyPlaylists;
    final onlineSection = youTube || spotify
        ? _OnlineSection(
            results: online,
            query: query.trim(),
            youTube: youTube,
            spotify: spotify,
            onSearch: onSearchOnline,
          )
        : null;
    final playlists = settings.playlistSearch
        ? searchSavedPlaylists(
            query,
            PlaylistLibraryScope.of(context).playlists,
          )
        : const <PlaylistSummary>[];
    if (results.isEmpty && playlists.isEmpty && onlineSection == null) {
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
    final leading = [
      ?onlineSection,
      if (playlists.isNotEmpty) ...[
        _SectionLabel('Playlisty w Bibliotece: ${playlists.length}'),
        for (final playlist in playlists) _SavedPlaylistTile(playlist),
      ],
      header,
    ];
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
              menuIdPrefix: 'Wyszukaj › Utwór › Menu (⋮)',
            ),
    );
  }
}

/// Top of the results while YouTube search or Spotify playlist search is on: the button, then
/// what it found — YouTube and Spotify playlists, then YouTube videos. Nothing online is
/// searched while typing.
class _OnlineSection extends StatelessWidget {
  const _OnlineSection({
    required this.results,
    required this.query,
    required this.youTube,
    required this.spotify,
    required this.onSearch,
  });

  final _OnlineResults? results;
  final String query;

  /// What the button searches: YouTube (videos, maybe playlists), Spotify playlists.
  final bool youTube;
  final bool spotify;
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
          icon: Icon(
            youTube && spotify
                ? Icons.travel_explore
                : youTube
                ? Icons.smart_display_outlined
                : Icons.queue_music,
          ),
          label: Text(
            youTube && spotify
                ? 'Wyszukaj na YouTubie i Spotify'
                : youTube
                ? 'Wyszukaj na YouTubie'
                : 'Wyszukaj playlisty na Spotify',
          ),
          onPressed: onSearch,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (results.youTubePlaylists case final part?)
          ..._part(
            context,
            part,
            label: 'Playlisty na YouTube',
            empty: 'Brak playlist na YouTube dla „$query”',
            found: (playlists) => [_PlaylistRow(playlists)],
          ),
        if (results.spotifyPlaylists case final part?)
          ..._part(
            context,
            part,
            label: 'Playlisty na Spotify',
            empty: 'Brak playlist na Spotify dla „$query”',
            found: (playlists) => [_PlaylistRow(playlists)],
          ),
        if (results.videos case final part?)
          ..._part(
            context,
            part,
            label: 'YouTube',
            empty: 'Brak wyników na YouTube dla „$query”',
            found: (videos) => [
              for (final video in videos)
                _YouTubeTile(video: video, query: query),
            ],
          ),
        const Divider(height: 16),
      ],
    );
  }

  /// A labelled part: spinner, error with retry, "nothing found", or [found]'s widgets.
  List<Widget> _part<T extends List<Object>>(
    BuildContext context,
    _Pending<T> part, {
    required String label,
    required String empty,
    required List<Widget> Function(T) found,
  }) {
    final value = part.value;
    return [
      _SectionLabel(value == null ? label : '$label: ${value.length}'),
      if (part.loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        )
      else if (part.error != null)
        ListTile(
          leading: Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(part.error!),
          trailing: IconButton(
            tooltip: 'Spróbuj ponownie',
            icon: const Icon(Icons.refresh),
            onPressed: onSearch,
          ),
        )
      else if (value!.isEmpty)
        ListTile(leading: const Icon(Icons.search_off), title: Text(empty))
      else
        ...found(value),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: context.palette.textSecondary,
          fontSize: AppFontSize.small,
        ),
      ),
    );
  }
}

/// Playlists found online, as a row of covers scrolled sideways (they'd push the songs far
/// down as a list). A tap opens the playlist's preview.
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow(this.playlists);

  final List<FoundPlaylist> playlists;

  static const _cover = 132.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: _cover + 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final playlist = playlists[i];
          final count = playlist.trackCount;
          return InkWell(
            borderRadius: palette.radius(4),
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlaylistScreen.preview(found: playlist),
                ),
              );
            },
            child: SizedBox(
              width: _cover,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumbnail(playlist: playlist, size: _cover),
                  const SizedBox(height: 6),
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.small,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    [
                      ?playlist.owner,
                      ?(count == null ? null : '$count utw.'),
                    ].join(' • '),
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
          );
        },
      ),
    );
  }
}

/// The playlist's picture from YouTube / Spotify (a video thumbnail is cropped square), or the
/// usual placeholder.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.playlist, required this.size});

  final FoundPlaylist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = CoverArt(
      seed: playlist.name,
      size: size,
      icon: Icons.queue_music,
    );
    final url = playlist.thumbnail;
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: context.palette.radius(4),
      child: Image.network(
        url.toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        frameBuilder: (_, child, frame, loaded) =>
            loaded || frame != null ? child : placeholder,
      ),
    );
  }
}

/// A Biblioteka playlist matching the query, like the rows in Biblioteka.
class _SavedPlaylistTile extends StatelessWidget {
  const _SavedPlaylistTile(this.playlist);

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: PlaylistCover(playlist: playlist, size: SongTile.coverSize),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        ['Playlista', ?playlist.owner].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        FocusScope.of(context).unfocus();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaylistScreen(playlist: playlist),
          ),
        );
      },
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
    final tile = ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      onLongPress: () =>
          showSongMenu(context, hit, idPrefix: 'Wyszukaj › Utwór › Menu (⋮)'),
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
    return SwipeActions(
      right: SwipeAction(
        icon: Icons.queue_music,
        label: 'Dodaj do kolejki',
        onTriggered: () => addToQueue(context, hit),
      ),
      child: tile,
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
