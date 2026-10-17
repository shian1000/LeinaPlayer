import 'package:flutter/material.dart';

import '../data/library_folders.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/saved_songs.dart';
import '../data/smart_playlists.dart';
import '../data/song_catalog.dart';
import '../data/text_normalizer.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/collection_cover.dart';
import '../widgets/common.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_tile.dart';
import 'create_sheet.dart';
import 'mood_screen.dart';
import 'playlist_screen.dart';
import 'saved_songs_screen.dart';
import 'smart_playlist_screen.dart';

const _id = 'Biblioteka';

/// What one of Biblioteka's categories lists.
enum LibraryCategory {
  playlists('Playlisty'),
  albums('Albumy'),
  moods('Nastroje'),
  folders('Foldery');

  const LibraryCategory(this.label);

  final String label;
}

/// Biblioteka's rows for [category] (`null`: everything): its playlists and moods, with the
/// folders holding them. A category shows only the folders with something it lets through, and
/// inside a folder the same; "Foldery" only the folders.
List<LibraryEntry> _libraryEntries(
  BuildContext context,
  LibraryCategory? category,
) {
  final all = PlaylistLibraryScope.of(context).playlists;
  bool album(PlaylistSummary p) => p.source == PlaylistSource.spotifyAlbum;
  final playlists = switch (category) {
    null || LibraryCategory.folders => all,
    LibraryCategory.playlists => [
      for (final p in all)
        if (!album(p)) p,
    ],
    LibraryCategory.albums => [
      for (final p in all)
        if (album(p)) p,
    ],
    LibraryCategory.moods => const <PlaylistSummary>[],
  };
  final moodLibrary = MoodLibraryScope.maybeOf(context);
  final showMoods =
      category == null ||
      category == LibraryCategory.moods ||
      category == LibraryCategory.folders;
  final moods = showMoods && moodLibrary != null
      ? [...moodLibrary.userMoods, ...moodLibrary.globalMoods]
      : const <Mood>[];
  final keepEmpty = category == null || category == LibraryCategory.folders;
  final entries =
      LibraryFoldersScope.maybeOf(context)?.entries(
        playlists: playlists,
        moods: moods,
        keepEmptyFolders: keepEmpty,
      ) ??
      [
        for (final p in playlists) PlaylistEntry(p),
        for (final m in moods) MoodEntry(m),
      ];
  if (category == LibraryCategory.folders) {
    return entries.whereType<FolderEntry>().toList();
  }
  return entries;
}

/// Biblioteka: a search over it, its categories (Playlisty, Albumy, Nastroje, Foldery,
/// Wykonawcy, Na później, Dynamiczne playlisty — each its own list, after Juxtopposed's Spotify
/// redesign), then everything, in folders or not, ordered by "Sortuj wg".
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folders = LibraryFoldersScope.maybeOf(context);
    final entries = _libraryEntries(context, null);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(
            title: 'Biblioteka',
            actions: [
              IconButton(
                tooltip: _searching
                    ? 'Zamknij wyszukiwanie'
                    : 'Wyszukaj w Bibliotece',
                icon: Icon(_searching ? Icons.close : Icons.search, size: 30),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _search.clear();
                }),
              ),
              IconButton(
                tooltip: 'Utwórz (+)',
                icon: const Icon(Icons.add, size: 32),
                onPressed: () =>
                    showCreateSheet(context, idPrefix: '$_id › Utwórz (+)'),
              ),
            ],
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Szukaj w Bibliotece',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            child: _searching
                ? _SearchResults(query: _search.text, entries: entries)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      const _Categories(),
                      if (folders != null) _ViewRow(folders: folders),
                      if (entries.isEmpty)
                        const _EmptyLibrary()
                      else
                        LibraryEntries(entries: entries),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Biblioteka's categories, each with how much is in it.
class _Categories extends StatelessWidget {
  const _Categories();

