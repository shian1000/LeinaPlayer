import 'package:sqlite3/sqlite3.dart';

import 'combined_search.dart';
import 'text_normalizer.dart';
import 'youtube_playlist.dart';

/// A song the phone plays that music.db doesn't have, asked to be added to MusicDatabase
/// (the outbox's `song_requests`, hand-off `docs/handoffs/musicdatabase-song-requests.md`).
/// MusicDatabase's owner adds it, leaves it for later or rejects it; a rejected one comes back
/// in music.db's `rejected_song_requests` ([RejectedSongRequests]) and isn't asked for again.
class SongRequest {
  const SongRequest({
    required this.title,
    required this.artist,
    required this.source,
    this.album,
    this.year,
    this.youtubeVideoId,
    this.spotifyTrackId,
    this.duration,
  });

  /// What [hit] would be asked as; `null` for a song music.db has, or one with no title.
  /// [artistNamed] (`SongCatalog.artistNamed`) gives music.db's name of an artist known by
  /// another name: a video's channel or a file's tag may be one of its `artists.synonyms`
  /// ("familyboombox" is "Бумбокс"), and the request then asks for the artist music.db has.
  /// A video's title loses the junk an older import left in it ([requestTitleOfVideo]).
  static SongRequest? of(
    SearchHit hit, {
    String? Function(String name)? artistNamed,
  }) {
    if (hit.inMainDatabase || hit.title.trim().isEmpty) return null;
    final file = hit.onPhone ? hit.phoneFiles.first : null;
    final shown = file != null ? file.artist : hit.artistLabel;
    final artist = shown == null || shown == unknownArtist
        ? null
        : artistNamed?.call(shown) ?? shown;
    final videoId = hit.playlistVideoId ?? hit.youtubeVideoId;
    final source = file != null
        ? SongRequestSource.phoneFile
        : videoId == null && hit.spotifyTrackId != null
        ? SongRequestSource.spotify
        : SongRequestSource.youtube;
    return SongRequest(
      title: source == SongRequestSource.youtube
          ? requestTitleOfVideo(hit.title)
          : hit.title,
      artist: artist,
      source: source,
      album: hit.album,
      year: hit.year,
      youtubeVideoId: file != null ? null : videoId,
      spotifyTrackId: hit.spotifyTrackId,
      duration: hit.duration,
    );
  }

  /// The artist a row shows when nothing names one ([SearchHit.youTubeOnly], `phoneOnly`).
  static const unknownArtist = 'Nieznany wykonawca';

  final String title;

  /// `null`: the phone knows no artist.
  final String? artist;
  final SongRequestSource source;
  final String? album;
  final int? year;
  final String? youtubeVideoId;
  final String? spotifyTrackId;

  /// The video's length, when the phone knows it (`duration_s`).
  final Duration? duration;

  /// Same song: same artist and title, as search compares them.
  String get key => songRequestKey(artist, title);
}

String songRequestKey(String? artist, String title) =>
    '${normalizeForSearch(artist)}|${normalizeForSearch(title)}';

enum SongRequestSource {
  youtube('youtube'),
  spotify('spotify'),
  phoneFile('phone_file');

  const SongRequestSource(this.code);

  /// As written to the request.
  final String code;
}

/// music.db's `rejected_song_requests`: songs MusicDatabase's owner doesn't want added. A
/// request matches a row by artist and title, or by its YouTube video or Spotify track.
class RejectedSongRequests {
  const RejectedSongRequests({
    this.keys = const {},
    this.videos = const {},
    this.spotifyTracks = const {},
  });

  static const none = RejectedSongRequests();

  final Set<String> keys;
  final Set<String> videos;
  final Set<String> spotifyTracks;

  bool get isEmpty => keys.isEmpty && videos.isEmpty && spotifyTracks.isEmpty;

  bool rejects(SongRequest request) =>
      keys.contains(request.key) ||
      (request.youtubeVideoId != null &&
          videos.contains(request.youtubeVideoId)) ||
      (request.spotifyTrackId != null &&
          spotifyTracks.contains(request.spotifyTrackId));

  /// None in a music.db from before MusicDatabase's migration 0015.
  static RejectedSongRequests read(Database db) {
    final hasTable = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'rejected_song_requests'",
    );
    if (hasTable.isEmpty) return none;
    final keys = <String>{};
    final videos = <String>{};
    final tracks = <String>{};
    for (final row in db.select(
      'SELECT artist, title, youtube_video_id, spotify_track_id '
      'FROM rejected_song_requests',
    )) {
      keys.add(
        songRequestKey(row['artist'] as String?, row['title']! as String),
      );
      if (row['youtube_video_id'] case final String v) videos.add(v);
      if (row['spotify_track_id'] case final String t) tracks.add(t);
    }
    return RejectedSongRequests(
      keys: keys,
      videos: videos,
      spotifyTracks: tracks,
    );
  }
}

/// music.db's `settled_song_requests` (MusicDatabase's migration 0024, hand-off
/// `settled-song-requests-for-musicdatabaseapp.md`): songs asked for that MusicDatabase found it
/// had or added, with the `songs.id` each became. A track is that song by the request's artist
/// and title ([songRequestKey]), its YouTube video or its Spotify track — even when nothing
/// else connects them (a phone file with no video, names the catalog's matcher can't reconcile).
class SettledSongRequests {
  const SettledSongRequests({
    this.keys = const {},
    this.videos = const {},
    this.spotifyTracks = const {},
  });

  static const none = SettledSongRequests();

  /// Each a `songs.id`, kept current by MusicDatabase (merges, deletions).
  final Map<String, int> keys;
  final Map<String, int> videos;
  final Map<String, int> spotifyTracks;

  /// None in a music.db from before MusicDatabase's migration 0024.
  static SettledSongRequests read(Database db) {
    final hasTable = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'settled_song_requests'",
    );
    if (hasTable.isEmpty) return none;
    final keys = <String, int>{};
    final videos = <String, int>{};
    final tracks = <String, int>{};
    for (final row in db.select(
      'SELECT artist, title, youtube_video_id, spotify_track_id, song_id '
      'FROM settled_song_requests ORDER BY id',
    )) {
      final song = row['song_id']! as int;
      keys[songRequestKey(row['artist'] as String?, row['title']! as String)] =
          song;
      if (row['youtube_video_id'] case final String v) videos[v] = song;
      if (row['spotify_track_id'] case final String t) tracks[t] = song;
    }
    return SettledSongRequests(
      keys: keys,
      videos: videos,
      spotifyTracks: tracks,
    );
  }
}
