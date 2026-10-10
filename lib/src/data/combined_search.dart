import 'local_library.dart';
import 'song_catalog.dart';
import 'text_normalizer.dart';

/// Whether a search result can be played.
enum SongAvailability {
  /// Can be played now — currently: a file on the phone (pending or not).
  available,

  /// Could become playable (e.g. streamed or downloaded); nothing lands here yet.
  potentiallyAvailable,

  /// Everything else.
  unavailable,
}

/// One row of the song search: a MusicDatabase song (possibly also on the phone) or a phone-only
/// song that isn't in MusicDatabase yet.
class SearchHit {
  SearchHit.main(CatalogSong song, this.phoneFiles)
    : mainSong = song,
      title = song.title,
      artistLabel = song.artistLabel,
      album = song.album,
      year = song.year;

  SearchHit.phoneOnly(LocalSong file)
    : mainSong = null,
      phoneFiles = [file],
      title = file.title,
      artistLabel = file.artist ?? 'Nieznany wykonawca',
      album = file.album,
      year = file.year;

  final CatalogSong? mainSong;

  /// Files on the phone holding this song (from the phone's `local.db`).
  final List<LocalSong> phoneFiles;

  final String title;
  final String artistLabel;
  final String? album;
  final int? year;

  bool get inMainDatabase => mainSong != null;
  bool get onPhone => phoneFiles.isNotEmpty;

  /// On the phone but not in MusicDatabase yet.
  bool get pending => !inMainDatabase && onPhone;

  SongAvailability get availability =>
      onPhone ? SongAvailability.available : SongAvailability.unavailable;
}

/// Song search over both databases: MusicDatabase's songs (each marked with the phone files that
/// are that song) plus phone songs MusicDatabase doesn't have. Ordered like
/// [SongCatalog.search]: best title matches first, alphabetical within a group.
List<SearchHit> searchEverywhere(
  String query,
  SongCatalog catalog,
  LocalLibrary library,
) {
  final normalizedQuery = normalizeForSearch(query);
  if (normalizedQuery.isEmpty) return const [];
  final hits = [
    for (final song in catalog.search(query))
      SearchHit.main(song, library.filesOf(song.id)),
    for (final file in library.searchPending(query, catalog.searchFields))
      SearchHit.phoneOnly(file),
  ];
  final keys = {
    for (final hit in hits)
      hit: (
        titleMatchRank(normalizeForSearch(hit.title), normalizedQuery),
        normalizeForSearch(hit.title),
      ),
  };
  hits.sort((a, b) {
    final (rankA, titleA) = keys[a]!;
    final (rankB, titleB) = keys[b]!;
    return rankA != rankB ? rankA.compareTo(rankB) : titleA.compareTo(titleB);
  });
  return hits;
}
