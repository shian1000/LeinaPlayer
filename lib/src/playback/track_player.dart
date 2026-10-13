import 'package:flutter/foundation.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/youtube_audio.dart';
import '../data/youtube_library.dart';
import '../data/youtube_matcher.dart';
import '../data/youtube_search.dart';
import 'player_controller.dart';
import 'youtube_playback.dart';
import '../data/album_covers.dart';

/// How playing one song went; [message] is for the user (what was found, or why it failed),
/// `null` when there's nothing to say.
class PlayOutcome {
  const PlayOutcome.played([this.message])
    : played = true,
      external = false,
      offline = false,
      goneVideo = null;
  const PlayOutcome.failed(this.message, {this.offline = false, this.goneVideo})
    : played = false,
      external = false;

  /// Handed to the YouTube app: playing, but not in this app's player.
  const PlayOutcome.external(this.message)
    : played = true,
      external = true,
      offline = false,
      goneVideo = null;

  final bool played;
  final bool external;

  /// Failed for want of a network connection (the song itself may be fine).
  final bool offline;

  /// Failed because YouTube no longer has this video.
  final String? goneVideo;
  final String? message;
}

/// Plays one song from the first source in the user's order that has it
/// ([SourceSettings.playbackOrder]): a phone file, or YouTube ([YouTubePlayback]). When no source
/// has it but YouTube might, YouTube is searched, the best video picked ([pickYouTubeVideo]) and
/// remembered on the phone. No UI here, so the queue can use it with the screen off.
class TrackPlayer {
  TrackPlayer({
    required this.player,
    required this.settings,
    required this.youTubeLibrary,
    required this.youTubeAudio,
    required this.youTubeSearch,
    this.openExternal,
    this.outbox,
    Future<bool> Function()? onWifi,
  }) : _onWifi = onWifi ?? _wifiConnected;

  final PlayerController player;
  final SourceSettings settings;
  final YouTubeLibrary youTubeLibrary;
  final YouTubeAudio youTubeAudio;
  final YouTubeSearch youTubeSearch;

  /// Replaced in tests; `null` opens the YouTube app for real.
  final OpenExternalFn? openExternal;

  /// Where dead music.db links (and the videos found instead) are reported for MusicDatabase;
  /// `null` reports nothing.
  final Outbox? outbox;

  /// Whether the phone is on Wi-Fi now; replaced in tests.
  final Future<bool> Function() _onWifi;

  static Future<bool> _wifiConnected() async =>
      await readCurrentWifiIp() != null;

  /// Where the YouTube app should open [hit]: inside its YouTube playlist [listId] when it's
  /// played from one (the playlist's own video), else the video's page; `null` when no video
  /// is known. A video YouTube removed — music.db's or the playlist's — gives way to the one the
  /// phone found instead.
  Uri? youTubeUri(SearchHit hit, {String? listId}) {
    final inPlaylist = listId != null ? hit.playlistVideoId : null;
    if (inPlaylist != null && !youTubeLibrary.isVideoRemoved(inPlaylist)) {
      return youTubeWatchUri(inPlaylist, listId: listId);
    }
    final videoId = _withRememberedVideo(hit).youtubeVideoId;
    return videoId == null ? null : youTubeWatchUri(videoId);
  }

  /// [onStatus] gets short progress messages ("Łączę z YouTube…"); [allowExternal] lets the
  /// YouTube app be the last resort (only when the user tapped something). [youTubeListId]: the
  /// YouTube playlist the song is played from, for the YouTube app ([youTubeUri]).
  Future<PlayOutcome> play(
    SearchHit hit, {
    String? searchQuery,
    String? playlistName,
    String? youTubeListId,
    bool allowExternal = true,
    void Function(String status)? onStatus,
  }) async {
    hit = _withRememberedVideo(hit);
    final outcome = await _playOnce(
      hit,
      searchQuery: searchQuery,
      playlistName: playlistName,
      youTubeListId: youTubeListId,
      allowExternal: allowExternal,
      onStatus: onStatus,
    );
    final gone = outcome.goneVideo;
    if (gone == null) return outcome;
    // Forget it and look for another one — music.db's own link too: the phone's video fills in
    // only until MusicDatabase changes the link (withPhoneYouTube). Each round marks one more
    // video, so this ends.
    await youTubeLibrary.markVideoRemoved(gone);
    await _reportIfMainLink(hit, gone);
    onStatus?.call(
      hit.mainSong?.youtubeVideoId == gone
          ? 'Link z MusicDatabase wygasł — szukam innego filmu…'
          : 'Tego filmu nie ma już na YouTube — szukam innego…',
    );
    return play(
      hit,
      searchQuery: searchQuery,
      playlistName: playlistName,
      youTubeListId: youTubeListId,
      allowExternal: allowExternal,
      onStatus: onStatus,
    );
  }