  @override
  Widget build(BuildContext context) {
    final playlists = PlaylistLibraryScope.of(context).playlists;
    final albums = playlists
        .where((p) => p.source == PlaylistSource.spotifyAlbum)
        .length;
    final moods = MoodLibraryScope.maybeOf(context);
    final folders = LibraryFoldersScope.maybeOf(context)?.folders.length;
    final saved = SavedSongsScope.maybeOf(context);
    final liked = LikedSongsScope.maybeOf(context);
    final smart = SmartPlaylistsScope.maybeOf(context);
    void open(LibraryCategory category) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryCategoryScreen(category: category),
      ),
    );
    return Column(
      children: [
        if (liked != null)
          _CategoryRow(
            icon: Icons.favorite_border,
            label: likedSongsLabel,
            count: liked.songs.length,
            onTap: () => SavedSongsScreen.openLiked(context),
          ),
        _CategoryRow(
          icon: Icons.queue_music,
          label: LibraryCategory.playlists.label,
          count: playlists.length - albums,
          onTap: () => open(LibraryCategory.playlists),
        ),
        _CategoryRow(
          icon: Icons.album_outlined,
          label: LibraryCategory.albums.label,
          count: albums,
          onTap: () => open(LibraryCategory.albums),
        ),
        _CategoryRow(
          icon: moodIcon,
          label: LibraryCategory.moods.label,
          count: moods == null
              ? null
              : moods.userMoods.length + moods.globalMoods.length,
          onTap: () => open(LibraryCategory.moods),
        ),
        if (folders != null)
          _CategoryRow(
            icon: Icons.folder_outlined,
            label: LibraryCategory.folders.label,
            count: folders,
            onTap: () => open(LibraryCategory.folders),
          ),
        _CategoryRow(
          icon: Icons.person_outline,
          label: 'Wykonawcy',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ArtistsScreen()),
          ),
        ),
        if (saved != null)
          _CategoryRow(
            icon: Icons.bookmark_border,
            label: 'Na później',
            count: saved.songs.length,
            onTap: () => SavedSongsScreen.open(context),
          ),
        if (smart != null)
          _CategoryRow(
            icon: Icons.auto_mode,
            label: 'Dynamiczne playlisty',
            count: smart.playlists.length,
            onTap: () => SmartPlaylistsScreen.open(context),
          ),
        const Divider(),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(
      label,
      style: const TextStyle(
        fontSize: AppFontSize.listTitle,
        fontWeight: FontWeight.bold,
      ),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count != null)
          Text(
            '$count',
            style: TextStyle(color: context.palette.textSecondary),
          ),
        const Icon(Icons.chevron_right),
      ],
    ),
    onTap: onTap,
  );
}

/// Biblioteka's playlists, moods and folders (also those inside folders) whose name holds
/// every word typed, and its dynamic playlists.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query, required this.entries});

  final String query;
  final List<LibraryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final words = normalizeForSearch(query).split(' ')
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const SizedBox.shrink();
    bool matches(String name) {
      final normalized = normalizeForSearch(name);
      return words.every(normalized.contains);
    }

    final found = [
      for (final entry in entries) ...[
        if (matches(entry.name)) entry,
        if (entry case FolderEntry(:final contents))
          for (final inner in contents)
            if (matches(inner.name)) inner,
      ],
    ];
    final smart = [
      for (final p
          in SmartPlaylistsScope.maybeOf(context)?.playlists ??
              const <SmartPlaylist>[])
        if (matches(p.name)) p,
    ];
    if (found.isEmpty && smart.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Nic w Bibliotece nie pasuje do „$query”.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.textSecondary),
        ),
      );
    }
    return ListView(
      children: [
        for (final entry in found) LibraryEntryTile(entry: entry),
        for (final p in smart) SmartPlaylistTile(playlist: p),
      ],
    );
  }
}

