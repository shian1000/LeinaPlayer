import 'package:flutter/material.dart';

import '../dummy.dart';
import '../sample_content.dart';
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

  void _openItem(LibraryItem item) {
    if (item.kind == LibraryItemKind.playlist) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(title: item.title, owner: item.owner),
        ),
      );
    } else {
      showDummy(context, '$_id › Element: ${item.title}');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Material(
                    color: context.palette.surface,
                    shape: context.palette.boxShape(12),
                    child: ListTile(
                      shape: context.palette.boxShape(12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: const Icon(Icons.download, size: 32),
                      title: const Text(
                        'Importuj swoją muzykę z innych aplikacji',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppFontSize.body,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          showDummy(context, '$_id › Importuj swoją muzykę'),
                    ),
                  ),
                ),
                for (final item in libraryItems)
                  _LibraryTile(item: item, onTap: () => _openItem(item)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.item, required this.onTap});

  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isArtist = item.kind == LibraryItemKind.artist;
    final subtitle = isArtist
        ? item.kindLabel
        : '${item.kindLabel} • ${item.owner}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: item.title == likedSongsTitle
          ? Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: palette.radius(4),
                border: palette.outline == null
                    ? null
                    : Border.all(color: palette.outline!),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette.likedGradient,
                ),
              ),
              child: Icon(Icons.favorite, color: palette.textPrimary),
            )
          : CoverArt(
              seed: item.title,
              size: 64,
              circle: isArtist,
              icon: isArtist ? Icons.person : Icons.music_note,
            ),
      title: Text(item.title),
      subtitle: Row(
        children: [
          if (item.pinned) ...[
            Icon(Icons.push_pin, size: 16, color: palette.accent),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