  Future<PlayOutcome> _playOnce(
    SearchHit hit, {
    String? searchQuery,
    String? playlistName,
    String? youTubeListId,
    required bool allowExternal,
    void Function(String status)? onStatus,
  }) async {
    final source = settings.playbackOrder.where(hit.playableFrom).firstOrNull;
    switch (source) {
      case PlaybackSource.phone:
        final ok = await player.play(
          NowPlaying(
            title: hit.title,
            artist: hit.artistLabel,
            source: hit.phoneFiles.first.filePath,
            coverSeed: hit.coverSeed,
            cover: CoverRequest.of(hit),
            searchQuery: searchQuery,
            playlistName: playlistName,
          ),
        );
        return ok
            ? const PlayOutcome.played()
            : PlayOutcome.failed(player.lastError);
      case PlaybackSource.youtube:
        return playVideo(
          videoId: hit.youtubeVideoId!,
          title: hit.title,
          artist: hit.artistLabel,
          coverSeed: hit.coverSeed,
          cover: CoverRequest.of(hit),
          searchQuery: searchQuery,
          playlistName: playlistName,
          allowExternal: allowExternal,
          onStatus: onStatus,
          externalUri: youTubeUri(hit, listId: youTubeListId),
        );
      case null:
        // Not found lately: the queue moves on, but a tap (allowExternal) searches again.
        if (hit.youTube == YouTubeLink.notFound && !allowExternal) {
          return const PlayOutcome.failed(
            'Tego utworu nie znaleziono na YouTube — dotknij go, żeby poszukać jeszcze raz.',
          );
        }
        if (hit.youTube != YouTubeLink.unknown &&
            hit.youTube != YouTubeLink.notFound) {
          return const PlayOutcome.failed(
            'Ten utwór jest niedostępny — nie ma go na telefonie ani na YouTube.',
          );
        }
        return _findOnYouTube(
          hit,
          searchQuery: searchQuery,
          playlistName: playlistName,
          allowExternal: allowExternal,
          onStatus: onStatus,
        );
    }
  }

  Future<PlayOutcome> _findOnYouTube(
    SearchHit hit, {
    String? searchQuery,
    String? playlistName,
    required bool allowExternal,
    void Function(String status)? onStatus,
  }) async {
    if (!settings.youTubeSearchEnabled) {
      return const PlayOutcome.failed(
        'Utworu nie ma na telefonie, a szukanie w serwisie YouTube jest wyłączone '
        '(Ustawienia › Źródła muzyki › YouTube).',
      );
    }
    onStatus?.call('Szukam na YouTube…');
    final YouTubeVideo? video;
    try {
      video = await _findVideo(hit);
    } on YouTubeSearchException catch (e) {
      return PlayOutcome.failed(e.message, offline: e.offline);
    }
    if (video == null) {
      return const PlayOutcome.failed(
        'Nie znaleziono na YouTube pewnego dopasowania tego utworu.',
      );
    }
    return playVideo(
      videoId: video.id,
      title: hit.title,
      artist: hit.artistLabel,
      coverSeed: hit.coverSeed,
      cover: CoverRequest.of(hit),
      searchQuery: searchQuery,
      playlistName: playlistName,
      allowExternal: allowExternal,
      onStatus: onStatus,
      foundVideo: video,
    );
  }

  /// The best video for [hit], remembered so the next play uses it (or its cached audio) without
  /// searching again, and the icon turns full (ADR 0003: kept on the phone only). Finding none is
  /// remembered too ([YouTubeLibrary.saveNotFound]).
  Future<YouTubeVideo?> _findVideo(SearchHit hit) async {
    final target = hit.youTubeTarget;
    final video = pickYouTubeVideo(target, [
      for (final v in await youTubeSearch.search(target.query, settings))
        if (!youTubeLibrary.isVideoRemoved(v.id)) v,
    ]);
    final mainSong = hit.mainSong;
    if (video != null) {
      await (mainSong != null
          ? youTubeLibrary.saveMatch(mainSong.id, video)
          : youTubeLibrary.saveTrackMatch(hit.artistLabel, hit.title, video));
      final dead = mainSong?.youtubeVideoId;
      if (mainSong != null && dead != null && hit.mainVideoRemoved) {
        await _report(() => outbox?.reportReplacement(mainSong, dead, video));
      }
    } else {
      await youTubeLibrary.saveNotFound(
        mainDbId: mainSong?.id,
        artist: hit.artistLabel,
        title: hit.title,
      );
    }
    return video;
  }

