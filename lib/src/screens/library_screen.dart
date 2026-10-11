import 'package:flutter/material.dart';

import '../dummy.dart';
import '../data/playlist_library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/menu_sheet.dart';
import 'app_shell.dart';
import 'create_sheet.dart';
import 'playlist_screen.dart';

const _id = 'Biblioteka';
const _filters = ['Playlisty', 'Albumy', 'Wykonawcy'];
const _sortOptions = ['Ostatnie', 'Ostatnio dodane', 'Alfabetycznie', 'Twórca'];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int? _selectedFilter;
  String _sort = _sortOptions.first;

  void _showSortSheet() {
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
        for (final option in _sortOptions)
          MenuSheetEntry(
            option == _sort ? Icons.check : Icons.circle_outlined,
            option,
            onTap: () {
              setState(() => _sort = option);
              showDummy(context, '$_id › Sortuj wg › $option');
            },
          ),
      ],
    );
  }

  void _openPlaylist(PlaylistSummary playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistScreen(playlist: playlist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = PlaylistLibraryScope.of(context).playlists;
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
                    selected: i == _selectedFilter,
                    onTap: () {
                      setState(
                        () => _selectedFilter = i == _selectedFilter ? null : i,
                      );
                      showDummy(context, '$_id › Filtr: ${_filters[i]}');
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
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: context.palette.textPrimary,
                      ),
                      icon: const Icon(Icons.swap_vert),
                      label: Text(
                        _sort,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _showSortSheet,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Widok siatki',
                      icon: const Icon(Icons.grid_view),
                      onPressed: () =>
                          showDummy(context, '$_id › Widok siatki'),
                    ),
                  ],
                ),
                if (playlists.isEmpty)
                  const _EmptyLibrary()
                else
                  for (final playlist in playlists)
                    _PlaylistTile(
                      playlist: playlist,
                      onTap: () => _openPlaylist(playlist),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CoverArt(seed: playlist.name, size: 64),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        ['Playlista', ?playlist.owner].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
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
