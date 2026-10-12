import 'combined_search.dart';
import 'local_library.dart';
import 'song_catalog.dart';
import 'youtube_library.dart';

/// What identifies a song across app restarts (the saved queue, the history): the MusicDatabase
/// song, else the phone file, else the YouTube video — plus the title/artist shown when it was
/// played, used when none of those can be found any more.
class TrackRef {
  const TrackRef({
    required this.title,
    this.artist,
    this.mainDbId,
    this.filePath,
    this.videoId,
    this.playlistVideoId,
    this.spotifyTrackId,
  });

  factory TrackRef.of(SearchHit hit) => TrackRef(
    title: hit.title,
    artist: hit.artistLabel,
    mainDbId: hit.mainSong?.id,
    filePath: hit.onPhone ? hit.phoneFiles.first.filePath : null,
    videoId: hit.youtubeVideoId,
    playlistVideoId: hit.playlistVideoId,
    spotifyTrackId: hit.spotifyTrackId,
  );

  factory TrackRef.fromJson(Map<String, Object?> json) => TrackRef(
    title: json['title'] as String,
    artist: json['artist'] as String?,
    mainDbId: json['main_db_id'] as int?,
    filePath: json['file_path'] as String?,
    videoId: json['video_id'] as String?,
    playlistVideoId: json['playlist_video_id'] as String?,
    spotifyTrackId: json['spotify_track_id'] as String?,
  );

  final String title;
  final String? artist;
  final int? mainDbId;
  final String? filePath;
  final String? videoId;

  /// [SearchHit.playlistVideoId].
  final String? playlistVideoId;

  /// [SearchHit.spotifyTrackId].
  final String? spotifyTrackId;

  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'main_db_id': mainDbId,
    'file_path': filePath,
    'video_id': videoId,
    if (playlistVideoId != null) 'playlist_video_id': playlistVideoId,
    if (spotifyTrackId != null) 'spotify_track_id': spotifyTrackId,
  };

  /// Same song (for grouping the history).
  String get key => mainDbId != null
      ? 'db:$mainDbId'
      : filePath != null
      ? 'file:$filePath'
      : 'yt:$videoId:$title';
}

/// Turns a [TrackRef] back into a playable row, with what the phone knows about it now.
SearchHit resolveTrack(
  TrackRef ref,
  SongCatalog catalog,
  LocalLibrary library,
  YouTubeLibrary youTube,
) {
  final song = ref.mainDbId == null ? null : catalog.byId(ref.mainDbId!);
  if (song != null) {
    return withPhoneYouTube(
      SearchHit.main(
        song,
        library.filesOf(song.id),
        phoneMatch: song.youtubeVideoId == null ? ref.videoId : null,
        playlistVideoId: ref.playlistVideoId,
        spotifyTrackId: ref.spotifyTrackId,
      ),
      youTube,
    );
  }
  final file = ref.filePath == null ? null : library.fileAt(ref.filePath!);
  if (file != null) return SearchHit.phoneOnly(file);
  // No file either: a video, or a track known only by name (from a Spotify playlist).
  if (ref.videoId != null || ref.filePath == null) {
    return withPhoneYouTube(
      SearchHit.youTubeOnly(
        title: ref.title,
        artistLabel: ref.artist ?? 'Nieznany wykonawca',
        videoId: ref.videoId,
        playlistVideoId: ref.playlistVideoId,
        spotifyTrackId: ref.spotifyTrackId,
      ),
      youTube,
    );
  }
  // The file is gone and nothing else knows the song: shown, but can't be played.
  return SearchHit.phoneOnly(
    LocalSong(
      id: 0,
      filePath: ref.filePath!,
      title: ref.title,
      artist: ref.artist,
      pending: true,
    ),
  );
}
