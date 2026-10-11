import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../dummy.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/song_tile.dart';

const _id = 'Playlista';

/// One of the user's playlists (Biblioteka › playlist), laid out like a playlist in the
/// reference app; its tracks are rows like the song search's, with the same source icons.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist});

  final PlaylistSummary playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<PlaylistTrack>? _tracks;
  bool _loading = false;

  /// Once the header has scrolled away the app bar turns solid and shows the name, as in the
  /// reference app (until then it's transparent over the cover).
  final _scroll = ScrollController();
  bool _headerHidden = false;

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
    if (mounted) setState(() => _tracks = tracks);
  }

  PlaylistSummary get _playlist => widget.playlist;
  String get _owner => _playlist.owner ?? 'YouTube';

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

  void _showPlaylistMenu() {
    showMenuSheet(
      context,
      idPrefix: '$_id › Menu (⋮)',
      header: MenuSheetHeader(
        cover: CoverArt(seed: _playlist.name, size: 56),
        title: _playlist.name,
        subtitle: 'Playlista • $_owner',
      ),
      entries: [
        const MenuSheetEntry(Icons.share_outlined, 'Udostępnij'),
        MenuSheetEntry(Icons.check_circle, 'Usuń z Biblioteki', onTap: _delete),
        const MenuSheetEntry(Icons.add, 'Dodaj do tej playlisty'),
        const MenuSheetEntry(Icons.edit_outlined, 'Edytuj playlistę'),
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
        cover: CoverArt(seed: hit.youtubeVideoId ?? hit.title, size: 56),
        title: hit.title,
        subtitle: hit.artistLabel,
      ),
      entries: const [
        MenuSheetEntry(Icons.share_outlined, 'Udostępnij'),
        MenuSheetEntry(
          Icons.add_circle_outline,
          'Dodaj do Polubionych utworów',
        ),
        MenuSheetEntry(Icons.playlist_add, 'Dodaj do playlisty'),
        MenuSheetEntry(Icons.remove_circle_outline, 'Usuń z tej playlisty'),
        MenuSheetEntry(Icons.queue_music, 'Dodaj do kolejki'),
        MenuSheetEntry(Icons.album_outlined, 'Przejdź do albumu'),
        MenuSheetEntry(Icons.person_outline, 'Przejdź do wykonawców'),
        MenuSheetEntry(Icons.radio, 'Przejdź do radia utworu'),
      ],
    );
  }

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
      appBar: AppBar(
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
            tooltip: 'Menu playlisty (⋮)',
            icon: const Icon(Icons.more_vert),
            onPressed: _showPlaylistMenu,
          ),
        ],
      ),
      body: ListView(
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
                    seeds: [for (final hit in hits.take(4)) _seedOf(hit)],
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
                      Icons.smart_display_outlined,
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
                  onPressed: () => dummy('Udostępnij (ikona)'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Odtwarzanie losowe',
                  icon: Icon(Icons.shuffle, color: palette.accent, size: 30),
                  onPressed: () => dummy('Odtwarzanie losowe'),
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
                  onPressed: () => dummy('Odtwórz playlistę'),
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
            for (final hit in hits)
              SongTile(
                hit: hit,
                playlistName: _playlist.name,
                // Like the reference app's playlists: just the artist.
                subtitle: hit.artistLabel,
                trailing: IconButton(
                  tooltip: 'Menu utworu (⋮)',
                  icon: Icon(Icons.more_vert, color: palette.textSecondary),
                  onPressed: () => _showTrackMenu(hit),
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

String _seedOf(SearchHit hit) => hit.mainSong != null
    ? '${hit.mainSong!.id}'
    : hit.youtubeVideoId ?? hit.title;

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
    required this.seeds,
    required this.fallback,
    required this.size,
  });

  final List<String> seeds;
  final String fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (seeds.length < 4) {
      return CoverArt(seed: seeds.firstOrNull ?? fallback, size: size);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: context.palette.radius(4),
      child: SizedBox.square(
        dimension: size,
        child: Wrap(
          children: [
            for (final seed in seeds) CoverArt(seed: seed, size: half),
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