  /// MusicDatabase's own link of [hit] is [gone]: worth telling MusicDatabase.
  Future<void> _reportIfMainLink(SearchHit hit, String gone) async {
    final song = hit.mainSong;
    if (song == null || song.youtubeVideoId != gone) return;
    await _report(() => outbox?.reportDeadYouTubeLink(song, gone));
  }

  /// A report that fails (storage) mustn't stop playback.
  Future<void> _report(Future<void>? Function() write) async {
    try {
      await write();
    } catch (e) {
      debugPrint('Writing to the outbox failed: $e');
    }
  }

  /// A queue holds its songs as they were when it was filled; what was learned on YouTube since
  /// (e.g. while caching ahead) is used instead of searching again.
  SearchHit _withRememberedVideo(SearchHit hit) =>
      withPhoneYouTube(hit, youTubeLibrary);

  /// Downloads [hit]'s YouTube audio to the cache ahead of time (Pamięć podręczna › Kolejka), finding
  /// the video first when the phone doesn't know it yet. Does nothing for songs another source
  /// plays first, while the cache is off, or off Wi-Fi when the user saves mobile data. Returns
  /// whether the song is ready in the cache.
  Future<bool> prefetch(SearchHit hit) async {
    if (!settings.playbackMethods.contains(YouTubePlaybackMethod.cache)) {
      return false;
    }
    hit = _withRememberedVideo(hit);
    final source = settings.playbackOrder.where(hit.playableFrom).firstOrNull;
    if (source == PlaybackSource.phone) return false;
    if (settings.queuePrefetchWifiOnly && !await _onWifi()) return false;
    var videoId = hit.youtubeVideoId;
    if (source == null) {
      if (hit.youTube != YouTubeLink.unknown ||
          !settings.youTubeSearchEnabled) {
        return false;
      }
      try {
        videoId = (await _findVideo(hit))?.id;
      } on YouTubeSearchException catch (e) {
        debugPrint('Caching ahead: searching "${hit.title}" failed: $e');
      }
    }
    if (videoId == null) return false;
    if (youTubeLibrary.isCached(videoId)) return true;
    for (final method in settings.activePlaybackMethods.where(
      (m) => m.streams,
    )) {
      try {
        final stream = await youTubeAudio.streamFrom(method, videoId);
        if (await youTubeLibrary.download(
          videoId,
          stream.url,
          stream.extension,
          settings.cacheKeep,
        )) {
          return true;
        }
      } on YouTubeAudioException catch (e) {
        debugPrint('Caching ahead: ${method.name} for $videoId failed: $e');
        if (e.gone) {
          // Found out before it plays: another video is looked for (and cached) now, so the
          // queue doesn't stall on it. Each round marks one more video, so this ends.
          await youTubeLibrary.markVideoRemoved(videoId);
          await _reportIfMainLink(hit, videoId);
          return prefetch(hit);
        }
      }
    }
    return false;
  }

  /// A YouTube video, with the user's playback methods in their order.
  Future<PlayOutcome> playVideo({
    required String videoId,
    required String title,
    required String artist,
    required String coverSeed,
    CoverRequest? cover,
    String? searchQuery,
    String? playlistName,
    bool allowExternal = true,
    void Function(String status)? onStatus,
    YouTubeVideo? foundVideo,
    Uri? externalUri,
  }) async {
    final playback = YouTubePlayback(
      audio: youTubeAudio,
      library: youTubeLibrary,
      settings: settings,
      player: player,
      openExternal: openExternal,
    );
    try {
      final via = await playback.play(
        videoId,
        (source) => NowPlaying(
          title: title,
          artist: artist,
          source: source,
          coverSeed: coverSeed,
          cover: cover?.withVideo(videoId),
          searchQuery: searchQuery,
          playlistName: playlistName,
          youtubeVideoId: videoId,
        ),
        onConnecting: () => onStatus?.call('Łączę z YouTube…'),
        allowExternal: allowExternal,
        externalUri: externalUri,
      );
      if (via == YouTubePlayedVia.youtubeApp) {
        return const PlayOutcome.external('Otwarto w aplikacji YouTube.');
      }
      // The phone picked this video itself, so say which one it is.
      return PlayOutcome.played(
        foundVideo == null
            ? null
            : 'Z YouTube: „${foundVideo.title}” (${foundVideo.channel})',
      );
    } on YouTubePlaybackException catch (e) {
      return PlayOutcome.failed(
        e.message,
        offline: e.offline,
        goneVideo: e.gone ? videoId : null,
      );
    }
  }
}
