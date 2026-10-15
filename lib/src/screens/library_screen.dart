import 'package:flutter/material.dart';

import '../dummy.dart';
import '../playback/playback_queue.dart';
import '../data/library_folders.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/collection_cover.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/song_tile.dart';
import 'app_shell.dart';
import 'create_sheet.dart';
import 'mood_screen.dart';
import 'playlist_screen.dart';

const _id = 'Biblioteka';
const _filters = ['Playlisty', 'Nastroje', 'Albumy', 'Wykonawcy'];

/// Filters that work; the rest are dummies.
const _playlistsFilter = 0;
const _moodsFilter = 1;

/// Biblioteka's rows for [filter] (an index of [_filters], `null` for none): its playlists and
/// moods, with the folders holding them. A filter shows only the folders with something it
/// lets through, and inside a folder the same.
List<LibraryEntry> _libraryEntries(BuildContext context, int? filter) {
  final showPlaylists = filter != _moodsFilter;
  final showMoods = filter == null || filter == _moodsFilter;
  final playlists = showPlaylists
      ? PlaylistLibraryScope.of(context).playlists
      : const <PlaylistSummary>[];
  final moodLibrary = MoodLibraryScope.maybeOf(context);
  final moods = showMoods && moodLibrary != null
      ? [...moodLibrary.userMoods, ...moodLibrary.globalMoods]
      : const <Mood>[];
  return LibraryFoldersScope.maybeOf(context)?.entries(
        playlists: playlists,
        moods: moods,
        keepEmptyFolders: filter == null,
      ) ??
      [
        for (final p in playlists) PlaylistEntry(p),
        for (final m in moods) MoodEntry(m),
      ];
}

int? _filterIndex(String? label) {
  final i = label == null ? -1 : _filters.indexOf(label);
  return i < 0 ? null : i;
}

/// Biblioteka: the user's playlists and moods, in folders or not, ordered by "Sortuj wg". The
/// ticked filter is remembered (in [LibraryFolders]).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// Only for widget tests without [LibraryFoldersScope].
  int? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final folders = LibraryFoldersScope.maybeOf(context);
    final filter = folders == null
        ? _selectedFilter
        : _filterIndex(folders.filter);
    final entries = _libraryEntries(context, filter);
    return SafeArea(
      // Stretch: a centred Column would push the (narrower) filter-chip row inwards.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(
            title: 'Biblioteka',
            onAvatarTap: () => AppShell.of(context).openDrawer(),
            actions: [
              IconButton(
                tooltip: 'Wyszukaj w Bibliotece',
                icon: const Icon(Icons.search, size: 30),
                onPressed: () =>
                    showDummy(context, '$_id › Wyszukaj w Bibliotece'),
              ),
              IconButton(
                tooltip: 'Utwórz (+)',
                icon: const Icon(Icons.add, size: 32),
                onPressed: () =>
                    showCreateSheet(context, idPrefix: '$_id › Utwórz (+)'),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  PillChip(
                    label: _filters[i],
                    selected: i == filter,
                    onTap: () {
                      final next = i == filter ? null : i;
                      if (folders == null) {
                        setState(() => _selectedFilter = next);
                      } else {
                        folders.setFilter(next == null ? null : _filters[next]);
                      }
                      if (i != _playlistsFilter && i != _moodsFilter) {
                        showDummy(context, '$_id › Filtr: ${_filters[i]}');
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Row(
                  children: [
                    if (folders != null) _SortButton(folders: folders),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Widok siatki',
                      icon: const Icon(Icons.grid_view),
                      onPressed: () =>
                          showDummy(context, '$_id › Widok siatki'),
                    ),
                  ],
                ),
                if (filter == _moodsFilter && entries.isEmpty)
                  const _EmptyMoods()
                else if (entries.isEmpty)
                  const _EmptyLibrary()
                else
                  for (final entry in entries) LibraryEntryTile(entry: entry),
              ],
            ),
          ),
        ],
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
  const LibraryEntryTile({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final (leading, subtitle) = switch (entry) {
      FolderEntry(:final contents) => (
        _FolderIcon(size: 64),
        'Folder • ${_itemCount(contents)}',
      ),
      PlaylistEntry(:final playlist) => (
        PlaylistCover(playlist: playlist, size: 64),
        [
          playlist.source == PlaylistSource.spotifyAlbum
              ? 'Album'
              : 'Playlista',
          ?playlist.owner,
        ].join(' • '),
      ),
      MoodEntry(:final mood) => (
        MoodCover(mood: mood, size: 64),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leading,
      title: CurrentTitle(text: entry.name, isCurrent: playing),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => switch (entry) {
        FolderEntry(:final folder) => FolderScreen.open(context, folder),
        PlaylistEntry(:final playlist) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaylistScreen(playlist: playlist),
          ),
        ),
        MoodEntry(:final mood) => MoodScreen.open(context, mood),
      },
      onLongPress: folders == null
          ? null
          : () => switch (entry) {
              FolderEntry(:final folder) => showFolderMenu(context, folder),
              _ => showMoveToFolderSheet(context, entry.key),
            },
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

/// What's in a Biblioteka folder that Biblioteka's filter lets through, in Biblioteka's order.
class FolderScreen extends StatelessWidget {
  const FolderScreen({super.key, required this.folderId});

  final String folderId;

  static Future<void> open(BuildContext context, LibraryFolder folder) {
    LibraryFoldersScope.read(context)?.opened(folder.key);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderScreen(folderId: folder.id),
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
    final entries = _libraryEntries(context, _filterIndex(folders.filter))
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
          Row(children: [_SortButton(folders: folders)]),
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
          for (final entry in entries) LibraryEntryTile(entry: entry),
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
