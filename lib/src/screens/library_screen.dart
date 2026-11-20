import 'package:flutter/material.dart';

import '../data/library_folders.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/saved_songs.dart';
import '../data/smart_playlists.dart';
import '../data/song_catalog.dart';
import '../data/text_normalizer.dart';
import '../data/combined_search.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/collection_cover.dart';
import '../widgets/common.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_tile.dart';
import 'create_sheet.dart';
import 'mood_screen.dart';
import 'playlist_screen.dart';
import 'saved_songs_screen.dart';
import 'smart_playlist_screen.dart';

const _id = 'Biblioteka';

/// Biblioteka's rows for the kinds in [filter] (none: everything): its playlists and moods, with
/// the folders holding them. Without "Foldery" only the folders with something the filter lets
/// through show, and inside a folder the same; with it every folder, whole, and outside folders
/// only the other kinds ticked.
List<LibraryEntry> _libraryEntries(
  BuildContext context,
  Set<LibraryCategory> filter,
) {
  bool passes(LibraryEntry entry) => switch (entry) {
    FolderEntry() => true,
    MoodEntry() => filter.contains(LibraryCategory.moods),
    PlaylistEntry(:final playlist) => filter.contains(
      playlist.source == PlaylistSource.spotifyAlbum
          ? LibraryCategory.albums
          : LibraryCategory.playlists,
    ),
  };
  final foldersTicked = filter.contains(LibraryCategory.folders);
  final whole = filter.isEmpty || foldersTicked;
  final moodLibrary = MoodLibraryScope.maybeOf(context);
  final playlists = [
    for (final p in PlaylistLibraryScope.of(context).playlists)
      if (whole || passes(PlaylistEntry(p))) p,
  ];
  final moods = [
    for (final m in [...?moodLibrary?.userMoods, ...?moodLibrary?.globalMoods])
      if (whole || passes(MoodEntry(m))) m,
  ];
  final entries =
      LibraryFoldersScope.maybeOf(
        context,
      )?.entries(playlists: playlists, moods: moods, keepEmptyFolders: whole) ??
      [
        for (final p in playlists) PlaylistEntry(p),
        for (final m in moods) MoodEntry(m),
      ];
  return foldersTicked ? entries.where(passes).toList() : entries;
}

/// Biblioteka: a search over it, its categories (Playlisty, Albumy, Nastroje, Foldery,
/// Wykonawcy, Dynamiczne playlisty — each its own list, after Juxtopposed's Spotify
/// redesign), then everything, in folders or not, ordered by "Sortuj wg", narrowed by filter
/// chips that are remembered (in [LibraryFolders]). The search goes over everything regardless.
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
    final filter = folders?.filters ?? const <LibraryCategory>{};
    final entries = _libraryEntries(context, _searching ? const {} : filter);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(
            title: l10n.libraryScreenTitle,
            actions: [
              IconButton(
                tooltip: _searching
                    ? l10n.libraryScreenCloseSearch
                    : l10n.libraryScreenSearchTooltip,
                icon: Icon(_searching ? Icons.close : Icons.search, size: 30),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _search.clear();
                }),
              ),
              IconButton(
                tooltip: l10n.libraryScreenCreate,
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
                decoration: InputDecoration(
                  hintText: l10n.libraryScreenSearchHint,
                  prefixIcon: const Icon(Icons.search),
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
                      if (folders != null) ...[
                        _FilterChips(folders: folders),
                        _ViewRow(folders: folders),
                      ],
                      if (entries.isNotEmpty)
                        LibraryEntries(entries: entries, filter: filter)
                      else if (filter.isEmpty)
                        const _EmptyLibrary()
                      else if (filter.length == 1)
                        _EmptyCategory(filter.single)
                      else
                        _EmptyNote(
                          l10n.libraryScreenNoFilterMatch,
                          palette: context.palette,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The filter over Biblioteka's list: any of the kinds, none ticked shows everything.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.folders});

  final LibraryFolders folders;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Row(
      children: [
        for (final category in LibraryCategory.values) ...[
          if (category.index > 0) const SizedBox(width: 8),
          PillChip(
            label: category.label,
            selected: folders.filters.contains(category),
            onTap: () => folders.toggleFilter(category),
          ),
        ],
      ],
    ),
  );
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
          label: l10n.libraryScreenArtists,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ArtistsScreen()),
          ),
        ),
        if (smart != null)
          _CategoryRow(
            icon: Icons.auto_mode,
            label: l10n.libraryScreenSmartPlaylists,
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
          l10n.libraryScreenNoSearchMatch(query),
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
      appBar: AppBar(title: Text(l10n.libraryScreenArtists)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.libraryScreenSearchArtist,
                prefixIcon: const Icon(Icons.search),
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
                subtitle: Text(
                  l10n.libraryScreenArtistSongs(counts[artists[i]]!),
                ),
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
    final folders = LibraryFoldersScope.maybeOf(context);
    final entries = _libraryEntries(context, {category});
    return Scaffold(
      appBar: AppBar(
        title: Text(category.label),
        actions: [
          IconButton(
            tooltip: l10n.libraryScreenCreate,
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
            _EmptyCategory(category)
          else
            LibraryEntries(entries: entries, filter: {category}),
        ],
      ),
    );
  }
}

/// What a category or filter chip with nothing in it says instead of its list.
class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory(this.category);

  final LibraryCategory category;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return switch (category) {
      LibraryCategory.moods => const _EmptyMoods(),
      LibraryCategory.playlists => const _EmptyLibrary(),
      LibraryCategory.albums => _EmptyNote(
        l10n.libraryScreenNoAlbums,
        palette: palette,
      ),
      LibraryCategory.folders => _EmptyNote(
        l10n.libraryScreenNoFolders,
        palette: palette,
      ),
    };
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

/// "Sortuj wg" (of the folder [folderId], else of Biblioteka) and the list / grid switch.
class _ViewRow extends StatelessWidget {
  const _ViewRow({required this.folders, this.folderId});

  final LibraryFolders folders;
  final String? folderId;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _SortButton(folders: folders, folderId: folderId),
      const Spacer(),
      IconButton(
        tooltip: folders.grid
            ? l10n.libraryScreenListView
            : l10n.libraryScreenGridView,
        icon: Icon(folders.grid ? Icons.view_list : Icons.grid_view),
        onPressed: () => folders.setGrid(!folders.grid),
      ),
    ],
  );
}

