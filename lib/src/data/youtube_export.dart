import 'package:flutter/foundation.dart';

import 'combined_search.dart';
import 'playlist_library.dart';
import 'song_catalog.dart';
import 'youtube_api.dart';
import 'youtube_search.dart';

/// How making a YouTube playlist went. [stopped] says why it stopped before the end (daily
/// limit, no connection, cancelled — `null` when it finished); [skipped] are the songs with no
/// video to add, in this run.
typedef YouTubeExportResult = ({
  String playlistId,
  int added,
  List<PlaylistTrack> skipped,
  YouTubeApiException? stopped,
});

/// Makes an unlisted YouTube playlist from Biblioteka playlist [playlist] ("Utwórz playlistę
/// na YouTube" in its share sheet), or finishes the one started before
/// ([PlaylistSummary.youTubeCopyUnfinished]). Each track goes as the video playing it would use
/// ([hitOf], then [findVideo] — the phone's own search, which remembers what it finds); songs
/// with none are skipped. Progress is saved after every song, so a run stopped by YouTube's
/// daily limit (about 200 songs) or by [cancelled] carries on from there next time.
///
/// The lite counterpart of MusicDatabase's `create_yt_playlist()` (ADR 0003), without its
/// YouTube API search: that would use the daily limit up 2× faster.
Future<YouTubeExportResult> exportToYouTube({
  required PlaylistSummary playlist,
  required List<PlaylistTrack> tracks,
  required PlaylistLibrary library,
  required SearchHit Function(PlaylistTrack track) hitOf,
  required Future<String?> Function(SearchHit hit) findVideo,
  required Future<String> Function() token,
  required Future<void> Function(String token) tokenRejected,
  required YouTubeApi api,
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  var accessToken = await token();

  Future<T> call<T>(Future<T> Function(String token) request) async {
    try {
      return await request(accessToken);
    } on YouTubeApiException catch (e) {
      if (!e.unauthorized) rethrow;
      await tokenRejected(accessToken);
      accessToken = await token();
      return request(accessToken);
    }
  }

  Future<String> create() async {
    final id = await call(
      (t) => api.createPlaylist(
        t,
        title: playlist.name,
        description: 'Z aplikacji Leina Radio',
      ),
    );
    await library.setYouTubeCopy(playlist.id, id, done: 0, reload: false);
    return id;
  }

  var start = playlist.youTubeCopyUnfinished ? playlist.youTubeCopyDone! : 0;
  var playlistId = playlist.youTubeCopyUnfinished
      ? playlist.youTubeCopyId!
      : await create();
  var added = 0;
  final skipped = <PlaylistTrack>[];
  YouTubeApiException? stopped;
  var done = start;
  onProgress?.call(done, tracks.length);
  try {
    while (done < tracks.length) {
      if (cancelled?.call() ?? false) {
        stopped = const YouTubeApiException('Przerwano');
        break;
      }
      final track = tracks[done];
      final videoId = await _videoFor(hitOf(track), findVideo);
      var inserted = false;
      if (videoId != null) {
        try {
          inserted = await call((t) => api.addVideo(t, playlistId, videoId));
        } on YouTubeApiException catch (e) {
          // Deleted on YouTube since the run that stopped: a new one from the start.
          if (!e.playlistGone || start == 0 || added > 0) rethrow;
          playlistId = await create();
          start = done = 0;
          skipped.clear();
          onProgress?.call(done, tracks.length);
          continue;
        }
      }
      if (inserted) {
        added++;
      } else {
        skipped.add(track);
      }
      done++;
      await library.setYouTubeCopy(
        playlist.id,
        playlistId,
        done: done,
        reload: false,
      );
      onProgress?.call(done, tracks.length);
    }
  } on YouTubeApiException catch (e) {
    stopped = e;
  }
  await library.setYouTubeCopy(
    playlist.id,
    playlistId,
    done: stopped == null ? null : done,
  );
  return (
    playlistId: playlistId,
    added: added,
    skipped: skipped,
    stopped: stopped,
  );
}

/// The video [hit] plays from, else one found now — not for songs marked as not on YouTube,
/// nor ones searched for lately without a find.
Future<String?> _videoFor(
  SearchHit hit,
  Future<String?> Function(SearchHit hit) findVideo,
) async {
  final known = hit.youtubeVideoId;
  if (known != null) return known;
  if (hit.youTube != YouTubeLink.unknown) return null;
  try {
    return await findVideo(hit);
  } on YouTubeSearchException catch (e) {
    debugPrint('Searching "${hit.title}" for the YouTube playlist failed: $e');
    return null;
  }
}
