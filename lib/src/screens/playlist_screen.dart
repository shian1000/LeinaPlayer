import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/library_folders.dart';
import '../data/local_library.dart';
import '../data/playlist_bookmarks.dart';
import '../data/playlist_library.dart';
import '../data/youtube_account.dart';
import '../data/playlist_search.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/spotify_playlist.dart';
import '../data/text_normalizer.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../data/youtube_playlist.dart';
import '../data/youtube_search.dart';
import '../playback/downloads.dart';
import '../playback/playback_queue.dart';
import '../app_name.dart';
import '../theme.dart';
import '../widgets/collection_cover.dart';
import '../widgets/common.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/share_sheet.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';
import '../widgets/youtube_export_dialog.dart';
import 'missing_tracks_screen.dart';
import 'playlist_add_screen.dart';
import 'playlist_edit_screen.dart';
import '../widgets/song_names.dart';

const _id = 'Playlista';

/// One of the user's playlists (Biblioteka › playlist), laid out like a playlist in the
/// reference app; its tracks are rows like the song search's, with the same source icons.
///
/// [PlaylistScreen.preview] shows a playlist found by search instead: fetched from YouTube or
/// Spotify and playable, but not saved until "Zapisz w Bibliotece" (user's decision).
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required PlaylistSummary this.playlist,
    this.reveal,
  }) : found = null;

  const PlaylistScreen.preview({super.key, required FoundPlaylist this.found})
    : playlist = null,
      reveal = null;

  final PlaylistSummary? playlist;
  final FoundPlaylist? found;

  /// A song to jump to (from "Ostatnie"); otherwise the song playing, if it's from here.
  final TrackRef? reveal;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

/// "Sortuj" on a saved playlist: how its tracks are listed and played, kept on the phone for
/// each playlist. "Ostatnio dodane" only for one made on the phone — an imported one's order is
/// its source's.
enum _TrackSort {
  own('Własna kolejność'),
  recent('Ostatnio dodane'),
  title('Tytuł'),
  artist('Wykonawca');

  const _TrackSort(this.label);

  final String label;
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  /// As listed: [_ownOrder] in the order "Sortuj" picked.
  List<PlaylistTrack>? _tracks;
  List<PlaylistTrack>? _ownOrder;
  _TrackSort _sort = _TrackSort.own;
  bool _loading = false;

  /// The Biblioteka playlist shown; for a preview, `null` until it's saved.
  late PlaylistSummary? _saved = widget.playlist;

  /// A preview's playlist as fetched ([YouTubePlaylistData] or [SpotifyPlaylistData]), kept to
  /// save it without fetching again.
  Object? _fetched;
  String? _fetchError;
  bool _saving = false;

  /// Once the header has scrolled away the app bar turns solid and shows the name, as in the
  /// reference app (until then it's transparent over the cover).
  final _scroll = ScrollController();
  final _firstRowKey = GlobalKey();
  bool _headerHidden = false;

