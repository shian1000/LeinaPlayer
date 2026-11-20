import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/library_folders.dart';
import '../data/playlist_library.dart';
import '../data/saved_songs.dart';
import '../data/track_ref.dart';
import '../l10n.dart';
import '../theme.dart';
import 'collection_cover.dart';
import 'common.dart';
import 'menu_sheet.dart';
import 'scrolling_text.dart';

/// "Dodaj do playlisty" for a song's menu; `null` where there are no playlists (widget tests).
MenuSheetEntry? playlistMenuEntry(
  BuildContext context,
  List<SearchHit> hits, {
  String? label,
}) {
  if (PlaylistLibraryScope.maybeOf(context) == null || hits.isEmpty) {
    return null;
  }
  return MenuSheetEntry(
    Icons.playlist_add,
    label ?? l10n.playlistPickerAddToPlaylist,
    onTap: () => showAddToPlaylistSheet(context, hits),
  );
}

/// "Dodaj do playlisty ›" unfolding the playlists in the same sheet ([MenuSheetEntry.submenu]):
/// "Polubione utwory", "Nowa playlista", then every saved playlist, those in a Biblioteka folder
/// unfolding under it ([_grouped]); `null` like [playlistMenuEntry].
MenuSheetEntry? playlistSubmenuEntry(
  BuildContext context,
  List<SearchHit> hits,
) {
  final library = PlaylistLibraryScope.maybeOf(context);
  if (library == null || hits.isEmpty) return null;
  final liked = LikedSongsScope.maybeOf(context);
  final folders = LibraryFoldersScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  void said(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
  return MenuSheetEntry(
    Icons.playlist_add,
    l10n.playlistPickerAddToPlaylist,
    submenu: () {
      final held = _heldCounts(library, hits);
      MenuSheetEntry playlistEntry(PlaylistSummary playlist) => MenuSheetEntry(
        Icons.queue_music,
        playlist.name,
        subtitle: _playlistLine(playlist, held[playlist.id] ?? 0, hits.length),
        checked: held[playlist.id] == hits.length,
        onTap: () async {
          said(await togglePlaylist(library, playlist, hits));
        },
      );
      return [
        if (liked != null)
          liked.containsAll(hits)
              ? MenuSheetEntry(
                  Icons.favorite,
                  l10n.playlistPickerUnlike,
                  onTap: () async => said(await toggleLiked(liked, hits)),
                )
              : MenuSheetEntry(
                  Icons.favorite_border,
                  l10n.playlistPickerLike,
                  subtitle: likedSongsLabel,
                  onTap: () async => said(await toggleLiked(liked, hits)),
                ),
        MenuSheetEntry(
          Icons.add,
          l10n.playlistPickerNewPlaylist,
          onTap: () async {
            final name = await askPlaylistName(context);
            if (name == null) return;
            await library.create(name, hits);
            said(l10n.playlistPickerCreated(name));
          },
        ),
        for (final (:folder, :playlists) in _grouped(library, folders))
          if (folder == null)
            playlistEntry(playlists.single)
          else
            MenuSheetEntry(
              Icons.folder_outlined,
              folder.name,
              subtitle: _folderLine(playlists, held, hits.length),
              submenu: () => [for (final p in playlists) playlistEntry(p)],
            ),
      ];
    },
  );
}

/// [library]'s playlists in its order, those in one of Biblioteka's [folders] gathered under it,
/// where the first of them would be; a playlist in no folder stands alone (`folder` `null`).
List<({LibraryFolder? folder, List<PlaylistSummary> playlists})> _grouped(
  PlaylistLibrary library,
  LibraryFolders? folders,
) {
  final folderOf = <String, LibraryFolder>{
    for (final folder in folders?.folders ?? const <LibraryFolder>[])
      for (final key in folder.items) key: folder,
  };
  final groups = <({LibraryFolder? folder, List<PlaylistSummary> playlists})>[];
  final inFolder = <String, List<PlaylistSummary>>{};
  for (final playlist in library.playlists) {
    final folder = folderOf[LibraryFolders.playlistKey(playlist.id)];
    if (folder == null) {
      groups.add((folder: null, playlists: [playlist]));
    } else if (inFolder[folder.id] case final list?) {
      list.add(playlist);
    } else {
      groups.add((folder: folder, playlists: inFolder[folder.id] = [playlist]));
    }
  }
  return groups;
}

/// A folder's number of playlists and how many of them already have all of the songs.
String _folderLine(
  List<PlaylistSummary> playlists,
  Map<int, int> held,
  int songs,
) {
  final n = playlists.length;
  final size = l10n.playlistPickerFolderSize(n);
  final holding = playlists.where((p) => held[p.id] == songs).length;
  return holding == 0 ? size : l10n.playlistPickerAlreadyIn(size, holding);
}

/// How many of [hits] each playlist already has, by its id.
Map<int, int> _heldCounts(PlaylistLibrary library, List<SearchHit> hits) {
  final counts = <int, int>{};
  for (final hit in hits) {
    for (final id in library.playlistsWith(hit)) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
}

/// A playlist's size and, while choosing for several songs, how many of them it already has.
String _playlistLine(PlaylistSummary playlist, int held, int songs) {
  final size = l10n.songsCount(playlist.trackCount);
  return held == 0 || held == songs
      ? size
      : l10n.playlistPickerAlreadyHere(size, held, songs);
}

/// Adds those of [hits] the playlist doesn't have yet, or takes them out when it has them all;
/// returns what to tell the user.
Future<String> togglePlaylist(
  PlaylistLibrary library,
  PlaylistSummary playlist,
  List<SearchHit> hits,
) async {
  final seen = <String>{};
  final missing = [
    for (final hit in hits)
      if (!library.playlistsWith(hit).contains(playlist.id) &&
          seen.add(TrackRef.of(hit).key))
        hit,
  ];
  if (missing.isEmpty) {
    await library.removeSongs(playlist.id, hits);
    return l10n.playlistPickerRemovedFrom(playlist.name);
  }
  await library.addSongs(playlist.id, missing);
  return l10n.playlistPickerAddedTo(playlist.name);
}

String get likedSongsLabel => l10n.playlistPickerLikedSongs;

/// Likes [hits], or takes them out of the liked songs when all of them are liked already;
/// returns what to tell the user.
Future<String> toggleLiked(LikedSongs liked, List<SearchHit> hits) async {
  final like = !liked.containsAll(hits);
  await liked.setAll(hits, like);
  return like ? l10n.playlistPickerLiked : l10n.playlistPickerUnliked;
}

/// The liked songs' cover: a heart on the accent colour, like Spotify's.
class LikedSongsCover extends StatelessWidget {
  const LikedSongsCover({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: palette.radius(4),
        ),
        child: Icon(Icons.favorite, color: palette.onAccent, size: size / 2),
      ),
    );
  }
}

