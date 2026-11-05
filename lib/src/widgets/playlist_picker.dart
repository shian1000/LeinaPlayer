import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/playlist_library.dart';
import '../data/saved_songs.dart';
import '../data/track_ref.dart';
import '../theme.dart';
import 'collection_cover.dart';
import 'common.dart';
import 'menu_sheet.dart';
import 'scrolling_text.dart';

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

/// "Dodaj do playlisty ›" unfolding the playlists in the same sheet ([MenuSheetEntry.submenu]):
/// "Polubione utwory", "Nowa playlista", then every playlist made on the phone; `null` like
/// [playlistMenuEntry].
MenuSheetEntry? playlistSubmenuEntry(
  BuildContext context,
  List<SearchHit> hits,
) {
  final library = PlaylistLibraryScope.maybeOf(context);
  if (library == null || hits.isEmpty) return null;
  final liked = LikedSongsScope.maybeOf(context);
  final messenger = ScaffoldMessenger.of(context);
  void said(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
  return MenuSheetEntry(
    Icons.playlist_add,
    'Dodaj do playlisty',
    submenu: () {
      final held = _heldCounts(library, hits);
      return [
        if (liked != null)
          liked.containsAll(hits)
              ? MenuSheetEntry(
                  Icons.favorite,
                  'Usuń z polubionych',
                  onTap: () async => said(await toggleLiked(liked, hits)),
                )
              : MenuSheetEntry(
                  Icons.favorite_border,
                  'Polub',
                  subtitle: likedSongsLabel,
                  onTap: () async => said(await toggleLiked(liked, hits)),
                ),
        MenuSheetEntry(
          Icons.add,
          'Nowa playlista',
          onTap: () async {
            final name = await askPlaylistName(context);
            if (name == null) return;
            await library.create(name, hits);
            said('Utworzono playlistę „$name”');
          },
        ),
        for (final playlist in library.playlists)
          MenuSheetEntry(
            Icons.queue_music,
            playlist.name,
            subtitle: _playlistLine(
              playlist,
              held[playlist.id] ?? 0,
              hits.length,
            ),
            checked: held[playlist.id] == hits.length,
            onTap: () async {
              said(await togglePlaylist(library, playlist, hits));
            },
          ),
      ];
    },
  );
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
  final size = '${playlist.trackCount} ${songsWord(playlist.trackCount)}';
  return held == 0 || held == songs ? size : '$size · już tu: $held z $songs';
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
    return 'Usunięto z playlisty „${playlist.name}”';
  }
  await library.addSongs(playlist.id, missing);
  return 'Dodano do playlisty „${playlist.name}”';
}

const likedSongsLabel = 'Polubione utwory';

/// Likes [hits], or takes them out of the liked songs when all of them are liked already;
/// returns what to tell the user.
Future<String> toggleLiked(LikedSongs liked, List<SearchHit> hits) async {
  final like = !liked.containsAll(hits);
  await liked.setAll(hits, like);
  return like ? 'Dodano do polubionych' : 'Usunięto z polubionych';
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
    builder: (_) => const TextInputDialog(
      title: 'Nowa playlista',
      hint: 'Nazwa playlisty',
      initial: '',
    ),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Puts [hits] at the end of a saved playlist or into a new one, or takes them out of a playlist
/// holding them all ([togglePlaylist]).
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  List<SearchHit> hits,
) {
  final library = PlaylistLibraryScope.of(context);
  final liked = LikedSongsScope.maybeOf(context);
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
      final held = _heldCounts(library, hits);
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
            if (liked != null)
              ListenableBuilder(
                listenable: liked,
                builder: (_, _) {
                  final all = liked.containsAll(hits);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: const LikedSongsCover(),
                    title: const Text(likedSongsLabel),
                    subtitle: Text(
                      '${liked.songs.length} ${songsWord(liked.songs.length)}',
                    ),
                    trailing: Icon(
                      all ? Icons.check_circle : Icons.add_circle_outline,
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
            for (final playlist in library.playlists)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: PlaylistCover(playlist: playlist, size: 48),
                title: ScrollingText(playlist.name),
                subtitle: Text(
                  _playlistLine(playlist, held[playlist.id] ?? 0, hits.length),
                ),
                trailing: held[playlist.id] == hits.length
                    ? Icon(Icons.check_circle, color: palette.accent)
                    : Icon(
                        Icons.add_circle_outline,
                        color: palette.textSecondary,
                      ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  said(await togglePlaylist(library, playlist, hits));
                },
              ),
          ],
        ),
      );
    },
  );
}
