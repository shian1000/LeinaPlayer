import 'dart:math';

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
import 'mood_sheet.dart';
import 'song_cover.dart';

/// The cover of a playlist or mood: the one the user picked ([CustomCovers]), else a collage
/// of its first songs' covers — four different albums in a 2×2 grid, as the reference app does
/// for playlists people make, or the first song's cover when there are fewer — else the
/// placeholder.
class CollectionCover extends StatelessWidget {
  const CollectionCover({
    super.key,
    this.cover,
    required this.songs,
    required this.seed,
    this.size = 56,
    this.icon = Icons.queue_music,
  });

  /// The picked cover's hash ([PlaylistSummary.cover], [Mood.cover]). Until its picture is on
  /// the phone (downloaded with the next sync) the collage shows.
  final String? cover;

  /// The songs in order, read only up to the fourth different album (may be lazy).
  final Iterable<CoverRequest> songs;
  final String seed;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final file = CustomCoversScope.maybeOf(context)?.fileFor(cover);
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

/// What a cover in a list stands for, told apart by its outline even without the picture
/// (after Juxtopposed's Spotify redesign): an album has one sleeve edge above it, a playlist a
/// stack of them, a mood rounder corners and a crescent in the corner.
enum CollectionKind { album, playlist, mood }

/// [CollectionKind]'s outline around a cover of [size] in all; [builder] draws the cover
/// itself at the size left for it.
class CollectionFrame extends StatelessWidget {
  const CollectionFrame({
    super.key,
    required this.kind,
    required this.size,
    required this.builder,
  });

  final CollectionKind kind;
  final double size;
  final Widget Function(double coverSize) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // A ListTile's leading may be lower than asked for.
    builder: (context, constraints) =>
        _frame(context, min(size, constraints.maxHeight)),
  );

  Widget _frame(BuildContext context, double size) {
    final palette = context.palette;
    final edge = (size / 22).clamp(2.0, 4.0);
    Widget sleeve(double widthFactor, double alpha) => Container(
      width: size * widthFactor,
      height: edge,
      margin: EdgeInsets.only(bottom: edge / 2),
      decoration: BoxDecoration(
        color: palette.textSecondary.withValues(alpha: alpha),
        borderRadius: palette.radius(edge),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: switch (kind) {
        CollectionKind.album => Column(
          children: [sleeve(0.92, 0.5), builder(size - edge * 1.5)],
        ),
        CollectionKind.playlist => Column(
          children: [
            sleeve(0.76, 0.3),
            sleeve(0.88, 0.55),
            builder(size - edge * 3),
          ],
        ),
        CollectionKind.mood => Stack(
          children: [
            ClipRRect(
              borderRadius: palette.radius(size / 4),
              child: builder(size),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: palette.background.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  moodIcon,
                  size: (size / 4).clamp(10.0, 18.0),
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      },
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
    final album = playlist.source == PlaylistSource.spotifyAlbum;
    return CollectionFrame(
      kind: album ? CollectionKind.album : CollectionKind.playlist,
      size: size,
      builder: (coverSize) => CollectionCover(
        cover: playlist.cover,
        // An album is one cover, though its songs may each find it on their own.
        songs: (album ? tracks.take(1) : tracks).map(
          (t) => CoverRequest.of(playlistHit(t, catalog, library, youTube)),
        ),
        seed: playlist.name,
        size: coverSize,
      ),
    );
  }
}

/// A mood's [CollectionCover], from its songs in the order its screen lists them.
class MoodCover extends StatelessWidget {
  const MoodCover({super.key, required this.mood, this.size = 56});

  final Mood mood;
  final double size;

  @override
  Widget build(BuildContext context) => CollectionFrame(
    kind: CollectionKind.mood,
    size: size,
    builder: (coverSize) => CollectionCover(
      cover: mood.cover,
      songs: moodHits(
        mood,
        SongCatalogScope.of(context),
        LocalLibraryScope.of(context),
        YouTubeLibraryScope.of(context),
      ).map(CoverRequest.of),
      seed: mood.name,
      size: coverSize,
      icon: moodIcon,
    ),
  );
}

/// "Dodaj okładkę" (or "Zmień okładkę") and "Usuń okładkę" for a playlist's or mood's menu;
/// [onSet] saves the new cover's hash (`null`: removed) where it belongs.
List<MenuSheetEntry> customCoverEntries(
  BuildContext context, {
  required String? current,
  required Future<void> Function(String? hash) onSet,
}) {
  final covers = CustomCoversScope.maybeOf(context);
  if (covers == null) return const [];
  return [
    MenuSheetEntry(
      Icons.add_photo_alternate_outlined,
      current == null ? 'Dodaj okładkę' : 'Zmień okładkę',
      onTap: () => _pickCover(context, covers, onSet),
    ),
    if (current != null)
      MenuSheetEntry(
        Icons.hide_image_outlined,
        'Usuń okładkę',
        subtitle: 'Wróci kolaż z okładek utworów',
        onTap: () => onSet(null),
      ),
  ];
}

Future<void> _pickCover(
  BuildContext context,
  CustomCovers covers,
  Future<void> Function(String? hash) onSet,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Wybierz okładkę',
      type: FileType.image,
    );
    final file = picked.firstOrNull;
    if (file == null) return;
    await onSet(await covers.add(await file.readAsBytes()));
  } catch (e) {
    debugPrint('Setting a cover failed: $e');
    messenger.showSnackBar(
      const SnackBar(content: Text('Nie udało się wczytać tego obrazu.')),
    );
  }
}
