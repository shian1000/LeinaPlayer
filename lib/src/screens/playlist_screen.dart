import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/text_normalizer.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../dummy.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/share_sheet.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_tile.dart';
import 'missing_tracks_screen.dart';

const _id = 'Playlista';

/// One of the user's playlists (Biblioteka › playlist), laid out like a playlist in the
/// reference app; its tracks are rows like the song search's, with the same source icons.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist, this.reveal});

  final PlaylistSummary playlist;

  /// A song to jump to (from "Ostatnie"); otherwise the song playing, if it's from here.
  final TrackRef? reveal;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<PlaylistTrack>? _tracks;
  bool _loading = false;

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
    final tracks = await PlaylistLibraryScope.of(context)
        .tracks(widget.playlist.id);
    if (!mounted) return;
    setState(() => _tracks = tracks);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Opening the playlist jumps to [PlaylistScreen.reveal] or else the song playing (when it
  /// plays from here), third from the top, like the reference app.
  void _reveal() {
    final tracks = _tracks;
    if (tracks == null || !_scroll.hasClients) return;
    final wanted = widget.reveal;
    final queue = PlaybackQueueScope.of(context);
    final index = wanted != null
        ? _indexOf(wanted, tracks)
        : queue.playlistId == _playlist.id
        ? queue.currentContextIndex
        : null;
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
    bool Function(PlaylistTrack) test = track.mainDbId != null
        ? (t) => t.mainDbId == track.mainDbId
        : track.videoId != null
        ? (t) => t.youtubeVideoId == track.videoId
        : (t) => t.title == track.title;
    final found = tracks.indexWhere(test);
    return found >= 0
        ? found
        : tracks.indexWhere((t) => t.title == track.title);
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

  PlaylistSummary get _playlist => widget.playlist;
  bool get _fromSpotify => _playlist.source == PlaylistSource.spotify;
  String get _owner =>
      _playlist.owner ?? (_fromSpotify ? 'Spotify' : 'YouTube');

  /// Shares the playlist's own page where it was imported from — the phone's copy has no link.
  void _share(List<SearchHit> hits) {
    final link = _playlist.link;
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ta playlista jest tylko na telefonie — nie ma linku.'),
        ),
      );
      return;
    }
    showLinkShareSheet(
      context,
      link: link,
      target: _fromSpotify ? ShareTarget.spotify : ShareTarget.youtube,
      title: _playlist.name,
      subtitle: 'Playlista • $_owner',
      cover: _Mosaic(
        covers: [for (final hit in hits.take(4)) CoverRequest.of(hit)],
        fallback: _playlist.name,
        size: 160,
      ),
      tint: context.palette.colorForSeed(_playlist.name),
    );
  }

  Future<void> _delete() async {
    final library = PlaylistLibraryScope.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć playlistę?'),
        content: Text(
          '„${_playlist.name}” zniknie z Biblioteki. Utwory w bazie danych i na telefonie '
          'zostają.',
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
    navigator.pop();
  }

  void _showMissing() {
    final tracks = _tracks;
    if (tracks == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MissingTracksScreen(playlist: _playlist, tracks: tracks),
      ),
    );
  }

  void _showPlaylistMenu(List<SearchHit> hits) {
    showMenuSheet(
      context,
      idPrefix: '$_id › Menu (⋮)',
      header: MenuSheetHeader(
        cover: CoverArt(seed: _playlist.name, size: 56),
        title: _playlist.name,
        subtitle: 'Playlista • $_owner',
      ),
      entries: [
        MenuSheetEntry(
          Icons.share_outlined,
          'Udostępnij',
          onTap: () => _share(hits),
        ),
        MenuSheetEntry(Icons.check_circle, 'Usuń z Biblioteki', onTap: _delete),
        const MenuSheetEntry(Icons.add, 'Dodaj do tej playlisty'),
        const MenuSheetEntry(Icons.edit_outlined, 'Edytuj playlistę'),
        MenuSheetEntry(
          Icons.rule,
          'Wyświetl utwory, których nie ma w bazie danych',
          onTap: _showMissing,
        ),
        const MenuSheetEntry(Icons.playlist_add, 'Dodaj do innej playlisty'),
        const MenuSheetEntry(
          Icons.drive_file_move_outline,
          'Przenieś do folderu',
        ),
        const MenuSheetEntry(Icons.qr_code, 'Pokaż kod playlisty'),
      ],
    );
  }

  void _showTrackMenu(SearchHit hit) {
    showMenuSheet(
      context,
      idPrefix: '$_id › Utwór › Menu (⋮)',
      header: MenuSheetHeader(
        cover: SongCover(cover: CoverRequest.of(hit)),
        title: hit.title,
        subtitle: hit.artistLabel,
      ),
      entries: [
        MenuSheetEntry(
          Icons.share_outlined,
          'Udostępnij',
          onTap: () => showSongShareSheet(
            context,
            hit,
            idPrefix: '$_id › Utwór › Menu (⋮)',
          ),
        ),
        const MenuSheetEntry(
          Icons.add_circle_outline,
          'Dodaj do Polubionych utworów',
        ),
        const MenuSheetEntry(Icons.playlist_add, 'Dodaj do playlisty'),
        const MenuSheetEntry(
          Icons.remove_circle_outline,
          'Usuń z tej playlisty',
        ),
        MenuSheetEntry(
          Icons.queue_music,
          'Dodaj do kolejki',
          onTap: () => addToQueue(context, hit),
        ),
        const MenuSheetEntry(Icons.album_outlined, 'Przejdź do albumu'),
        const MenuSheetEntry(Icons.person_outline, 'Przejdź do wykonawców'),
        const MenuSheetEntry(Icons.radio, 'Przejdź do radia utworu'),
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
      children: [for (final (i, hit) in matches) _trackTile(hits, i, hit)],
    );
  }

  Widget _trackTile(List<SearchHit> hits, int i, SearchHit hit, {Key? key}) =>
      SongTile(
        key: key,
        hit: hit,
        // Tapping a track queues the whole playlist, starting at that track.
        queue: hits,
        queueIndex: i,
        playlistId: _playlist.id,
        youTubeListId: _playlist.youTubeId,
        playlistName: _playlist.name,
        // Like the reference app's playlists: just the artist.
        subtitle: hit.artistLabel,
        trailing: IconButton(
          tooltip: 'Menu utworu (⋮)',
          icon: Icon(Icons.more_vert, color: context.palette.textSecondary),
          onPressed: () => _showTrackMenu(hit),
        ),
      );

  @override
  Widget build(BuildContext context) {
    void dummy(String label) => showDummy(context, '$_id › $label');
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
      body: IndexedStack(
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
                    Center(
                      child: _Mosaic(
                        covers: [
                          for (final hit in hits.take(4)) CoverRequest.of(hit),
                        ],
                        fallback: _playlist.name,
                        size: 220,
                      ),
                    ),
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
                            _trackCount(_playlist.trackCount),
                            if (_playlist.duration > Duration.zero)
                              _length(_playlist.duration),
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
                    IconButton(
                      tooltip: 'Pobierz',
                      icon: const Icon(
                        Icons.download_for_offline_outlined,
                        size: 30,
                      ),
                      onPressed: () => dummy('Pobierz (ikona)'),
                    ),
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
                                  PlaybackQueueScope.of(context).startShuffled(
                                    hits,
                                    playlistId: _playlist.id,
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
                      shape: palette.rounded
                          ? const CircleBorder()
                          : const RoundedRectangleBorder(),
                      onPressed: hits.isEmpty
                          ? null
                          : () => runQueueAction(
                              context,
                              (onStatus) =>
                                  PlaybackQueueScope.of(context).start(
                                    hits,
                                    0,
                                    playlistId: _playlist.id,
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
                  children: [
                    _ActionChip(
                      icon: Icons.add,
                      label: 'Dodaj',
                      onTap: () => dummy('Dodaj (do tej playlisty)'),
                    ),
                    _ActionChip(
                      icon: Icons.menu,
                      label: 'Edytuj',
                      onTap: () => dummy('Edytuj (playlistę)'),
                    ),
                    _ActionChip(
                      icon: Icons.swap_vert,
                      label: 'Sortuj',
                      onTap: () => dummy('Sortuj (playlistę)'),
                    ),
                  ],
                ),
              ),
              if (tracks == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (final (i, hit) in hits.indexed)
                  _trackTile(hits, i, hit, key: i == 0 ? _firstRowKey : null),
              const SizedBox(height: 24),
            ],
          ),
          if (_searching) _searchResults(hits),
        ],
      ),
    );
  }
}

