import 'local_library.dart';
import 'playlist_library.dart';
import 'song_catalog.dart';
import 'source_settings.dart';
import 'text_normalizer.dart';
import 'youtube_library.dart';
import 'youtube_matcher.dart';

/// Whether a search result can be played.
enum SongAvailability {
  /// Can be played now: a file on the phone (pending or not) or on MusicDatabase's server, or a
  /// YouTube video stored in MusicDatabase.
  available,

  /// Not playable as is, but YouTube may find it (no link stored, and not marked "N/A").
  potentiallyAvailable,

  /// Not on the phone or the server and marked in MusicDatabase as not on YouTube.
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
    this.spotifyTrackId,
    this.notFoundOnYouTube = false,
  }) : mainSong = song,
       mainVideoRemoved = false,
       title = song.title,
       artistLabel = song.artistLabel,
       album = song.album,
       year = song.year;

  /// A track known only as a YouTube video (e.g. from an imported playlist), or with no
  /// [videoId] only by its title and artist (a Spotify playlist's), to be found on YouTube.
  SearchHit.youTubeOnly({
    required this.title,
    required this.artistLabel,
    required String? videoId,
    this.playlistVideoId,
    this.spotifyTrackId,
    this.notFoundOnYouTube = false,
  }) : mainSong = null,
       mainVideoRemoved = false,
       phoneFiles = const [],
       phoneMatch = videoId,
       album = null,
       year = null;

  SearchHit.phoneOnly(LocalSong file)
    : mainSong = null,
      mainVideoRemoved = false,
      phoneMatch = null,
      playlistVideoId = null,
      spotifyTrackId = null,
      notFoundOnYouTube = false,
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

  /// The track on Spotify it came from (a Spotify playlist's), for sharing; see [spotifyUri].
  final String? spotifyTrackId;

  /// The phone searched YouTube for it lately and found nothing ([YouTubeLink.notFound]).
  final bool notFoundOnYouTube;

  /// YouTube no longer has music.db's video of the song (`youtube_removed_videos`): until
  /// MusicDatabase changes the link, the song is treated as having none, so the phone looks for
  /// another video ([phoneMatch]).
  final bool mainVideoRemoved;

  final String title;
  final String artistLabel;
  final String? album;
  final int? year;

  bool get inMainDatabase => mainSong != null;

  /// Latin forms of [title], [artistLabel] and [album] from music.db, for names in another
  /// alphabet (`latin_names.dart`); `null` for songs music.db doesn't have.
  String? get titleLatin => mainSong?.titleLatin;
  String? get artistLatin => mainSong?.artistLatin;
  String? get albumLatin => mainSong?.albumLatin;

  SearchHit._copy(
    SearchHit hit, {
    required this.phoneMatch,
    required this.notFoundOnYouTube,
    bool keepPlaylistVideo = true,
    bool? mainVideoRemoved,
  }) : mainSong = hit.mainSong,
       mainVideoRemoved = mainVideoRemoved ?? hit.mainVideoRemoved,
       phoneFiles = hit.phoneFiles,
       playlistVideoId = keepPlaylistVideo ? hit.playlistVideoId : null,
       spotifyTrackId = hit.spotifyTrackId,
       title = hit.title,
       artistLabel = hit.artistLabel,
       album = hit.album,
       year = hit.year;

  /// The same song, marked as searched on YouTube without result (or, with `false`, not).
  SearchHit withNotFoundOnYouTube([bool notFound = true]) =>
      SearchHit._copy(this, phoneMatch: null, notFoundOnYouTube: notFound);

  /// The same song without the phone's or the playlist's video (YouTube removed it); with
  /// [mainVideo] also without MusicDatabase's own link ([mainVideoRemoved]).
  SearchHit withoutVideo({bool mainVideo = false}) => SearchHit._copy(
    this,
    phoneMatch: null,
    notFoundOnYouTube: false,
    keepPlaylistVideo: false,
    mainVideoRemoved: mainVideo || mainVideoRemoved,
  );

  /// The same song, now with a video the phone found for it.
  SearchHit withPhoneMatch(String videoId) =>
      SearchHit._copy(this, phoneMatch: videoId, notFoundOnYouTube: false);

  /// The song's page on Spotify: MusicDatabase's own link, else the Spotify playlist's track.
  Uri? get spotifyUri {
    final id = mainSong?.spotifyTrackId ?? spotifyTrackId;
    return id == null ? null : Uri.https('open.spotify.com', '/track/$id');
  }

  /// Seed for the placeholder cover, the same wherever the song is shown.
  String get coverSeed => mainSong != null
      ? '${mainSong!.id}'
      : phoneFiles.isNotEmpty
      ? phoneFiles.first.filePath
      : youtubeVideoId ?? title;

  /// The video to play: music.db's link (unless YouTube removed it), else the one the phone
  /// found.
  String? get youtubeVideoId =>
      (mainVideoRemoved ? null : mainSong?.youtubeVideoId) ?? phoneMatch;

  /// Phone-only songs aren't in MusicDatabase, so nothing is known about them on YouTube.
  YouTubeLink get youTube {
    if (youtubeVideoId != null) return YouTubeLink.linked;
    final stored = mainVideoRemoved
        ? YouTubeLink.unknown
        : mainSong?.youTube ?? YouTubeLink.unknown;
    return stored == YouTubeLink.unknown && notFoundOnYouTube
        ? YouTubeLink.notFound
        : stored;
  }

  MatchTarget get youTubeTarget =>
      mainSong?.youTubeTarget ??
      MatchTarget(title: title, mainArtists: [MatchArtist(artistLabel)]);
  bool get onPhone => phoneFiles.isNotEmpty;

  /// The song's file on MusicDatabase's server ([PlaybackSource.server]).
  ServerFile? get serverFile => mainSong?.serverFile;

  /// On the phone but not in MusicDatabase yet.
  bool get pending => !inMainDatabase && onPhone;

  /// Whether [source] can play this song right now, without searching.
  bool playableFrom(PlaybackSource source) => switch (source) {
    PlaybackSource.phone => onPhone,
    PlaybackSource.server => serverFile != null,
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

/// [hit] with what the phone has learned about it on YouTube since the row was made: a video it
/// found (`youtube_matches`, `youtube_track_matches`) or that it searched lately and found none
/// (`youtube_not_found`), and dropping a video YouTube removed (`youtube_removed_videos`) — a
/// playlist's, a phone-found one, or music.db's own, which is then replaced by a phone-found one
/// until MusicDatabase changes the link (ADR 0003: the phone only fills the gap) — and a video
/// MusicDatabase turned down ([YouTubeLibrary.useBadVideos]). Queues and saved
/// rows hold songs as they were, so they're shown and played through this.
SearchHit withPhoneYouTube(SearchHit hit, YouTubeLibrary youTube) {
  final video = hit.youtubeVideoId;
  if (video != null) {
    final own = hit.mainSong;
    final turnedDown =
        own != null &&
        video != own.youtubeVideoId &&
        youTube.isWrongFor(own.id, video);
    if (!youTube.isVideoRemoved(video) && !turnedDown) return hit;
    hit = hit.withoutVideo(mainVideo: hit.mainSong?.youtubeVideoId == video);
  }
  final mainSong = hit.mainSong;
  // A phone-only song stays one: it plays from its file.
  if (mainSong == null && hit.onPhone) return hit;
  if (mainSong != null &&
      !hit.mainVideoRemoved &&
      mainSong.youTube != YouTubeLink.unknown) {
    return hit;
  }
  final videoId = mainSong != null
      ? youTube.matchFor(mainSong.id)
      : youTube.matchForTrack(hit.artistLabel, hit.title);
  if (videoId != null) return hit.withPhoneMatch(videoId);
  final notFound = mainSong != null
      ? youTube.notFoundSong(mainSong.id)
      : youTube.notFoundTrack(hit.artistLabel, hit.title);
  if (notFound == hit.notFoundOnYouTube) return hit;
  return hit.withNotFoundOnYouTube(notFound);
}

/// Song search over both databases: MusicDatabase's songs (each marked with the phone files that
/// are that song) plus phone songs MusicDatabase doesn't have. Ordered like
/// [SongCatalog.search]: best title matches first, alphabetical within a group.
List<SearchHit> searchEverywhere(
  String query,
  SongCatalog catalog,
  LocalLibrary library, {
  YouTubeLibrary? youTube,
}) {
  final normalizedQuery = normalizeForSearch(query);
  if (normalizedQuery.isEmpty) return const [];
  final hits = [
    for (final song in catalog.search(query))
      if (youTube == null)
        SearchHit.main(song, library.filesOf(song.id))
      else
        withPhoneYouTube(
          SearchHit.main(song, library.filesOf(song.id)),
          youTube,
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
/// just the playlist's YouTube video, or a phone file not in MusicDatabase with the same title and
/// artist (a saved queue's), or — with none (Spotify) — its title and artist; with what
/// the phone learned on YouTube since ([withPhoneYouTube]).
SearchHit playlistHit(
  PlaylistTrack track,
  SongCatalog catalog,
  LocalLibrary library,
  YouTubeLibrary youTube,
) {
  final videoId = track.playableVideoId;
  final song =
      (track.mainDbId == null ? null : catalog.byId(track.mainDbId!)) ??
      (videoId == null ? null : catalog.findByYouTubeId(videoId));
  if (song != null) {
    return withPhoneYouTube(
      SearchHit.main(
        song,
        library.filesOf(song.id),
        // The playlist's own video is the version the user listens to.
        phoneMatch: song.youtubeVideoId == null ? videoId : null,
        playlistVideoId: videoId,
        spotifyTrackId: track.spotifyTrackId,
      ),
      youTube,
    );
  }
  if (videoId == null && track.spotifyTrackId == null) {
    final file = library.pendingFile(title: track.title, artist: track.artist);
    if (file != null) return SearchHit.phoneOnly(file);
  }
  return withPhoneYouTube(
    SearchHit.youTubeOnly(
      title: track.title,
      artistLabel: track.artist ?? 'Nieznany wykonawca',
      videoId: videoId,
      playlistVideoId: videoId,
      spotifyTrackId: track.spotifyTrackId,
    ),
    youTube,
  );
}
