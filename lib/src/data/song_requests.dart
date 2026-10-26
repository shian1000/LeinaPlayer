import 'package:sqflite/sqflite.dart';

import 'combined_search.dart';
import 'text_normalizer.dart';

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
  });

  /// What [hit] would be asked as; `null` for a song music.db has, or one with no title.
  /// [artistNamed] (`SongCatalog.artistNamed`) gives music.db's name of an artist known by
  /// another name: a video's channel or a file's tag may be one of its `artists.synonyms`
  /// ("familyboombox" is "Бумбокс"), and the request then asks for the artist music.db has.
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
    return SongRequest(
      title: hit.title,
      artist: artist,
      source: file != null
          ? SongRequestSource.phoneFile
          : videoId == null && hit.spotifyTrackId != null
          ? SongRequestSource.spotify
          : SongRequestSource.youtube,
      album: hit.album,
      year: hit.year,
      youtubeVideoId: file != null ? null : videoId,
      spotifyTrackId: hit.spotifyTrackId,
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
  static Future<RejectedSongRequests> read(Database db) async {
    final hasTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'rejected_song_requests'",
    );
    if (hasTable.isEmpty) return none;
    final keys = <String>{};
    final videos = <String>{};
    final tracks = <String>{};
    for (final row in await db.rawQuery(
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
