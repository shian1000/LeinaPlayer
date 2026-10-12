import 'playlist_library.dart';
import 'text_normalizer.dart';

/// A playlist found by searching YouTube or Spotify, before it's fetched: enough to list it and
/// open its preview.
class FoundPlaylist {
  const FoundPlaylist({
    required this.source,
    required this.id,
    required this.name,
    this.owner,
    this.trackCount,
    this.thumbnail,
  });

  final PlaylistSource source;

  /// The playlist's id there (YouTube `list=`, Spotify `playlist/<id>`).
  final String id;
  final String name;
  final String? owner;
  final int? trackCount;
  final Uri? thumbnail;
}

/// Biblioteka playlists whose name or owner contain every word of [query], normalised like song
/// search.
List<PlaylistSummary> searchSavedPlaylists(
  String query,
  List<PlaylistSummary> playlists,
) {
  final words = normalizeForSearch(query)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  return [
    for (final playlist in playlists)
      if (words.every(
        normalizeForSearch('${playlist.name} ${playlist.owner ?? ''}').contains,
      ))
        playlist,
  ];
}
