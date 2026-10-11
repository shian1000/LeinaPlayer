import 'local_library.dart';
import 'playlist_library.dart';
import 'song_catalog.dart';
import 'source_settings.dart';
import 'text_normalizer.dart';
import 'youtube_library.dart';
import 'youtube_matcher.dart';

/// Whether a search result can be played.
enum SongAvailability {
  /// Can be played now: a file on the phone (pending or not) or a YouTube video stored in
  /// MusicDatabase.
  available,

  /// Not playable as is, but YouTube may find it (no link stored, and not marked "N/A").
  potentiallyAvailable,

  /// Not on the phone and marked in MusicDatabase as not on YouTube.
  unavailable,
}

/// One row of the song search: a MusicDatabase song (possibly also on the phone) or a phone-only
/// song that isn't in MusicDatabase yet.
class SearchHit {
  SearchHit.main(
    CatalogSong song,
    this.phoneFiles, {
    this.phoneMatch,
    this.playlistVideoId,
  }) : mainSong = song,
       title = song.title,
       artistLabel = song.artistLabel,
       album = song.album,
       year = song.year;

  /// A track known only as a YouTube video (e.g. from an imported playlist).
  SearchHit.youTubeOnly({
    required this.title,
    required this.artistLabel,
    required String videoId,
    this.playlistVideoId,
  }) : mainSong = null,
       phoneFiles = const [],
       phoneMatch = videoId,
       album = null,
       year = null;

  SearchHit.phoneOnly(LocalSong file)
    : mainSong = null,
      phoneMatch = null,
      playlistVideoId = null,
      phoneFiles = [file],
      title = file.title,
      artistLabel = file.artist ?? 'Nieznany wykonawca',
      album = file.album,
      year = file.year;

  final CatalogSong? mainSong;

  /// Files on the phone holding this song (from the phone's `local.db`).
  final List<LocalSong> phoneFiles;

  /// A video known on the phone (`youtube_matches`, or a playlist's own video), for a song
  /// music.db has no link for.
  final String? phoneMatch;

  /// This row's video in the YouTube playlist it came from (may differ from music.db's video
  /// of the song), so YouTube can open the song inside that playlist.
  final String? playlistVideoId;

  final String title;
  final String artistLabel;
  final String? album;
  final int? year;

  bool get inMainDatabase => mainSong != null;

  /// The same MusicDatabase song, now with a video the phone found for it.
  SearchHit withPhoneMatch(String videoId) => SearchHit.main(
    mainSong!,
    phoneFiles,
    phoneMatch: videoId,
    playlistVideoId: playlistVideoId,
  );

  /// Seed for the placeholder cover, the same wherever the song is shown.
  String get coverSeed => mainSong != null
      ? '${mainSong!.id}'
      : phoneFiles.isNotEmpty
      ? phoneFiles.first.filePath
      : youtubeVideoId ?? title;

  /// The video to play: music.db's link, else the one the phone found.
  String? get youtubeVideoId => mainSong?.youtubeVideoId ?? phoneMatch;

  /// Phone-only songs aren't in MusicDatabase, so nothing is known about them on YouTube.
  YouTubeLink get youTube => youtubeVideoId != null
      ? YouTubeLink.linked
      : mainSong?.youTube ?? YouTubeLink.unknown;

  MatchTarget get youTubeTarget =>
      mainSong?.youTubeTarget ??
      MatchTarget(title: title, mainArtists: [MatchArtist(artistLabel)]);
  bool get onPhone => phoneFiles.isNotEmpty;

  /// On the phone but not in MusicDatabase yet.
  bool get pending => !inMainDatabase && onPhone;

  /// Whether [source] can play this song right now, without searching.
  bool playableFrom(PlaybackSource source) => switch (source) {
    PlaybackSource.phone => onPhone,
    PlaybackSource.youtube => youTube == YouTubeLink.linked,
  };

  SongAvailability get availability {
    if (PlaybackSource.values.any(playableFrom)) {
      return SongAvailability.available;
    }
    return youTube == YouTubeLink.unknown
        ? SongAvailability.potentiallyAvailable
        : SongAvailability.unavailable;
  }
}

/// Song search over both databases: MusicDatabase's songs (each marked with the phone files that
/// are that song) plus phone songs MusicDatabase doesn't have. Ordered like
/// [SongCatalog.search]: best title matches first, alphabetical within a group.
List<SearchHit> searchEverywhere(
  String query,
  SongCatalog catalog,
  LocalLibrary library, {
  String? Function(int mainDbId)? youTubeMatch,
}) {
  final normalizedQuery = normalizeForSearch(query);
  if (normalizedQuery.isEmpty) return const [];
  final hits = [
    for (final song in catalog.search(query))
      SearchHit.main(
        song,
        library.filesOf(song.id),
        phoneMatch:
            song.youtubeVideoId == null &&
                song.youTube != YouTubeLink.notOnYouTube
            ? youTubeMatch?.call(song.id)
            : null,
      ),
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

/// The row for a playlist track: the MusicDatabase song when it was recognised (by its
/// `main_db_id`, or by the video if music.db has linked it since), with its phone files; otherwise
/// just the playlist's YouTube video.
SearchHit playlistHit(
  PlaylistTrack track,
  SongCatalog catalog,
  LocalLibrary library,
  YouTubeLibrary youTube,
) {
  final videoId = track.youtubeVideoId;
  final song =
      (track.mainDbId == null ? null : catalog.byId(track.mainDbId!)) ??
      (videoId == null ? null : catalog.findByYouTubeId(videoId));
  if (song != null) {
    return SearchHit.main(
      song,
      library.filesOf(song.id),
      // The playlist's own video is the version the user listens to.
      phoneMatch: song.youtubeVideoId == null
          ? videoId ?? youTube.matchFor(song.id)
          : null,
      playlistVideoId: videoId,
    );
  }
  return SearchHit.youTubeOnly(
    title: track.title,
    artistLabel: track.artist ?? 'Nieznany wykonawca',
    videoId: videoId ?? '',
    playlistVideoId: videoId,
  );
}
