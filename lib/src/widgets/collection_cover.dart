import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/custom_covers.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../theme_controller.dart';
import 'cover_art.dart';
import 'menu_sheet.dart';
import 'song_cover.dart';

/// The cover of a playlist or mood: the one the user picked ([CustomCovers]), else a collage
/// of its first songs' covers — four different albums in a 2×2 grid, as the reference app does
/// for playlists people make, or the first song's cover when there are fewer — else the
/// placeholder.
class CollectionCover extends StatelessWidget {
  const CollectionCover({
    super.key,
    this.coverKey,
    required this.songs,
    required this.seed,
    this.size = 56,
    this.icon = Icons.queue_music,
  });

  /// Where a picked cover is kept ([CustomCovers.playlistKey], [CustomCovers.moodKey]);
  /// `null` for a playlist not saved in Biblioteka.
  final String? coverKey;

  /// The songs in order, read only up to the fourth different album (may be lazy).
  final Iterable<CoverRequest> songs;
  final String seed;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final key = coverKey;
    final file = key == null
        ? null
        : CustomCoversScope.maybeOf(context)?.fileFor(key);
    final collage = _collage(context);
    if (file == null) return collage;
    final filter = ThemeScope.maybeOf(context)?.coverFilter ?? CoverFilter.none;
    return ClipRRect(
      borderRadius: context.palette.radius(4),
      child: Image(
        image: coverImageFor(context, FileImage(file), size, seed),
        filterQuality: filter == CoverFilter.monochrome
            ? FilterQuality.none
            : FilterQuality.medium,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => collage,
      ),
    );
  }

  Widget _collage(BuildContext context) {
    final albums = <String>{};
    final covers = <CoverRequest>[];
    for (final song in songs) {
      if (albums.add(song.lookupKey)) covers.add(song);
      if (covers.length == 4) break;
    }
    if (covers.isEmpty) return CoverArt(seed: seed, size: size, icon: icon);
    if (covers.length < 4) return SongCover(cover: covers.first, size: size);
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

/// A Biblioteka playlist's [CollectionCover] in a list, from its first tracks
/// ([PlaylistLibrary.leadTracks]) rather than the whole playlist.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, this.size = 56});

  final PlaylistSummary playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final tracks = PlaylistLibraryScope.of(context).leadTracks(playlist.id);
    return CollectionCover(
      coverKey: CustomCovers.playlistKey(playlist),
      // An album is one cover, though its songs may each find it on their own.
      songs:
          (playlist.source == PlaylistSource.spotifyAlbum
                  ? tracks.take(1)
                  : tracks)
              .map(
                (t) =>
                    CoverRequest.of(playlistHit(t, catalog, library, youTube)),
              ),
      seed: playlist.name,
      size: size,
    );
  }
}

/// A mood's [CollectionCover], from its songs in the order its screen lists them.
class MoodCover extends StatelessWidget {
  const MoodCover({super.key, required this.mood, this.size = 56});

  final Mood mood;
  final double size;

  @override
  Widget build(BuildContext context) => CollectionCover(
    coverKey: CustomCovers.moodKey(mood),
    songs: moodHits(
      mood,
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      YouTubeLibraryScope.of(context),
    ).map(CoverRequest.of),
    seed: mood.name,
    size: size,
    icon: Icons.mood,
  );
}

/// "Dodaj okładkę" (or "Zmień okładkę") and "Usuń okładkę" for a playlist's or mood's menu.
List<MenuSheetEntry> customCoverEntries(BuildContext context, String coverKey) {
  final covers = CustomCoversScope.maybeOf(context);
  if (covers == null) return const [];
  final has = covers.fileFor(coverKey) != null;
  return [
    MenuSheetEntry(
      Icons.add_photo_alternate_outlined,
      has ? 'Zmień okładkę' : 'Dodaj okładkę',
      onTap: () => _pickCover(context, covers, coverKey),
    ),
    if (has)
      MenuSheetEntry(
        Icons.hide_image_outlined,
        'Usuń okładkę',
        subtitle: 'Wróci kolaż z okładek utworów',
        onTap: () => covers.remove(coverKey),
      ),
  ];
}

Future<void> _pickCover(
  BuildContext context,
  CustomCovers covers,
  String coverKey,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Wybierz okładkę',
      type: FileType.image,
    );
    final file = picked.firstOrNull;
    if (file == null) return;
    await covers.set(coverKey, await file.readAsBytes());
  } catch (e) {
    debugPrint('Setting a cover failed: $e');
    messenger.showSnackBar(
      const SnackBar(content: Text('Nie udało się wczytać tego obrazu.')),
    );
  }
}