  /// Searching within this playlist: the app bar becomes a search field and only matching
  /// tracks are listed. It's a local history entry, so Back (the arrow or the system one, which
  /// `AppShell` turns into a plain `pop`) closes the search before leaving the playlist.
  LocalHistoryEntry? _searchEntry;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.playlist case final playlist?) {
      final folders = LibraryFoldersScope.read(context);
      // Not while building: Biblioteka, under this screen, reorders itself.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => folders?.opened(LibraryFolders.playlistKey(playlist.id)),
      );
    }
    _scroll.addListener(() {
      final hidden = _scroll.offset > 300;
      if (hidden != _headerHidden) setState(() => _headerHidden = hidden);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    // music.db is otherwise only read once search is opened; tracks need it for their icons.
    SongCatalogScope.of(context).ensureLoaded();
    _load();
  }

  Future<void> _load() async {
    final saved = _saved;
    if (saved == null) return _fetch();
    final library = PlaylistLibraryScope.of(context);
    final tracks = await library.tracks(saved.id);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // Its track count and length change with "Dodaj" / "Edytuj".
      _saved = library.byId(saved.id) ?? saved;
      _sort =
          _TrackSort.values.asNameMap()[prefs.getString(_sortKey(saved))] ??
          _TrackSort.own;
      _ownOrder = tracks;
      _tracks = _sorted(tracks);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  static String _sortKey(PlaylistSummary playlist) =>
      'playlist.sort.${playlist.uid ?? playlist.id}';

  /// A playlist made on the phone: songs can be added to it and it can be edited.
  bool get _editable => _saved != null && _saved!.source == null;

  List<PlaylistTrack> _sorted(List<PlaylistTrack> tracks) {
    int byTitle(PlaylistTrack a, PlaylistTrack b) =>
        compareNames(a.title, b.title);
    int byArtist(PlaylistTrack a, PlaylistTrack b) =>
        compareNames(a.artist, b.artist);
    return switch (_sort) {
      _TrackSort.own => tracks,
      _TrackSort.recent => tracks.reversed.toList(),
      _TrackSort.title =>
        [...tracks]..sort((a, b) {
          final c = byTitle(a, b);
          return c != 0 ? c : byArtist(a, b);
        }),
      _TrackSort.artist =>
        [...tracks]..sort((a, b) {
          final c = byArtist(a, b);
          return c != 0 ? c : byTitle(a, b);
        }),
    };
  }

  void _showSortSheet() {
    final saved = _saved;
    if (saved == null) return;
    showMenuSheet(
      context,
      idPrefix: '$_id › Sortuj',
      header: const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Center(
          child: Text(
            'Sortuj wg',
            style: TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      entries: [
        for (final option in _TrackSort.values)
          if (option != _TrackSort.recent || _editable)
            MenuSheetEntry(
              option == _sort ? Icons.check : Icons.circle_outlined,
              option.label,
              onTap: () async {
                setState(() {
                  _sort = option;
                  if (_ownOrder case final own?) _tracks = _sorted(own);
                });
                await (await SharedPreferences.getInstance()).setString(
                  _sortKey(saved),
                  option.name,
                );
              },
            ),
      ],
    );
  }

  void _openAdd(List<SearchHit> hits) {
    final saved = _saved;
    if (saved == null) return;
    PlaylistAddScreen.open(
      context,
      playlist: saved,
      present: {for (final hit in hits) SongSelection.keyOf(hit)},
      onAdded: () {
        if (mounted) _load();
      },
    );
  }

  void _openEdit() {
    final saved = _saved;
    final own = _ownOrder;
    if (saved == null || own == null) return;
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    PlaylistEditScreen.open(
      context,
      playlist: saved,
      tracks: [
        for (final track in own)
          (track, playlistHit(track, catalog, library, youTube)),
      ],
      onSaved: () {
        if (mounted) _load();
      },
    );
  }

  /// Reads a preview's playlist from YouTube or Spotify.
  Future<void> _fetch() async {
    final found = widget.found!;
    final library = PlaylistLibraryScope.of(context);
    final settings = SourceSettingsScope.of(context);
    final youTube = YouTubeScope.playlistsOf(context);
    final spotify = YouTubeScope.spotifyOf(context);
    // A retry: the first fetch starts from these already.
    if (_fetchError != null) {
      setState(() {
        _tracks = null;
        _fetchError = null;
      });
    }
    try {
      switch (found.source) {
        case PlaylistSource.youtube:
          final data = await youTube.fetch(found.id, settings);
          final tracks = await library.previewYouTube(data);
          if (!mounted) return;
          setState(() {
            _fetched = data;
            _tracks = tracks;
          });
        case PlaylistSource.spotify || PlaylistSource.spotifyAlbum:
          final data = found.source == PlaylistSource.spotifyAlbum
              ? await spotify.fetchAlbum(found.id)
              : await spotify.fetch(found.id);
          final tracks = await library.previewSpotify(data);
          if (!mounted) return;
          setState(() {
            _fetched = data;
            _tracks = tracks;
          });
        // Search finds only YouTube and Spotify playlists.
        case PlaylistSource.folder:
          throw StateError('No preview for a folder playlist');
      }
    } on YouTubeSearchException catch (e) {
      if (mounted) setState(() => _fetchError = e.message);
    } on SpotifyException catch (e) {
      if (mounted) setState(() => _fetchError = e.message);
    } catch (e) {
      debugPrint('Previewing playlist ${found.id} failed: $e');
      if (mounted) {
        setState(() => _fetchError = 'Nie udało się wczytać playlisty.');
      }
    }
  }

  /// Saves a preview to Biblioteka (or updates the copy already there) and goes on showing the
  /// saved playlist.
  Future<void> _saveToLibrary() async {
    final fetched = _fetched;
    if (fetched == null || _saving) return;
    final library = PlaylistLibraryScope.of(context);
    final settings = SourceSettingsScope.of(context);
    final youTubeSearch = YouTubeScope.searchOf(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final result = switch (fetched) {
        YouTubePlaylistData() => await library.importYouTube(
          fetched,
          videoExists: (id) => youTubeSearch.videoExists(id, settings),
        ),
        SpotifyPlaylistData() => await library.importSpotify(fetched),
        _ => throw ArgumentError.value(fetched),
      };
      if (!mounted) return;
      setState(() {
        _saved = result.playlist;
        _fetched = null;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.updated ? 'Zaktualizowano' : 'Zapisano'} „${result.playlist.name}” '
            'w Bibliotece.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      debugPrint('Saving playlist failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się zapisać playlisty.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Opening the playlist jumps to [PlaylistScreen.reveal] or else the song playing (when it
  /// plays from here), third from the top, like the reference app.
  void _reveal() {
    final tracks = _tracks;
    if (tracks == null || !_scroll.hasClients) return;
    final wanted = widget.reveal;
    final playing = PlaybackQueueScope.of(context).currentEntry;
    final index = wanted != null
        ? _indexOf(wanted, tracks)
        : _savedId != null && playing?.origin?.playlistId == _savedId
        ? playing!.index
        : _bookmarkedIndex(tracks);
    if (index == null || index < 0 || index >= tracks.length) return;
    // Rows all have the first one's height; rows far down aren't built yet to measure.
    final first = _firstRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (first == null) return;
    final firstTop = RenderAbstractViewport.of(first)
        .getOffsetToReveal(first, 0)
        .offset;
    // The app bar is drawn over the list.
    final covered = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final target = firstTop + (index - 2) * first.size.height - covered;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
  }

  /// Where [track] is in the playlist: by MusicDatabase song, else video, else title.
  static int _indexOf(TrackRef track, List<PlaylistTrack> tracks) {
    final found = tracks.indexWhere(_sameSong(track));
    return found >= 0
        ? found
        : tracks.indexWhere((t) => t.title == track.title);
  }

  static bool Function(PlaylistTrack) _sameSong(TrackRef track) =>
      track.mainDbId != null
      ? (t) => t.mainDbId == track.mainDbId
      : track.videoId != null
      ? (t) => t.youtubeVideoId == track.videoId
      : (t) => t.title == track.title;

  /// The row of the song last played from this playlist: where it was listed then, unless
  /// "Sortuj" or an edit has moved it since; `null` when there's none or it's gone.
  int? _bookmarkedIndex(List<PlaylistTrack> tracks) {
    final id = _savedId;
    final bookmark = id == null
        ? null
        : PlaylistBookmarksScope.maybeOf(context)?.of(id);
    if (bookmark == null) return null;
    final at = bookmark.index;
    if (at < tracks.length && _sameSong(bookmark.track)(tracks[at])) return at;
    final found = _indexOf(bookmark.track, tracks);
    return found >= 0 ? found : null;
  }

  bool get _searching => _searchEntry != null;

  void _startSearch() {
    final entry = LocalHistoryEntry(
      onRemove: () {
        if (!mounted) return;
        setState(() {
          _searchEntry = null;
          _query.clear();
        });
      },
    );
    ModalRoute.of(context)!.addLocalHistoryEntry(entry);
    setState(() => _searchEntry = entry);
  }

  /// For a preview, built from what was found and fetched; its [PlaylistSummary.id] means
  /// nothing — use [_savedId].
  PlaylistSummary get _playlist {
    final saved = _saved;
    if (saved != null) return saved;
    final found = widget.found!;
    final (name, owner) = switch (_fetched) {
      YouTubePlaylistData(:final name, :final owner) => (name, owner),
      SpotifyPlaylistData(:final name, :final owner) => (name, owner),
      _ => (found.name, found.owner),
    };
    // Not a dependency: also read from callbacks, and the screen rebuilds with the catalog anyway.
    final catalog = context
        .getInheritedWidgetOfExactType<SongCatalogScope>()
        ?.notifier;
    final lengths = [
      for (final t in _tracks ?? const <PlaylistTrack>[])
        catalog == null ? t.duration : playlistTrackLength(t, catalog),
    ];
    return PlaylistSummary(
      id: -1,
      name: name,
      owner: owner,
      trackCount: _tracks?.length ?? found.trackCount ?? 0,
      duration: lengths.nonNulls.fold(Duration.zero, (sum, d) => sum + d),
      unknownLengths: lengths.where((d) => d == null).length,
      updatedAt: DateTime.now(),
      source: found.source,
      sourceId: found.id,
    );
  }

  int? get _savedId => _saved?.id;
  bool get _preview => _saved == null;

  /// "Zapisz w Bibliotece", or "Zaktualizuj…" when this playlist was imported before.
  String _saveLabel(BuildContext context) {
    final found = widget.found!;
    return PlaylistLibraryScope.of(context).saved(found.source, found.id) ==
            null
        ? 'Zapisz w Bibliotece'
        : 'Zaktualizuj w Bibliotece';
  }

  bool get _fromSpotify => _playlist.source?.isSpotify ?? false;
  String get _kind =>
      _playlist.source == PlaylistSource.spotifyAlbum ? 'Album' : 'Playlista';
  String get _owner =>
      _playlist.owner ??
      switch (_playlist.source) {
        PlaylistSource.spotify || PlaylistSource.spotifyAlbum => 'Spotify',
        PlaylistSource.folder => 'MusicDatabase',
        PlaylistSource.youtube => 'YouTube',
        // Made on the phone.
        null => _playlist.account ?? appName,
      };

  /// The playlist's cover: the one picked for it, else a collage of [hits]' covers.
  Widget _cover(List<SearchHit> hits, double size) {
    final saved = _saved;
    return CollectionCover(
      // The cover changes in Biblioteka, not in the summary this screen was opened with.
      cover: saved == null
          ? null
          : PlaylistLibraryScope.of(context).byId(saved.id)?.cover,
      songs:
          (_playlist.source == PlaylistSource.spotifyAlbum
                  ? hits.take(1)
                  : hits)
              .map(CoverRequest.of),
      seed: _playlist.name,
      size: size,
    );
  }

  /// Shares the playlist's own page where it was imported from. One made on the phone has no
  /// link until "Utwórz na YouTube" makes a copy of it there.
  void _share(List<SearchHit> hits) {
    final saved = _saved;
    final playlist =
        (saved == null
            ? null
            : PlaylistLibraryScope.of(context).byId(saved.id)) ??
        _playlist;
    final canMake =
        saved != null &&
        (playlist.source == null || playlist.source == PlaylistSource.folder) &&
        (playlist.youTubeCopyId == null || playlist.youTubeCopyUnfinished) &&
        (YouTubeAccountScope.maybeOf(context)?.supported ?? true);
    showLinkShareSheet(
      context,
      link: playlist.link,
      target: playlist.linksToYouTube
          ? ShareTarget.youtube
          : ShareTarget.spotify,
      title: playlist.name,
      subtitle: '$_kind • $_owner',
      cover: _cover(hits, 160),
      tint: context.palette.colorForSeed(playlist.name),
      makeOnYouTube: canMake
          ? () => showYouTubeExportDialog(context, playlist)
          : null,
      unfinished: playlist.youTubeCopyUnfinished,
    );
  }

  Future<void> _rename() async {
    final saved = _saved;
    if (saved == null) return;
    final playlists = PlaylistLibraryScope.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Zmień nazwę playlisty',
        hint: 'Nazwa',
        initial: saved.name,
      ),
    );
    if (name == null) return;
    await playlists.rename(saved.id, name);
    if (!mounted) return;
    setState(() => _saved = playlists.byId(saved.id) ?? saved);
  }

  Future<void> _delete() async {
    final library = PlaylistLibraryScope.of(context);
    final folders = LibraryFoldersScope.maybeOf(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć playlistę?'),
        content: Text(
          _playlist.account == null
              ? '„${_playlist.name}” zniknie z Biblioteki. Utwory w bazie danych i na '
                    'telefonie zostają.'
              : '„${_playlist.name}” zniknie z Biblioteki na wszystkich urządzeniach konta '
                    '${_playlist.account} i z MusicDatabase (zostanie tam kopia w archiwum). '
                    'Utwory w bazie danych i na telefonie zostają.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await library.delete(_playlist.id);
    // A local id may be given to a new playlist later.
    await folders?.move(LibraryFolders.playlistKey(_playlist.id), null);
    navigator.pop();
  }

  void _showMissing() {
    final tracks = _tracks;
    if (tracks == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MissingTracksScreen(
          playlist: _playlist,
          tracks: tracks,
          saved: !_preview,
        ),
      ),
    );
  }

  /// The whole playlist into the queue, remembered as played from it.
  List<MenuSheetEntry> _queueEntries(List<SearchHit> hits) {
    if (hits.isEmpty) return const [];
    QueueOrigin origin() => QueueOrigin(
      playlistId: _savedId,
      youTubeListId: _playlist.youTubeId,
      playlistName: _playlist.name,
    );
    return [
      MenuSheetEntry(
        Icons.queue_music,
        'Dodaj do kolejki',
        onTap: () => queueSongs(context, hits, next: false, origin: origin()),
      ),
      MenuSheetEntry(
        Icons.playlist_play,
        'Odtwórz jako następną',
        onTap: () => queueSongs(context, hits, next: true, origin: origin()),
      ),
    ];
  }

  void _showPlaylistMenu(List<SearchHit> hits) {
    showMenuSheet(
      context,
      idPrefix: '$_id › Menu (⋮)',
      header: MenuSheetHeader(
        cover: _cover(hits, 56),
        title: _playlist.name,
        subtitle: '$_kind • $_owner',
      ),
      entries: _preview
          ? [
              MenuSheetEntry(
                Icons.share_outlined,
                'Udostępnij',
                onTap: () => _share(hits),
              ),
              ..._queueEntries(hits),
              ?moodForAllEntry(context, hits, title: _playlist.name),
              if (_fetched != null)
                MenuSheetEntry(
                  Icons.add_circle_outline,
                  _saveLabel(context),
                  onTap: _saveToLibrary,
                ),
              if (_tracks != null)
                MenuSheetEntry(
                  Icons.rule,
                  'Wyświetl utwory, których nie ma w bazie danych',
                  onTap: _showMissing,
                ),
            ]
          : [
              MenuSheetEntry(
                Icons.share_outlined,
                'Udostępnij',
                onTap: () => _share(hits),
              ),
              ..._queueEntries(hits),
              ?moodForAllEntry(context, hits, title: _playlist.name),
              MenuSheetEntry(
                Icons.check_circle,
                'Usuń z Biblioteki',
                onTap: _delete,
              ),
              MenuSheetEntry(
                Icons.drive_file_rename_outline,
                'Zmień nazwę',
                onTap: _rename,
              ),
              if (_editable) ...[
                MenuSheetEntry(
                  Icons.add,
                  'Dodaj do tej playlisty',
                  onTap: () => _openAdd(hits),
                ),
                MenuSheetEntry(
                  Icons.edit_outlined,
                  'Edytuj playlistę',
                  onTap: _openEdit,
                ),
              ],
              ...customCoverEntries(
                context,
                current: PlaylistLibraryScope.of(context)
                    .byId(_saved!.id)
                    ?.cover,
                onSet: (hash) =>
                    PlaylistLibraryScope.of(context).setCover(_saved!.id, hash),
              ),
              MenuSheetEntry(
                Icons.rule,
                'Wyświetl utwory, których nie ma w bazie danych',
                onTap: _showMissing,
              ),
              ?playlistMenuEntry(
                context,
                hits,
                label: 'Dodaj do innej playlisty',
              ),
              ?moveToFolderEntry(
                context,
                LibraryFolders.playlistKey(_saved!.id),
              ),
            ],
    );
  }

  Future<void> _removeTrack(int index) async {
    final saved = _saved;
    final tracks = _tracks;
    if (saved == null || tracks == null || index >= tracks.length) return;
    final playlists = PlaylistLibraryScope.of(context);
    await playlists.removeTrack(saved.id, tracks[index].position);
    if (!mounted) return;
    setState(() => _saved = playlists.byId(saved.id) ?? saved);
    await _load();
  }

  void _showTrackMenu(SearchHit hit, int index) {
    showSongMenu(
      context,
      hit,
      idPrefix: '$_id › Utwór › Menu (⋮)',
      extra: [
        if (!_preview)
          MenuSheetEntry(
            Icons.remove_circle_outline,
            'Usuń z tej playlisty',
            onTap: () => _removeTrack(index),
          ),
      ],
    );
  }

  PreferredSizeWidget _searchBar(AppPalette palette, Color tint) => AppBar(
    backgroundColor: Color.lerp(tint, palette.background, 0.4),
    leading: IconButton(
      tooltip: 'Zamknij wyszukiwanie',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pop(),
    ),
    titleSpacing: 0,
    title: TextField(
      controller: _query,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: 'Szukaj w playliście',
        border: InputBorder.none,
      ),
    ),
    actions: [
      if (_query.text.isNotEmpty)
        IconButton(
          tooltip: 'Wyczyść',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_query.clear),
        ),
    ],
  );

  /// The playlist's tracks whose title, artist or album contain every word of the query (both
  /// normalised like song search); tapping one still plays on through the whole playlist.
  Widget _searchResults(List<SearchHit> hits) {
    final palette = context.palette;
    final words = normalizeForSearch(_query.text)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final matches = [
      for (final (i, hit) in hits.indexed)
        if (words.every(
          normalizeForSearch(
            [hit.title, hit.artistLabel, hit.album ?? ''].join(' '),
          ).contains,
        ))
          (i, hit),
    ];
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Brak wyników dla „${_query.text.trim()}”',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + kToolbarHeight,
        bottom: 24,
      ),
      children: [
        for (final (i, hit) in matches)
          _trackTile(hits, i, hit, bookmarked: _bookmarkedIndex(_tracks!)),
      ],
    );
  }

  Widget _trackTile(
    List<SearchHit> hits,
    int i,
    SearchHit hit, {
    Key? key,
    int? bookmarked,
  }) => SongTile(
    key: key,
    hit: hit,
    bookmarked: i == bookmarked,
    selectionKey: i,
    // Tapping a track queues the whole playlist, starting at that track.
    queue: hits,
    queueIndex: i,
    playlistId: _savedId,
    youTubeListId: _playlist.youTubeId,
    playlistName: _playlist.name,
    // Like the reference app's playlists: just the artist.
    subtitle: hit.shownArtist(context),
    trailing: IconButton(
      tooltip: 'Menu utworu (⋮)',
      icon: Icon(Icons.more_vert, color: context.palette.textSecondary),
      onPressed: () => _showTrackMenu(hit, i),
    ),
    onLongPress: () => _showTrackMenu(hit, i),
    onSwipeRemove: _preview ? null : () => _swipeRemove(hit, i),
    swipeRemoveLabel: 'Usuń z tej playlisty',
  );

  /// Dragged left: like "Usuń z tej playlisty", saying so.
  Future<void> _swipeRemove(SearchHit hit, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    await _removeTrack(index);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('Usunięto z playlisty: „${hit.title}”')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = palette.colorForSeed(_playlist.name);
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final tracks = _tracks;
    final hits = [
      for (final track in tracks ?? const <PlaylistTrack>[])
        playlistHit(track, catalog, library, youTube),
    ];
    final bookmarked = tracks == null ? null : _bookmarkedIndex(tracks);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _searching
          ? _searchBar(palette, tint)
          : AppBar(
              backgroundColor: _headerHidden
                  ? Color.lerp(tint, palette.background, 0.4)
                  : Colors.transparent,
              title: _headerHidden
                  ? Text(
                      _playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : null,
              leading: IconButton(
                tooltip: 'Wstecz',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  tooltip: 'Szukaj w playliście',
                  icon: const Icon(Icons.search),
                  onPressed: tracks == null ? null : _startSearch,
                ),
                IconButton(
                  tooltip: 'Menu playlisty (⋮)',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showPlaylistMenu(hits),
                ),
              ],
            ),
      // The playlist stays built under the search, so closing it returns to the same place.
      body: SongSelectionArea(
        all: () => {for (final (i, hit) in hits.indexed) i: hit},
        child: IndexedStack(
          index: _searching ? 1 : 0,
          children: [
            ListView(
              controller: _scroll,
              padding: EdgeInsets.zero,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [tint, palette.background],
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.paddingOf(context).top + 56,
                    16,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: _cover(hits, 220)),
                      const SizedBox(height: 20),
                      Text(
                        _playlist.name,
                        style: const TextStyle(
                          fontSize: AppFontSize.largeTitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: palette.accent,
                            child: Text(
                              _owner.characters.first,
                              style: TextStyle(
                                color: palette.onAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _owner,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _fromSpotify
                                ? Icons.graphic_eq
                                : Icons.smart_display_outlined,
                            size: 18,
                            color: palette.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            [
                              trackCountLabel(_playlist.trackCount),
                              if (_playlist.duration > Duration.zero)
                                playlistLengthLabel(_playlist),
                            ].join(' • '),
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                  child: Row(
                    children: [
                      if (!_preview && tracks != null)
                        _DownloadButton(hits: hits, name: _playlist.name),
                      IconButton(
                        tooltip: 'Udostępnij',
                        icon: const Icon(Icons.share_outlined, size: 28),
                        onPressed: () => _share(hits),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Odtwarzanie losowe',
                        icon: Icon(
                          Icons.shuffle,
                          color: palette.accent,
                          size: 30,
                        ),
                        onPressed: hits.isEmpty
                            ? null
                            : () => runQueueAction(
                                context,
                                (onStatus) =>
                                    PlaybackQueueScope.of(context)
                                        .startShuffled(
                                          hits,
                                          playlistId: _savedId,
                                          youTubeListId: _playlist.youTubeId,
                                          playlistName: _playlist.name,
                                          onStatus: onStatus,
                                        ),
                              ),
                      ),
                      const SizedBox(width: 4),
                      FloatingActionButton(
                        heroTag: null,
                        tooltip: 'Odtwórz playlistę',
                        backgroundColor: palette.accent,
                        foregroundColor: palette.onAccent,
                        shape: palette.buttonShape,
                        onPressed: hits.isEmpty
                            ? null
                            : () => runQueueAction(
                                context,
                                (onStatus) =>
                                    PlaybackQueueScope.of(context).start(
                                      hits,
                                      0,
                                      playlistId: _savedId,
                                      youTubeListId: _playlist.youTubeId,
                                      playlistName: _playlist.name,
                                      shuffle: false,
                                      onStatus: onStatus,
                                    ),
                              ),
                        child: const Icon(Icons.play_arrow, size: 36),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    children: _preview
                        ? [
                            _ActionChip(
                              icon: Icons.add,
                              label: _saving
                                  ? 'Zapisuję…'
                                  : _saveLabel(context),
                              onTap: _fetched == null || _saving
                                  ? null
                                  : _saveToLibrary,
                            ),
                          ]
                        : [
                            if (_editable) ...[
                              _ActionChip(
                                icon: Icons.add,
                                label: 'Dodaj',
                                onTap: () => _openAdd(hits),
                              ),
                              _ActionChip(
                                icon: Icons.menu,
                                label: 'Edytuj',
                                onTap: tracks == null ? null : _openEdit,
                              ),
                            ],
                            _ActionChip(
                              icon: Icons.swap_vert,
                              label: _sort == _TrackSort.own
                                  ? 'Sortuj'
                                  : _sort.label,
                              onTap: tracks == null ? null : _showSortSheet,
                            ),
                          ],
                  ),
                ),
                if (_fetchError != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          _fetchError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.textPrimary,
                            shape: palette.pillShape,
                          ),
                          onPressed: _fetch,
                          child: const Text('Spróbuj ponownie'),
                        ),
                      ],
                    ),
                  )
                else if (tracks == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  for (final (i, hit) in hits.indexed)
                    _trackTile(
                      hits,
                      i,
                      hit,
                      key: i == 0 ? _firstRowKey : null,
                      bookmarked: bookmarked,
                    ),
                const SizedBox(height: 24),
              ],
            ),
            if (_searching) _searchResults(hits),
          ],
        ),
      ),
    );
  }
}

/// "1 utwór", "3 utwory", "12 utworów".
String trackCountLabel(int n) {
  final tens = n % 100;
  final word = n == 1
      ? 'utwór'
      : n % 10 >= 2 && n % 10 <= 4 && (tens < 12 || tens > 14)
      ? 'utwory'
      : 'utworów';
  return '$n $word';
}

/// "3 godz. 12 min" / "45 min"; "ponad 3 godz. 12 min" when some tracks' lengths are unknown.
String playlistLengthLabel(PlaylistSummary playlist) {
  final d = playlist.duration;
  final length = d.inHours > 0
      ? '${d.inHours} godz. ${d.inMinutes % 60} min'
      : '${d.inMinutes} min';
  return playlist.unknownLengths > 0 ? 'ponad $length' : length;
}

/// "Pobierz" for the whole playlist: ⬇ downloads every song not on the phone yet, a spinner
/// while it works, a filled mark once all are — tapped then, it asks before taking them off.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.hits, required this.name});

  final List<SearchHit> hits;
  final String name;

  Future<void> _download(BuildContext context, Downloads downloads) async {
    final messenger = ScaffoldMessenger.of(context);
    final missing = hits.where((h) => !downloads.isDownloaded(h)).length;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Pobieram ${trackCountLabel(missing)} z „$name”…'),
        ),
      );
    final failed = await downloads.download(hits);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Pobrano „$name” — zagra też bez internetu.'
                : 'Nie udało się pobrać: ${trackCountLabel(failed)}.',
          ),
        ),
      );
  }

  Future<void> _remove(BuildContext context, Downloads downloads) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć pobrane?'),
        content: Text(
          'Utwory z „$name” przestaną być dostępne bez internetu (muzyka z telefonu '
          'zostaje).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await downloads.remove(hits);
  }

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadsScope.maybeOf(context);
    if (downloads == null) return const SizedBox.shrink();
    final palette = context.palette;
    if (downloads.isDownloadingAny(hits)) {
      return const IconButton(
        tooltip: 'Pobieram…',
        onPressed: null,
        icon: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final state = downloads.stateOf(hits);
    return IconButton(
      tooltip: switch (state) {
        DownloadState.all => 'Pobrano — usuń z pobranych',
        DownloadState.some => 'Pobierz resztę',
        DownloadState.none => 'Pobierz',
      },
      icon: Icon(
        state == DownloadState.all
            ? Icons.download_for_offline
            : Icons.download_for_offline_outlined,
        size: 30,
        color: state == DownloadState.none ? null : palette.accent,
      ),
      onPressed: hits.isEmpty
          ? null
          : state == DownloadState.all
          ? () => _remove(context, downloads)
          : () => _download(context, downloads),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ActionChip(
      avatar: Icon(icon, size: 20, color: palette.accent),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: palette.chip,
      side: palette.outlineSide,
      shape: palette.pillShape,
      onPressed: onTap,
    );
  }
}