/// [entries] as rows, or as a grid of covers when "Widok siatki" is on.
class LibraryEntries extends StatelessWidget {
  const LibraryEntries({
    super.key,
    required this.entries,
    this.filter = const {},
  });

  final List<LibraryEntry> entries;
  final Set<LibraryCategory> filter;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    if (!(LibraryFoldersScope.maybeOf(context)?.grid ?? false)) {
      return Column(
        children: [
          for (final entry in entries)
            LibraryEntryTile(entry: entry, filter: filter),
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
                    filter: filter,
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

/// "Sortuj wg": shows the order and opens the sheet to change it. In a folder ([folderId]) it
/// changes only that folder's order, which can go back to following Biblioteka's.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.folders, this.folderId});

  final LibraryFolders folders;
  final String? folderId;

  void _showSortSheet(BuildContext context) {
    final folderId = this.folderId;
    final own = folderId != null && folders.hasOwnSort(folderId);
    final current = folders.sortOf(folderId);
    showMenuSheet(
      context,
      idPrefix: '$_id › Sortuj wg',
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: Text(
            l10n.libraryScreenSortBy,
            style: const TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      entries: [
        for (final option in LibrarySort.values)
          MenuSheetEntry(
            (folderId == null || own) && option == current
                ? Icons.check
                : Icons.circle_outlined,
            option.label,
            onTap: () => folderId == null
                ? folders.setSort(option)
                : folders.setFolderSort(folderId, option),
          ),
        if (folderId != null)
          MenuSheetEntry(
            own ? Icons.circle_outlined : Icons.check,
            l10n.libraryScreenSortAsLibrary,
            subtitle: folders.sort.label,
            onTap: () => folders.setFolderSort(folderId, null),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(foregroundColor: context.palette.textPrimary),
    icon: const Icon(Icons.swap_vert),
    label: Text(
      folders.sortOf(folderId).label,
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
    this.filter = const {},
    this.gridSize,
  });

  final LibraryEntry entry;

  /// A cell of [LibraryEntries]' grid this wide: the cover with the name under it.
  final double? gridSize;

  /// The kinds it's listed under; a folder opened from there shows only those.
  final Set<LibraryCategory> filter;

  @override
  Widget build(BuildContext context) {
    final coverSize = gridSize ?? 64;
    final (leading, subtitle) = switch (entry) {
      FolderEntry(:final contents) => (
        FolderCover(size: coverSize),
        l10n.libraryScreenFolderSubtitle(_itemCount(contents)),
      ),
      PlaylistEntry(:final playlist) => (
        PlaylistCover(playlist: playlist, size: coverSize),
        [
          playlist.source == PlaylistSource.spotifyAlbum
              ? l10n.libraryScreenKindAlbum
              : l10n.libraryScreenKindPlaylist,
          ?playlist.owner,
        ].join(' • '),
      ),
      MoodEntry(:final mood) => (
        MoodCover(mood: mood, size: coverSize),
        mood.global ? l10n.libraryScreenGlobalMood : l10n.libraryScreenOwnMood,
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
        filter: filter,
      ),
      PlaylistEntry(:final playlist) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(playlist: playlist),
        ),
      ),
      MoodEntry(:final mood) => MoodScreen.open(context, mood),
    };
    void menu() => switch (entry) {
      FolderEntry(:final folder) when folders != null => showFolderMenu(
        context,
        folder,
      ),
      FolderEntry() => null,
      _ => showLibraryEntryMenu(context, entry, leading, subtitle),
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
            ScrollingText(
              subtitle,
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
      subtitle: ScrollingText(subtitle),
      onTap: open,
      onLongPress: menu,
    );
  }

  static String _itemCount(List<LibraryEntry> contents) {
    final n = contents.length;
    if (n == 0) return l10n.libraryScreenFolderEmpty;
    final playlists = contents.whereType<PlaylistEntry>().length;
    final moods = n - playlists;
    return [
      if (playlists > 0) l10n.libraryScreenPlaylistCount(playlists),
      if (moods > 0) l10n.libraryScreenMoodCount(moods),
    ].join(', ');
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
      cover: const FolderCover(size: 48),
      title: folder.name,
      subtitle: l10n.libraryScreenFolder,
    ),
    entries: [
      MenuSheetEntry(
        Icons.edit_outlined,
        l10n.libraryScreenRename,
        onTap: () async {
          final name = await showDialog<String>(
            context: context,
            builder: (_) => TextInputDialog(
              title: l10n.libraryScreenFolderName,
              hint: l10n.libraryScreenFolderName,
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
        l10n.libraryScreenDeleteFolder,
        subtitle: l10n.libraryScreenDeleteFolderSubtitle,
        onTap: () async {
          await folders.delete(folder.id);
          onDeleted?.call();
        },
      ),
    ],
  );
}

/// What's in a Biblioteka folder that the filter it was opened from lets through, in the
/// folder's own order or else Biblioteka's.
class FolderScreen extends StatelessWidget {
  const FolderScreen({
    super.key,
    required this.folderId,
    this.filter = const {},
  });

  final String folderId;
  final Set<LibraryCategory> filter;

  static Future<void> open(
    BuildContext context,
    LibraryFolder folder, {
    Set<LibraryCategory> filter = const {},
  }) {
    LibraryFoldersScope.read(context)?.opened(folder.key);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderScreen(
          folderId: folder.id,
          // Inside a folder "Foldery" means everything in it.
          filter: filter.contains(LibraryCategory.folders) ? const {} : filter,
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
            l10n.libraryScreenFolderGone,
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
      );
    }
    final entries = _libraryEntries(context, filter)
        .whereType<FolderEntry>()
        .firstWhere(
          (e) => e.folder.id == folderId,
          orElse: () => FolderEntry(folder, const []),
        )
        .contents;
    return Scaffold(
      appBar: AppBar(
        title: ScrollingText(folder.name),
        actions: [
          IconButton(
            tooltip: l10n.libraryScreenFolderMenu,
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
          _ViewRow(folders: folders, folderId: folderId),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                l10n.libraryScreenFolderEmptyNote,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          LibraryEntries(entries: entries, filter: filter),
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
          Text(
            l10n.libraryScreenNoMoods,
            style: const TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.libraryScreenNoMoodsNote,
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
          Text(
            l10n.libraryScreenNoPlaylists,
            style: const TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.libraryScreenNoPlaylistsNote,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A playlist's or mood's menu (a long press in Biblioteka or on Home's card): into the queue
/// as a whole, or to a folder.
Future<void> showLibraryEntryMenu(
  BuildContext context,
  LibraryEntry entry,
  Widget cover,
  String subtitle,
) {
  final catalog = SongCatalogScope.of(context);
  final library = LocalLibraryScope.of(context);
  final youTube = YouTubeLibraryScope.of(context);
  final (
    QueueOrigin origin,
    Future<List<SearchHit>> Function() songs,
  ) = switch (entry) {
    PlaylistEntry(:final playlist) => (
      QueueOrigin(
        playlistId: playlist.id,
        youTubeListId: playlist.youTubeId,
        playlistName: playlist.name,
      ),
      () async => [
        for (final track in await PlaylistLibraryScope.of(
          context,
        ).tracks(playlist.id))
          playlistHit(track, catalog, library, youTube),
      ],
    ),
    MoodEntry(:final mood) => (
      QueueOrigin(playlistName: mood.name, moodKey: mood.key),
      () async => moodHits(mood, catalog, library, youTube),
    ),
    FolderEntry() => throw ArgumentError.value(entry),
  };
  final playlist = entry is PlaylistEntry;
  final feminine =
      entry is PlaylistEntry &&
      entry.playlist.source != PlaylistSource.spotifyAlbum;
  Future<void> queue(bool next) async {
    final hits = await songs();
    if (!context.mounted) return;
    if (hits.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              playlist
                  ? l10n.libraryScreenPlaylistEmpty
                  : l10n.libraryScreenMoodEmpty,
            ),
          ),
        );
      return;
    }
    await queueSongs(context, hits, next: next, origin: origin);
  }

  return showMenuSheet(
    context,
    idPrefix: '$_id › ${playlist ? 'Playlista' : 'Nastrój'} › Menu',
    header: MenuSheetHeader(
      cover: cover,
      title: entry.name,
      subtitle: subtitle,
    ),
    entries: [
      MenuSheetEntry(
        Icons.queue_music,
        l10n.libraryScreenAddToQueue,
        onTap: () => queue(false),
      ),
      MenuSheetEntry(
        Icons.playlist_play,
        feminine
            ? l10n.libraryScreenPlayNextFeminine
            : l10n.libraryScreenPlayNext,
        onTap: () => queue(true),
      ),
      ?moveToFolderEntry(context, entry.key),
    ],
  );
}
