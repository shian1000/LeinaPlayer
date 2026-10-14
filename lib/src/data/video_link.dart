import 'package:flutter/foundation.dart';

import 'combined_search.dart';
import 'incoming_links.dart';
import 'local_library.dart';
import 'playlist_library.dart';
import 'song_catalog.dart';
import 'source_settings.dart';
import 'spotify_playlist.dart';
import 'youtube_library.dart';
import 'youtube_playlist.dart';
import 'youtube_search.dart';

/// The song a YouTube video link is, the way a playlist import recognises a video
/// (`PlaylistLibrary.matchSong`): music.db's link, then a video the phone matched earlier, then
/// artist and title read from the video's title. A song found by its title gets the video
/// remembered on the phone (ADR 0003), like a match found by searching. Not recognised: the
/// video itself.
Future<SearchHit> hitForVideoLink(
  YouTubeVideoLink link, {
  required SongCatalog catalog,
  required LocalLibrary library,
  required YouTubeLibrary youTube,
  required YouTubeSearch search,
  required SourceSettings settings,
}) async {
  final videoId = link.videoId;
  // Opened inside a playlist: "Otwórz w YouTube" goes back to that place in it.
  final playlistVideoId = link.listId == null ? null : videoId;
  SearchHit hitOf(CatalogSong song) => SearchHit.main(
    song,
    library.filesOf(song.id),
    phoneMatch: song.youtubeVideoId == null ? videoId : null,
    playlistVideoId: playlistVideoId,
  );

  await catalog.ensureLoaded();
  final phoneMatched = youTube.songForVideo(videoId);
  final known =
      catalog.findByYouTubeId(videoId) ??
      (phoneMatched == null ? null : catalog.byId(phoneMatched));
  if (known != null) return hitOf(known);

  final YouTubeVideo video;
  try {
    video = await search.video(videoId, settings);
  } on YouTubeSearchException catch (e) {
    debugPrint('Reading video $videoId failed: $e');
    return SearchHit.youTubeOnly(
      title: 'Film z YouTube',
      artistLabel: 'YouTube',
      videoId: videoId,
      playlistVideoId: playlistVideoId,
    );
  }
  final parsed = parseYouTubeTrack(video.title, video.channel);
  final song = catalog.findExact(title: parsed.title, artist: parsed.artist);
  if (song != null) {
    // Not over MusicDatabase's own answer, including "not on YouTube" (N/A).
    if (song.youTube == YouTubeLink.unknown &&
        !youTube.isWrongFor(song.id, video.id)) {
      await youTube.saveMatch(song.id, video);
    }
    return hitOf(song);
  }
  return SearchHit.youTubeOnly(
    title: parsed.title,
    artistLabel: parsed.artist,
    videoId: videoId,
    playlistVideoId: playlistVideoId,
  );
}

/// The song a Spotify track link is, the way a Spotify playlist's track is recognised
/// ([PlaylistLibrary.matchSpotifyTrack]: exact title and artist). Not recognised: the track by
/// its title and artist, found on YouTube when played (and remembered like a playlist's).
Future<SearchHit> hitForSpotifyTrack(
  SpotifyTrack track, {
  required SongCatalog catalog,
  required PlaylistLibrary playlists,
  required LocalLibrary library,
  required YouTubeLibrary youTube,
}) async {
  await catalog.ensureLoaded();
  final song = playlists.matchSpotifyTrack(track);
  return withPhoneYouTube(
    song != null
        ? SearchHit.main(
            song,
            library.filesOf(song.id),
            spotifyTrackId: track.id,
          )
        : SearchHit.youTubeOnly(
            title: cleanSpotifyTitle(track.title),
            artistLabel: track.artists.isEmpty
                ? 'Nieznany wykonawca'
                : track.artists.join(', '),
            videoId: null,
            spotifyTrackId: track.id,
          ),
    youTube,
  );
}