/// Asks for a name; `null` when cancelled or left empty.
Future<String?> askPlaylistName(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => TextInputDialog(
      title: l10n.playlistPickerNewPlaylist,
      hint: l10n.playlistPickerNameHint,
      initial: '',
    ),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Puts [hits] at the end of a saved playlist or into a new one, or takes them out of a playlist
/// holding them all ([togglePlaylist]); playlists in a Biblioteka folder unfold under it
/// ([_grouped]).
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  List<SearchHit> hits,
) {
  final library = PlaylistLibraryScope.of(context);
  final liked = LikedSongsScope.maybeOf(context);
  final folders = LibraryFoldersScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final what = hits.length == 1
      ? hits.single.title
      : l10n.songsCount(hits.length);
  void said(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      final held = _heldCounts(library, hits);
      final groups = _grouped(library, folders);
      final open = <String>{};
      Widget playlistTile(PlaylistSummary playlist, {double indent = 20}) =>
          ListTile(
            contentPadding: EdgeInsets.only(left: indent, right: 20),
            leading: PlaylistCover(playlist: playlist, size: 48),
            title: ScrollingText(playlist.name),
            subtitle: Text(
              _playlistLine(playlist, held[playlist.id] ?? 0, hits.length),
            ),
            trailing: held[playlist.id] == hits.length
                ? Icon(Icons.check_circle, color: palette.accent)
                : Icon(Icons.add_circle_outline, color: palette.textSecondary),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              said(await togglePlaylist(library, playlist, hits));
            },
          );

      return StatefulBuilder(
        builder: (sheetContext, setState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              MenuSheetHeader(
                cover: const Icon(Icons.playlist_add, size: 40),
                title: l10n.playlistPickerAddToPlaylist,
                subtitle: what,
              ),
              const Divider(),
              if (liked != null)
                ListenableBuilder(
                  listenable: liked,
                  builder: (_, _) {
                    final all = liked.containsAll(hits);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      leading: const LikedSongsCover(),
                      title: Text(likedSongsLabel),
                      subtitle: Text(l10n.songsCount(liked.songs.length)),
                      trailing: Icon(
                        all ? Icons.favorite : Icons.favorite_border,
                        color: all ? palette.accent : palette.textSecondary,
                      ),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        said(await toggleLiked(liked, hits));
                      },
                    );
                  },
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Icon(Icons.add, color: palette.textSecondary),
                title: Text(l10n.playlistPickerNewPlaylist),
                onTap: () async {
                  final navigator = Navigator.of(sheetContext);
                  final name = await askPlaylistName(sheetContext);
                  if (name == null) return;
                  navigator.pop();
                  await library.create(name, hits);
                  said(l10n.playlistPickerCreated(name));
                },
              ),
              for (final (:folder, :playlists) in groups)
                if (folder == null)
                  playlistTile(playlists.single)
                else ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: const FolderCover(size: 48),
                    title: ScrollingText(folder.name),
                    subtitle: Text(_folderLine(playlists, held, hits.length)),
                    trailing: Icon(
                      open.contains(folder.id)
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: palette.textSecondary,
                    ),
                    onTap: () => setState(() {
                      if (!open.remove(folder.id)) open.add(folder.id);
                    }),
                  ),
                  if (open.contains(folder.id))
                    for (final playlist in playlists)
                      playlistTile(playlist, indent: 44),
                ],
            ],
          ),
        ),
      );
    },
  );
}
