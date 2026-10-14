import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/playlist_library.dart';
import '../theme.dart';
import 'collection_cover.dart';
import 'common.dart';
import 'menu_sheet.dart';

/// "Dodaj do playlisty" for a song's menu; `null` where there are no playlists (widget tests).
MenuSheetEntry? playlistMenuEntry(
  BuildContext context,
  List<SearchHit> hits, {
  String label = 'Dodaj do playlisty',
}) {
  if (PlaylistLibraryScope.maybeOf(context) == null || hits.isEmpty) {
    return null;
  }
  return MenuSheetEntry(
    Icons.playlist_add,
    label,
    onTap: () => showAddToPlaylistSheet(context, hits),
  );
}

/// Asks for a name; `null` when cancelled or left empty.
Future<String?> askPlaylistName(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const TextInputDialog(
      title: 'Nowa playlista',
      hint: 'Nazwa playlisty',
      initial: '',
    ),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Puts [hits] at the end of a playlist made on the phone, or into a new one. Imported
/// playlists aren't offered: importing them again would drop what was added.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  List<SearchHit> hits,
) {
  final library = PlaylistLibraryScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final what = hits.length == 1
      ? hits.single.title
      : '${hits.length} ${songsWord(hits.length)}';
  void said(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      final editable = library.editable;
      final imported = library.playlists.length - editable.length;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            MenuSheetHeader(
              cover: const Icon(Icons.playlist_add, size: 40),
              title: 'Dodaj do playlisty',
              subtitle: what,
            ),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.add, color: palette.textSecondary),
              title: const Text('Nowa playlista'),
              onTap: () async {
                final navigator = Navigator.of(sheetContext);
                final name = await askPlaylistName(sheetContext);
                if (name == null) return;
                navigator.pop();
                await library.create(name, hits);
                said('Utworzono playlistę „$name”');
              },
            ),
            for (final playlist in editable)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: PlaylistCover(playlist: playlist, size: 48),
                title: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${playlist.trackCount} ${songsWord(playlist.trackCount)}',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await library.addSongs(playlist.id, hits);
                  said('Dodano do playlisty „${playlist.name}”');
                },
              ),
            if (imported > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'Playlist zaimportowanych z YouTube i Spotify nie można tu '
                  'zmieniać — ponowny import zastąpiłby dodane utwory.',
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
          ],
        ),
      );
    },
  );
}