/// "1 utwór", "3 utwory", "12 utworów".
String _trackCount(int n) {
  final tens = n % 100;
  final word = n == 1
      ? 'utwór'
      : n % 10 >= 2 && n % 10 <= 4 && (tens < 12 || tens > 14)
      ? 'utwory'
      : 'utworów';
  return '$n $word';
}

/// "3 godz. 12 min" / "45 min".
String _length(Duration d) => d.inHours > 0
    ? '${d.inHours} godz. ${d.inMinutes % 60} min'
    : '${d.inMinutes} min';

/// Playlist cover: the first four tracks' covers in a 2×2 grid (as the reference app does for
/// playlists people make), or one cover when there are fewer.
class _Mosaic extends StatelessWidget {
  const _Mosaic({
    required this.covers,
    required this.fallback,
    required this.size,
  });

  final List<CoverRequest> covers;
  final String fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (covers.length < 4) {
      final first = covers.firstOrNull;
      return first == null
          ? CoverArt(seed: fallback, size: size)
          : SongCover(cover: first, size: size);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: context.palette.radius(4),
      child: SizedBox.square(
        dimension: size,
        child: Wrap(
          children: [
            for (final cover in covers) SongCover(cover: cover, size: half),
          ],
        ),
      ),
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
  final VoidCallback onTap;

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
