import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../data/server_downloads.dart';
import '../data/song_catalog.dart';
import '../data/song_requests.dart';
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

/// What "Pobierz" did with a song.
enum DownloadOutcome {
  downloaded,

  /// A file on the phone: nothing to download.
  onPhone,
  failed,
}

/// Where MusicDatabase's server at [base] serves [file]'s audio.
Uri serverFileUri(Uri base, ServerFile file) =>
    base.resolve('library/${file.id}');

/// The status MusicDatabase's server answers a `HEAD` of [uri] with, `null` when it can't be
/// reached within a few seconds.
Future<int?> _probeServer(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client
        .headUrl(uri)
        .timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    return response.statusCode;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Plays one song from the first source in the user's order that has it
/// ([SourceSettings.activePlaybackOrder] — switched-off sources are never used): a phone file, a file on MusicDatabase's server (when the
/// server can't play it, the next source does), or YouTube ([YouTubePlayback]). When no source
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
    this.catalog,
    this.serverDownloads,
    Future<List<Uri>> Function()? serverAddresses,
    Future<bool> Function()? onWifi,
  }) : _serverAddresses = serverAddresses ?? _noServer,
       _onWifi = onWifi ?? _wifiConnected;

  final PlayerController player;
  final SourceSettings settings;
  final YouTubeLibrary youTubeLibrary;
  final YouTubeAudio youTubeAudio;
  final YouTubeSearch youTubeSearch;

  /// Replaced in tests; `null` opens the YouTube app for real.
  final OpenExternalFn? openExternal;

  /// Where dead music.db links (and the videos found instead), and videos found for songs
  /// music.db has no link for, are reported for MusicDatabase; `null` reports nothing.
  final Outbox? outbox;

  /// music.db as loaded: a song played that it doesn't have is asked for in [outbox], unless
  /// its owner rejected it; `null` asks for nothing.
  final SongCatalog? catalog;

  /// Server files kept on the phone with "Pobierz", played instead of streaming them; `null`:
  /// none (tests).
  final ServerDownloads? serverDownloads;

  /// MusicDatabase's server as the phone reaches it now, best address first
  /// ([DatabaseSync.serverAddresses]), for [PlaybackSource.server].
  final Future<List<Uri>> Function() _serverAddresses;

  static Future<List<Uri>> _noServer() async => const [];

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

  /// [hit]'s music video, with the links the user set; `null` when it has none.
  Uri? musicVideoUri(SearchHit hit) {
    final videoId = _withRememberedVideo(hit).musicVideoId;
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
    unawaited(_requestIfMissing(hit));
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
      hit.mainSong?.fromMusicDb.youtubeVideoId == gone
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
    bool skipServer = false,
  }) async {
    final source = settings.activePlaybackOrder
        .where((s) => !(skipServer && s == PlaybackSource.server))
        .where(hit.playableFrom)
        .firstOrNull;
    switch (source) {
      case PlaybackSource.server:
        final outcome = await _playFromServer(
          hit,
          hit.serverFile!,
          searchQuery: searchQuery,
          playlistName: playlistName,
          onStatus: onStatus,
        );
        if (outcome.played) return outcome;
        // Away from home without the tailnet, or the drive unplugged: the next source plays it.
        final fallback = await _playOnce(
          hit,
          searchQuery: searchQuery,
          playlistName: playlistName,
          youTubeListId: youTubeListId,
          allowExternal: allowExternal,
          onStatus: onStatus,
          skipServer: true,
        );
        return fallback.played || fallback.goneVideo != null
            ? fallback
            : outcome;
      case PlaybackSource.phone:
        final ok = await player.play(
          NowPlaying(
            title: hit.title,
            artist: hit.artistLabel,
            titleLatin: hit.titleLatin,
            artistLatin: hit.artistLatin,
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
          titleLatin: hit.titleLatin,
          artistLatin: hit.artistLatin,
          coverSeed: hit.coverSeed,
          cover: CoverRequest.of(hit),
          searchQuery: searchQuery,
          playlistName: playlistName,
          allowExternal: allowExternal,
          onStatus: onStatus,
          externalUri: youTubeUri(hit, listId: youTubeListId),
        );
      case null:
        if (!settings.enabledSources.contains(PlaybackSource.youtube)) {
          return const PlayOutcome.failed(
            'Tego utworu nie ma w żadnym włączonym źródle '
            '(Ustawienia › Odtwarzanie › Kolejność odtwarzania).',
          );
        }
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

  /// [file] streamed from the first of MusicDatabase's addresses that answers for it
  /// (`GET /library/<files.id>`, hand-off `musicdatabase-server-files.md`). Each address is
  /// asked first ([_probeServer]), so an unreachable one is passed over in seconds and "no
  /// connection" (the queue waits and tries again) is told from "the server hasn't got it" (the
  /// queue moves on).
  Future<PlayOutcome> _playFromServer(
    SearchHit hit,
    ServerFile file, {
    String? searchQuery,
    String? playlistName,
    void Function(String status)? onStatus,
  }) async {
    NowPlaying track(String source) => NowPlaying(
      title: hit.title,
      artist: hit.artistLabel,
      titleLatin: hit.titleLatin,
      artistLatin: hit.artistLatin,
      source: source,
      serverFileId: file.id,
      coverSeed: hit.coverSeed,
      cover: CoverRequest.of(hit),
      searchQuery: searchQuery,
      playlistName: playlistName,
    );
    // Downloaded with "Pobierz": no server needed.
    if (await serverDownloads?.fileFor(file.id) case final copy?) {
      if (await player.play(track(copy.path))) {
        return const PlayOutcome.played();
      }
    }
    final addresses = await _serverAddresses();
    if (addresses.isEmpty) {
      return const PlayOutcome.failed(
        'Utwór jest na serwerze, ale telefon nie jest w sieci domowej, a adres zdalny serwera '
        'nie jest ustawiony.',
      );
    }
    onStatus?.call('Łączę z serwerem…');
    int? refused;
    for (final base in addresses) {
      final uri = serverFileUri(base, file);
      final status = await _probeServer(uri);
      if (status == null) continue;
      if (status != HttpStatus.ok) {
        refused ??= status;
        continue;
      }
      final ok = await player.play(track(uri.toString()));
      return ok
          ? const PlayOutcome.played()
          : PlayOutcome.failed(player.lastError);
    }
    return switch (refused) {
      null => const PlayOutcome.failed(
        'Nie można połączyć się z serwerem MusicDatabase.',
        offline: true,
      ),
      HttpStatus.serviceUnavailable => const PlayOutcome.failed(
        'Biblioteka muzyki na serwerze jest niedostępna (dysk nie jest podłączony?).',
      ),
      HttpStatus.notFound => PlayOutcome.failed(
        'Pliku „${file.fileName}” nie ma już na serwerze.',
      ),
      _ => PlayOutcome.failed('Serwer zwrócił błąd $refused dla utworu.'),
    };
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
        '(Ustawienia › YouTube).',
      );
    }
    onStatus?.call('Szukam na YouTube…');
    final YouTubeVideo? video;
    try {
      video = await findVideo(hit);
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
      titleLatin: hit.titleLatin,
      artistLatin: hit.artistLatin,
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
  /// searching again, and the icon turns full; a MusicDatabase song's video also goes to the
  /// outbox as a suggestion. Finding none is remembered too ([YouTubeLibrary.saveNotFound]).
  Future<YouTubeVideo?> findVideo(SearchHit hit) async {
    final target = hit.youTubeTarget;
    final mainSong = hit.mainSong;
    final video = pickYouTubeVideo(target, [
      for (final v in await youTubeSearch.search(target.query, settings))
        if (!youTubeLibrary.isVideoRemoved(v.id) &&
            !(mainSong != null && youTubeLibrary.isWrongFor(mainSong.id, v.id)))
          v,
    ]);
    if (video != null) {
      await (mainSong != null
          ? youTubeLibrary.saveMatch(mainSong.id, video)
          : youTubeLibrary.saveTrackMatch(hit.artistLabel, hit.title, video));
      final dead = mainSong?.youtubeVideoId;
      if (mainSong != null && dead != null && hit.mainVideoRemoved) {
        await _report(() => outbox?.reportReplacement(mainSong, dead, video));
      } else if (mainSong?.youTube == YouTubeLink.unknown) {
        await _report(() => outbox?.reportFoundYouTubeLink(mainSong!, video));
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

  /// MusicDatabase's own link of [hit] is [gone]: worth telling MusicDatabase. Not one the
  /// user set in its place ([CatalogSong.userLinks]).
  Future<void> _reportIfMainLink(SearchHit hit, String gone) async {
    final song = hit.mainSong?.fromMusicDb;
    if (song == null || song.youtubeVideoId != gone) return;
    await _report(() => outbox?.reportDeadYouTubeLink(song, gone));
  }

  /// Only against a loaded music.db: it says what MusicDatabase has and what its owner rejected.
  Future<void> _requestIfMissing(SearchHit hit) async {
    final catalog = this.catalog;
    if (outbox == null ||
        catalog == null ||
        catalog.status != CatalogStatus.ready) {
      return;
    }
    final request = SongRequest.of(hit, artistNamed: catalog.artistNamed);
    if (request == null || catalog.rejectedSongRequests.rejects(request)) {
      return;
    }
    await _report(() => outbox?.requestSong(request));
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
    final source = settings.activePlaybackOrder
        .where(hit.playableFrom)
        .firstOrNull;
    // A server file streams like a phone file plays: nothing to cache.
    if (source == PlaybackSource.phone || source == PlaybackSource.server) {
      return false;
    }
    if (settings.queuePrefetchWifiOnly && !await _onWifi()) return false;
    return _cacheYouTube(hit, pin: false);
  }

  /// "Pobierz": keeps [hit] on the phone for good, from the first source in the play order that
  /// has it — a file of MusicDatabase's library copied to the phone ([ServerDownloads]), or the
  /// YouTube audio kept in the cache outside its limit ([YouTubeLibrary.setPinned]). When the
  /// server can't be reached, YouTube is tried. A file on the phone needs nothing.
  Future<DownloadOutcome> download(SearchHit hit) async {
    if (hit.onPhone) return DownloadOutcome.onPhone;
    hit = _withRememberedVideo(hit);
    final server = hit.serverFile;
    final downloads = serverDownloads;
    final order = settings.activePlaybackOrder.where(hit.playableFrom);
    if (order.firstOrNull == PlaybackSource.server &&
        server != null &&
        downloads != null) {
      final addresses = await _serverAddresses();
      if (await downloads.download(server, [
        for (final base in addresses) serverFileUri(base, server),
      ])) {
        return DownloadOutcome.downloaded;
      }
    }
    if (!settings.enabledSources.contains(PlaybackSource.youtube)) {
      return DownloadOutcome.failed;
    }
    return await _cacheYouTube(hit, pin: true)
        ? DownloadOutcome.downloaded
        : DownloadOutcome.failed;
  }

  /// [hit] kept with "Pobierz": a downloaded server file or pinned YouTube audio.
  bool isDownloaded(SearchHit hit) {
    hit = _withRememberedVideo(hit);
    final server = hit.serverFile;
    if (server != null && (serverDownloads?.isDownloaded(server.id) ?? false)) {
      return true;
    }
    final videoId = hit.youtubeVideoId;
    return videoId != null && youTubeLibrary.isPinned(videoId);
  }

  /// "Usuń z pobranych": a server file's copy is deleted, YouTube audio goes back to the cache.
  Future<void> removeDownload(SearchHit hit) async {
    hit = _withRememberedVideo(hit);
    if (hit.serverFile case final server?) {
      await serverDownloads?.remove(server.id);
    }
    if (hit.youtubeVideoId case final videoId?) {
      await youTubeLibrary.setPinned(videoId, false, limit: settings.cacheKeep);
    }
  }

  /// [hit]'s YouTube audio into the cache — found on YouTube first when the phone doesn't know
  /// the video yet; with [pin], kept there for good.
  Future<bool> _cacheYouTube(SearchHit hit, {required bool pin}) async {
    if (!settings.enabledSources.contains(PlaybackSource.youtube)) return false;
    var videoId = hit.youtubeVideoId;
    if (hit.youTube != YouTubeLink.linked || videoId == null) {
      if (hit.youTube != YouTubeLink.unknown ||
          !settings.youTubeSearchEnabled ||
          !settings.enabledSources.contains(PlaybackSource.youtube)) {
        return false;
      }
      try {
        videoId = (await findVideo(hit))?.id;
      } on YouTubeSearchException catch (e) {
        debugPrint('Caching ahead: searching "${hit.title}" failed: $e');
      }
    }
    if (videoId == null) return false;
    if (youTubeLibrary.isCached(videoId)) {
      if (pin) await youTubeLibrary.setPinned(videoId, true);
      return true;
    }
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
          pin: pin,
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
          return _cacheYouTube(_withRememberedVideo(hit), pin: pin);
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
    String? titleLatin,
    String? artistLatin,
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
          titleLatin: titleLatin,
          artistLatin: artistLatin,
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