/// Biblioteka › Wykonawcy: every artist in music.db (MusicDatabase is the user's library) and
/// on the phone, with how many songs each has, alphabetically; a field narrows it down.
class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    void count(String label) {
      for (final name in artistNamesOf(label)) {
        counts.update(name, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    for (final song in SongCatalogScope.of(context).songs) {
      count(song.artistLabel);
    }
    for (final file in LocalLibraryScope.of(context).songs) {
      if (file.pending && file.artist != null) count(file.artist!);
    }
    final words = normalizeForSearch(_query).split(' ')
      ..removeWhere((w) => w.isEmpty);
    final artists = [
      for (final name in counts.keys)
        if (words.every(normalizeForSearch(name).contains)) name,
    ]..sort((a, b) => compareNames(a, b));
    return Scaffold(
      appBar: AppBar(title: const Text('Wykonawcy')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Szukaj wykonawcy',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (text) => setState(() => _query = text),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: artists.length,
              itemBuilder: (context, i) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: context.palette.chip,
                  child: Icon(
                    Icons.person_outline,
                    color: context.palette.textSecondary,
                  ),
                ),
                title: Text(artists[i]),
                subtitle: Text('${counts[artists[i]]} utw.'),
                onTap: () => openArtistSongs(context, artists[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of Biblioteka's categories as a list of its own, in Biblioteka's order.
class LibraryCategoryScreen extends StatelessWidget {
  const LibraryCategoryScreen({super.key, required this.category});

  final LibraryCategory category;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final folders = LibraryFoldersScope.maybeOf(context);
    final entries = _libraryEntries(context, category);
    return Scaffold(
      appBar: AppBar(
        title: Text(category.label),
        actions: [
          IconButton(
            tooltip: 'Utwórz (+)',
            icon: const Icon(Icons.add),
            onPressed: () =>
                showCreateSheet(context, idPrefix: '$_id › Utwórz (+)'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (folders != null) _ViewRow(folders: folders),
          if (entries.isEmpty)
            switch (category) {
              LibraryCategory.moods => const _EmptyMoods(),
              LibraryCategory.playlists => const _EmptyLibrary(),
              LibraryCategory.albums => _EmptyNote(
                'Brak albumów. Album ze Spotify dodasz, importując jego link '
                '(+ › Importuj playlistę).',
                palette: palette,
              ),
              LibraryCategory.folders => _EmptyNote(
                'Brak folderów. Utwórz folder przyciskiem + albo przytrzymaj '
                'playlistę lub nastrój.',
                palette: palette,
              ),
            }
          else
            LibraryEntries(entries: entries, category: category),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text, {required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: palette.textSecondary),
    ),
  );
}

/// "Sortuj wg" and the list / grid switch.
class _ViewRow extends StatelessWidget {
  const _ViewRow({required this.folders});

  final LibraryFolders folders;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _SortButton(folders: folders),
      const Spacer(),
      IconButton(
        tooltip: folders.grid ? 'Widok listy' : 'Widok siatki',
        icon: Icon(folders.grid ? Icons.view_list : Icons.grid_view),
        onPressed: () => folders.setGrid(!folders.grid),
      ),
    ],
  );
}

/// [entries] as rows, or as a grid of covers when "Widok siatki" is on.
class LibraryEntries extends StatelessWidget {
  const LibraryEntries({super.key, required this.entries, this.category});

  final List<LibraryEntry> entries;
  final LibraryCategory? category;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    if (!(LibraryFoldersScope.maybeOf(context)?.grid ?? false)) {
      return Column(
        children: [
          for (final entry in entries)
            LibraryEntryTile(entry: entry, category: category),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 2 * _gap) / 3;
          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: width,
                  child: LibraryEntryTile(
                    entry: entry,
                    category: category,
                    gridSize: width,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Sortuj wg": shows the order and opens the sheet to change it.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.folders});

  final LibraryFolders folders;

  void _showSortSheet(BuildContext context) {
    showMenuSheet(
      context,
      idPrefix: '$_id › Sortuj wg',
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
        for (final option in LibrarySort.values)
          MenuSheetEntry(
            option == folders.sort ? Icons.check : Icons.circle_outlined,
            option.label,
            onTap: () => folders.setSort(option),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(foregroundColor: context.palette.textPrimary),
    icon: const Icon(Icons.swap_vert),
    label: Text(
      folders.sort.label,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    onPressed: () => _showSortSheet(context),
  );
}

/// A row of Biblioteka or a folder: tapping opens it, holding it moves a playlist or mood to a
/// folder, or opens a folder's menu. The playlist / mood the playing song was queued from is
/// highlighted, like the playing song in a list.
class LibraryEntryTile extends StatelessWidget {
  const LibraryEntryTile({
    super.key,
    required this.entry,
    this.category,
    this.gridSize,
  });

  final LibraryEntry entry;

  /// A cell of [LibraryEntries]' grid this wide: the cover with the name under it.
  final double? gridSize;

  /// The category it's listed in; a folder opened from it shows only what the category does.
  final LibraryCategory? category;

  @override
  Widget build(BuildContext context) {
    final coverSize = gridSize ?? 64;
    final (leading, subtitle) = switch (entry) {
      FolderEntry(:final contents) => (
        _FolderIcon(size: coverSize),
        'Folder • ${_itemCount(contents)}',
      ),
      PlaylistEntry(:final playlist) => (
        PlaylistCover(playlist: playlist, size: coverSize),
        [
          playlist.source == PlaylistSource.spotifyAlbum
              ? 'Album'
              : 'Playlista',
          ?playlist.owner,
        ].join(' • '),
      ),
      MoodEntry(:final mood) => (
        MoodCover(mood: mood, size: coverSize),
        mood.global ? 'Nastrój • globalny' : 'Nastrój • Twój',
      ),
    };
    final folders = LibraryFoldersScope.maybeOf(context);
    final origin = PlaybackQueueScope.maybeOf(context)?.currentEntry?.origin;
    final playing = switch (entry) {
      PlaylistEntry(:final playlist) =>
        origin?.isFrom(playlistId: playlist.id) ?? false,
      MoodEntry(:final mood) => origin?.isFrom(moodKey: mood.key) ?? false,
      FolderEntry() => false,
    };
    void open() => switch (entry) {
      FolderEntry(:final folder) => FolderScreen.open(
        context,
        folder,
        category: category,
      ),
      PlaylistEntry(:final playlist) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(playlist: playlist),
        ),
      ),
      MoodEntry(:final mood) => MoodScreen.open(context, mood),
    };
    final VoidCallback? menu = folders == null
        ? null
        : () => switch (entry) {
            FolderEntry(:final folder) => showFolderMenu(context, folder),
            _ => showMoveToFolderSheet(context, entry.key),
          };
    if (gridSize != null) {
      return InkWell(
        onTap: open,
        onLongPress: menu,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(height: 6),
            CurrentTitle(text: entry.name, isCurrent: playing),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.small,
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leading,
      title: CurrentTitle(text: entry.name, isCurrent: playing),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: open,
      onLongPress: menu,
    );
  }

  static String _itemCount(List<LibraryEntry> contents) {
    final n = contents.length;
    if (n == 0) return 'pusty';
    final playlists = contents.whereType<PlaylistEntry>().length;
    final moods = n - playlists;
    String form(int n, String one, String few, String many) {
      if (n == 1) return '1 $one';
      final tens = n % 100 ~/ 10;
      final last = n % 10;
      return '$n ${tens != 1 && last >= 2 && last <= 4 ? few : many}';
    }

    return [
      if (playlists > 0) form(playlists, 'playlista', 'playlisty', 'playlist'),
      if (moods > 0) form(moods, 'nastrój', 'nastroje', 'nastrojów'),
    ].join(', ');
  }
}

class _FolderIcon extends StatelessWidget {
  const _FolderIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.folder_outlined,
        size: size * 0.5,
        color: palette.textSecondary,
      ),
    );
  }
}

/// A folder's menu: rename it or delete it (what's in it goes back to Biblioteka).
Future<void> showFolderMenu(
  BuildContext context,
  LibraryFolder folder, {
  VoidCallback? onDeleted,
}) {
  final folders = LibraryFoldersScope.of(context);
  return showMenuSheet(
    context,
    idPrefix: '$_id › Folder › Menu (⋮)',
    header: MenuSheetHeader(
      cover: const _FolderIcon(size: 48),
      title: folder.name,
      subtitle: 'Folder',
    ),
    entries: [
      MenuSheetEntry(
        Icons.edit_outlined,
        'Zmień nazwę',
        onTap: () async {
          final name = await showDialog<String>(
            context: context,
            builder: (_) => TextInputDialog(
              title: 'Nazwa folderu',
              hint: 'Nazwa folderu',
              initial: folder.name,
            ),
          );
          if (name != null && name.trim().isNotEmpty) {
            await folders.rename(folder.id, name);
          }
        },
      ),
      MenuSheetEntry(
        Icons.delete_outline,
        'Usuń folder',
        subtitle: 'Jego playlisty i nastroje wrócą do Biblioteki',
        onTap: () async {
          await folders.delete(folder.id);
          onDeleted?.call();
        },
      ),
    ],
  );
}

/// What's in a Biblioteka folder that the category it was opened from lets through, in
/// Biblioteka's order.
class FolderScreen extends StatelessWidget {
  const FolderScreen({super.key, required this.folderId, this.category});

  final String folderId;
  final LibraryCategory? category;

  static Future<void> open(
    BuildContext context,
    LibraryFolder folder, {
    LibraryCategory? category,
  }) {
    LibraryFoldersScope.read(context)?.opened(folder.key);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderScreen(
          folderId: folder.id,
          // Inside a folder "Foldery" means everything in it.
          category: category == LibraryCategory.folders ? null : category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final folders = LibraryFoldersScope.of(context);
    final folder = folders.byId(folderId);
    if (folder == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'Tego folderu już nie ma.',
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
      );
    }
    final entries = _libraryEntries(context, category)
        .whereType<FolderEntry>()
        .firstWhere(
          (e) => e.folder.id == folderId,
          orElse: () => FolderEntry(folder, const []),
        )
        .contents;
    return Scaffold(
      appBar: AppBar(
        title: Text(folder.name),
        actions: [
          IconButton(
            tooltip: 'Menu folderu (⋮)',
            icon: const Icon(Icons.more_vert),
            onPressed: () => showFolderMenu(
              context,
              folder,
              onDeleted: () {
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _ViewRow(folders: folders),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                'Pusty folder. Przenieś tu playlistę albo nastrój, przytrzymując '
                'je w Bibliotece albo z ich menu (⋮): „Przenieś do folderu”.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          LibraryEntries(entries: entries, category: category),
        ],
      ),
    );
  }
}

class _EmptyMoods extends StatelessWidget {
  const _EmptyMoods();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: Column(
        children: [
          Icon(moodIcon, size: 48, color: palette.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'Brak nastrojów',
            style: TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Utwórz nastrój przyciskiem + u góry albo z menu ⋮ utworu („Dodaj do '
            'nastroju”). Nastroje globalne przychodzą z MusicDatabase.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: Column(
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 48,
            color: palette.textSecondary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Brak playlist',
            style: TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dodaj playlistę przyciskiem + u góry, np. importując ją z YouTube.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
