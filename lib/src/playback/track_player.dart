import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/combined_search.dart';
import '../data/cover_credit.dart';
import '../data/database_sync.dart';
import '../data/download_files.dart';
import '../data/mp3_conversion.dart';
import '../data/outbox.dart';
import '../data/server_downloads.dart';
import '../data/song_catalog.dart';
import '../data/version_names.dart';
import '../data/song_requests.dart';
import '../data/source_settings.dart';
import '../data/youtube_audio.dart';
import '../data/youtube_library.dart';
import '../data/youtube_matcher.dart';
import '../data/youtube_search.dart';
import '../l10n.dart';
import 'player_controller.dart';
import 'youtube_playback.dart';
import '../data/album_covers.dart';
import '../data/server_trust.dart';

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
  final client = ServerTrust.instance.client()
    ..connectionTimeout = const Duration(seconds: 3);
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

/// Bytes in an MP3's ID3v2 tag, its 10-byte header (and footer) included; `null` when
/// [header] doesn't start one.
int? id3TagLength(List<int> header) {
  if (header.length < 10 ||
      String.fromCharCodes(header.take(3)) != 'ID3' ||
      header.sublist(6, 10).any((b) => b > 0x7f)) {
    return null;
  }
  final size = header.sublist(6, 10).fold(0, (size, b) => (size << 7) | b);
  final footer = header[5] & 0x10 != 0 ? 10 : 0;
  return 10 + size + footer;
}

/// The ID3v2 tag at the start of the server file at [uri] — where an MP3 keeps its cover — got
/// with byte ranges, without the audio; `null` for a 404 or a file without one. Throws when
/// the server can't be reached or can't read the file now.
Future<Uint8List?> fetchServerFileHead(Uri uri) async {
  const maxTagBytes = 16 * 1024 * 1024;
  final client = ServerTrust.instance.client()
    ..connectionTimeout = const Duration(seconds: 3);
  Future<Uint8List?> firstBytes(int count) async {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${count - 1}');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.partialContent &&
        response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final builder = BytesBuilder(copy: false);
    // A server ignoring the range sends the whole song: stop once there's enough.
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      builder.add(chunk);
      if (builder.length >= count) break;
    }
    final bytes = builder.takeBytes();
    return bytes.length > count
        ? Uint8List.sublistView(bytes, 0, count)
        : bytes;
  }

  try {
    final header = await firstBytes(10);
    if (header == null) return null;
    final length = id3TagLength(header);
    if (length == null || length > maxTagBytes) return null;
    return await firstBytes(length);
  } finally {
    client.close(force: true);
  }
}

/// Plays one song from the first source in the user's order that has it
/// ([SourceSettings.activePlaybackOrder] — switched-off sources are never used): a phone file, a file on MusicDatabase's server, or
/// YouTube ([YouTubePlayback]); when the phone file or the server can't play it, the next
/// source does. When no source
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
    this.mp3Converter,
    this.coverBytes,
    this.onPhoneFileGone,
    this.playlistVideosOf,
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

  /// Re-encodes "Pobierz"'s songs as MP3 when [SourceSettings.downloadsAsMp3] says so; `null`
  /// where the phone has no encoder.
  final Mp3Converter? mp3Converter;

  /// [hit]'s album cover for the MP3's tag (`AlbumCovers.coverBytes`); `null` when there's none.
  final Future<Uint8List?> Function(SearchHit hit)? coverBytes;

  /// A phone file about to play is no longer there (moved or deleted since the last scan):
  /// `local.db` forgets it ([LocalLibrary.forgetGone]) and the next source plays the song.
  /// `null`: files aren't checked before playing (tests with made-up paths).
  final Future<void> Function(String path)? onPhoneFileGone;

  /// The videos Biblioteka's playlists have for music.db song id ([PlaylistLibrary.videosOf]),
  /// tried before searching YouTube ([findVideo]); `null`: none (tests).
  final List<YouTubeVideo> Function(int songId)? playlistVideosOf;

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
          ? l10n.trackPlayerLinkExpired
          : l10n.trackPlayerVideoGoneSearching,
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
    Set<PlaybackSource> skip = const {},
  }) async {
    final source = settings.activePlaybackOrder
        .where((s) => !skip.contains(s))
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
          skip: {...skip, PlaybackSource.server},
        );
        return fallback.played || fallback.goneVideo != null
            ? fallback
            : outcome;
      case PlaybackSource.phone:
        final file = hit.phoneFiles.first.filePath;
        final String? failure;
        if (await _phoneFileGone(file)) {
          failure = l10n.trackPlayerPhoneFileGone(file.split('/').last);
        } else if (await player.play(
          NowPlaying(
            title: hit.title,
            artist: hit.artistLabel,
            titleLatin: hit.titleLatin,
            artistLatin: hit.artistLatin,
            language: hit.mainSong?.language,
            coverOf: hit.coverOf,
            version: hit.version,
            source: file,
            coverSeed: hit.coverSeed,
            cover: CoverRequest.of(hit),
            searchQuery: searchQuery,
            playlistName: playlistName,
          ),
        )) {
          return const PlayOutcome.played();
        } else {
          failure = player.lastError;
        }
        // A file gone or broken: the song may still be on the server or on YouTube.
        final fallback = await _playOnce(
          hit,
          searchQuery: searchQuery,
          playlistName: playlistName,
          youTubeListId: youTubeListId,
          allowExternal: allowExternal,
          onStatus: onStatus,
          skip: {...skip, PlaybackSource.phone},
        );
        return fallback.played || fallback.goneVideo != null
            ? fallback
            : PlayOutcome.failed(failure);
      case PlaybackSource.youtube:
        return playVideo(
          videoId: hit.youtubeVideoId!,
          title: hit.title,
          artist: hit.artistLabel,
          titleLatin: hit.titleLatin,
          artistLatin: hit.artistLatin,
          language: hit.mainSong?.language,
          coverOf: hit.coverOf,
          version: hit.version,
          coverSeed: hit.coverSeed,
          cover: CoverRequest.of(hit),
          searchQuery: searchQuery,
          playlistName: playlistName,
          allowExternal: allowExternal,
          onStatus: onStatus,
          externalUri: youTubeUri(hit, listId: youTubeListId),
          hit: hit,
        );
      case null:
        if (!settings.enabledSources.contains(PlaybackSource.youtube)) {
          return PlayOutcome.failed(l10n.trackPlayerNoEnabledSource);
        }
        // Not found lately: the queue moves on, but a tap (allowExternal) searches again.
        if (hit.youTube == YouTubeLink.notFound && !allowExternal) {
          return PlayOutcome.failed(l10n.trackPlayerNotFoundTapToRetry);
        }
        if (hit.youTube != YouTubeLink.unknown &&
            hit.youTube != YouTubeLink.notFound) {
          return PlayOutcome.failed(l10n.trackPlayerUnavailable);
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

  /// Whether the phone file at [path] is gone; a gone one is forgotten ([onPhoneFileGone]).
  Future<bool> _phoneFileGone(String path) async {
    final forget = onPhoneFileGone;
    if (forget == null || await File(path).exists()) return false;
    // By its name only: its folders may name people, and the log goes to someone else.
    debugPrint('Phone file ${path.split('/').last} is gone: forgotten');
    try {
      await forget(path);
    } catch (e) {
      debugPrint('Forgetting a gone phone file failed: $e');
    }
    return true;
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
      language: hit.mainSong?.language,
      coverOf: hit.coverOf,
      version: hit.version,
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
      return PlayOutcome.failed(l10n.trackPlayerServerUnreachableNoRemote);
    }
    onStatus?.call(l10n.trackPlayerConnectingServer);
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
      null => PlayOutcome.failed(
        l10n.trackPlayerServerConnectionFailed,
        offline: true,
      ),
      HttpStatus.serviceUnavailable => PlayOutcome.failed(
        l10n.trackPlayerServerLibraryUnavailable,
      ),
      HttpStatus.notFound => PlayOutcome.failed(
        l10n.trackPlayerServerFileGone(file.fileName),
      ),
      final int status => PlayOutcome.failed(
        l10n.trackPlayerServerError(status),
      ),
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
      return PlayOutcome.failed(l10n.trackPlayerYouTubeSearchOff);
    }
    onStatus?.call(l10n.trackPlayerSearchingYouTube);
    final YouTubeVideo? video;
    try {
      video = await findVideo(hit);
    } on YouTubeSearchException catch (e) {
      return PlayOutcome.failed(e.message, offline: e.offline);
    }
    if (video == null) {
      return PlayOutcome.failed(l10n.trackPlayerNoConfidentMatch);
    }
    return playVideo(
      videoId: video.id,
      title: hit.title,
      artist: hit.artistLabel,
      titleLatin: hit.titleLatin,
      artistLatin: hit.artistLatin,
      language: hit.mainSong?.language,
      coverOf: hit.coverOf,
      version: hit.version,
      coverSeed: hit.coverSeed,
      cover: CoverRequest.of(hit),
      searchQuery: searchQuery,
      playlistName: playlistName,
      allowExternal: allowExternal,
      onStatus: onStatus,
      foundVideo: video,
      hit: hit,
    );
  }

  /// The best video YouTube search has for [hit]; nothing is remembered.
  Future<YouTubeVideo?> pickVideo(SearchHit hit) async {
    final target = hit.youTubeTarget;
    return pickYouTubeVideo(target, [
      for (final v in await youTubeSearch.search(target.query, settings))
        if (_usable(hit, v.id)) v,
    ]);
  }

  /// Not removed from YouTube, nor turned down by MusicDatabase for [hit]'s song.
  bool _usable(SearchHit hit, String videoId) {
    final mainSong = hit.mainSong;
    return !youTubeLibrary.isVideoRemoved(videoId) &&
        !(mainSong != null && youTubeLibrary.isWrongFor(mainSong.id, videoId));
  }

  /// The video a Biblioteka playlist has for [hit]'s music.db song, when the matcher finds it
  /// plausible for the song by the track's names ([pickYouTubeVideo]) and it isn't removed or
  /// turned down — the version the user saved beats a fresh search (song #5965: played from
  /// search, the phone found and reported a remix while a playlist held the original).
  YouTubeVideo? _playlistVideo(SearchHit hit, {bool notAgeRestricted = false}) {
    final mainSong = hit.mainSong;
    if (mainSong == null) return null;
    // In playlist order: the first plausible one, not the matcher's best score.
    for (final v in playlistVideosOf?.call(mainSong.id) ?? const []) {
      if (!youTubeLibrary.isVideoRemoved(v.id) &&
          !(notAgeRestricted && youTubeLibrary.isAgeRestricted(v.id)) &&
          !youTubeLibrary.isWrongFor(mainSong.id, v.id) &&
          pickYouTubeVideo(hit.youTubeTarget, [v]) != null) {
        return v;
      }
    }
    return null;
  }

  /// The best video for [hit] — a playlist's own ([_playlistVideo]), else YouTube search's —
  /// remembered so the next play uses it (or its cached audio) without searching again, and
  /// the icon turns full; a MusicDatabase song's video also goes to the outbox as a suggestion.
  /// Finding none is remembered too ([YouTubeLibrary.saveNotFound]).
  Future<YouTubeVideo?> findVideo(SearchHit hit) async {
    final mainSong = hit.mainSong;
    final video = _playlistVideo(hit) ?? await pickVideo(hit);
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

  /// Another upload of [hit] to play instead of the age-restricted [videoId] — a playlist's
  /// video, else YouTube search's (one with a video or a "Topic" channel's audio usually has no
  /// age check), never a video known to have one — remembered with it ([YouTubeLibrary
  /// .saveStandIn]), found or not. Only on the phone: music.db's link stays, and nothing goes to
  /// the outbox, as the video is the right one.
  Future<YouTubeVideo?> findStandIn(SearchHit hit, String videoId) async {
    var video = _playlistVideo(hit, notAgeRestricted: true);
    if (video == null) {
      final target = hit.youTubeTarget;
      try {
        final found = await youTubeSearch.search(target.query, settings);
        // The search usually finds the age-restricted video too: its channel names the act.
        final channel = found
            .where((v) => v.id == videoId)
            .firstOrNull
            ?.channel;
        video = pickYouTubeVideo(
          channel == null
              ? target
              : target.withArtistAlias(
                  channel.replaceFirst(_channelSuffix, ''),
                ),
          [
            for (final v in found)
              if (_usable(hit, v.id) && !youTubeLibrary.isAgeRestricted(v.id))
                v,
          ],
        );
      } on YouTubeSearchException catch (e) {
        debugPrint('Searching a stand-in for $videoId failed: $e');
        return null;
      }
    }
    if (video?.id == videoId) video = null;
    await youTubeLibrary.saveStandIn(videoId, video);
    return video;
  }

  static final _channelSuffix = RegExp(
    r'\s*(?:-\s*Topic|VEVO|Official)$',
    caseSensitive: false,
  );

  /// [videoId], or the upload played in its place when YouTube age-restricts it.
  String _playableVideo(String videoId) =>
      youTubeLibrary.standInFor(videoId) ?? videoId;

  /// MusicDatabase's own link of [hit] is [gone]: worth telling MusicDatabase. Not one the
  /// user set in its place ([CatalogSong.userLinks]).
  Future<void> _reportIfMainLink(SearchHit hit, String gone) async {
    final song = hit.mainSong?.fromMusicDb;
    if (song == null || song.youtubeVideoId != gone) return;
    await _report(() => outbox?.reportDeadYouTubeLink(song, gone));
  }

  /// Only against a loaded music.db: it says what MusicDatabase has, what its owner rejected
  /// and which requests it settled as one of its songs.
  Future<void> _requestIfMissing(SearchHit hit) async {
    final catalog = this.catalog;
    if (outbox == null ||
        catalog == null ||
        catalog.status != CatalogStatus.ready) {
      return;
    }
    final request = SongRequest.of(hit, artistNamed: catalog.artistNamed);
    if (request == null ||
        catalog.rejectedSongRequests.rejects(request) ||
        catalog.findSettledRequest(
              title: request.title,
              artist: request.artist,
              videoId: request.youtubeVideoId,
              spotifyTrackId: request.spotifyTrackId,
            ) !=
            null) {
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

  /// The tags at the start of server file [fileId] ([fetchServerFileHead]) from the first of
  /// MusicDatabase's addresses that answers, for its cover.
  Future<Uint8List?> serverFileHead(int fileId) async {
    final addresses = await _serverAddresses();
    if (addresses.isEmpty) throw StateError('No server address');
    Object? failure;
    for (final base in addresses) {
      try {
        return await fetchServerFileHead(base.resolve('library/$fileId'));
      } catch (e) {
        failure = e;
      }
    }
    throw failure!;
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
      ], name: downloadBaseName(hit.artistLabel, hit.title))) {
        if (_mp3Converter case final convert?) {
          await downloads.convertToMp3(server.id, await _tagsOf(hit), convert);
        }
        return DownloadOutcome.downloaded;
      }
    }
    if (!settings.enabledSources.contains(PlaybackSource.youtube)) {
      return DownloadOutcome.failed;
    }
    if (!await _cacheYouTube(hit, pin: true)) return DownloadOutcome.failed;
    final videoId = _withRememberedVideo(hit).youtubeVideoId;
    if (_mp3Converter case final convert? when videoId != null) {
      await youTubeLibrary.convertToMp3(
        _playableVideo(videoId),
        await _tagsOf(hit),
        convert,
      );
    }
    return DownloadOutcome.downloaded;
  }

  Mp3Converter? get _mp3Converter =>
      settings.downloadsAsMp3 ? mp3Converter : null;

  Future<Mp3Tags> _tagsOf(SearchHit hit) async {
    Uint8List? cover;
    try {
      cover = await coverBytes?.call(hit);
    } catch (e) {
      debugPrint('Cover for the MP3 of "${hit.title}" failed: $e');
    }
    return Mp3Tags(
      title: hit.title,
      artist: hit.artistLabel,
      album: hit.album,
      year: hit.year,
      genre: hit.mainSong?.genres.firstOrNull,
      cover: cover,
    );
  }

  /// [hit] kept with "Pobierz": a downloaded server file or pinned YouTube audio.
  bool isDownloaded(SearchHit hit) {
    hit = _withRememberedVideo(hit);
    final server = hit.serverFile;
    if (server != null && (serverDownloads?.isDownloaded(server.id) ?? false)) {
      return true;
    }
    final videoId = hit.youtubeVideoId;
    return videoId != null && youTubeLibrary.isPinned(_playableVideo(videoId));
  }

  /// "Usuń z pobranych": a server file's copy is deleted, YouTube audio goes back to the cache.
  Future<void> removeDownload(SearchHit hit) async {
    hit = _withRememberedVideo(hit);
    if (hit.serverFile case final server?) {
      await serverDownloads?.remove(server.id);
    }
    if (hit.youtubeVideoId case final videoId?) {
      await youTubeLibrary.setPinned(
        _playableVideo(videoId),
        false,
        limit: settings.cacheKeep,
      );
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
    if (youTubeLibrary.isAgeRestricted(videoId)) {
      if (!settings.ageRestrictedStandIn ||
          youTubeLibrary.standInFor(videoId) == null &&
              (youTubeLibrary.noStandInFor(videoId) ||
                  await findStandIn(hit, videoId) == null)) {
        return false;
      }
      videoId = youTubeLibrary.standInFor(videoId)!;
    }
    final name = downloadBaseName(hit.artistLabel, hit.title);
    if (youTubeLibrary.isCached(videoId)) {
      if (pin) await youTubeLibrary.setPinned(videoId, true, name: name);
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
          name: name,
        )) {
          return true;
        }
      } on YouTubeAudioException catch (e) {
        debugPrint('Caching ahead: ${method.name} for $videoId failed: $e');
        if (e.ageRestricted && !youTubeLibrary.isAgeRestricted(videoId)) {
          // Found out before it plays: its stand-in is looked for (and cached) now. A stand-in
          // that is age-restricted too is marked, so this ends.
          await youTubeLibrary.markAgeRestricted(videoId);
          return _cacheYouTube(hit, pin: pin);
        }
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
    String? language,
    CoverOf? coverOf,
    SongVersion? version,
    required String coverSeed,
    CoverRequest? cover,
    String? searchQuery,
    String? playlistName,
    bool allowExternal = true,
    void Function(String status)? onStatus,
    YouTubeVideo? foundVideo,
    Uri? externalUri,
    SearchHit? hit,
  }) async {
    YouTubeVideo? standIn;
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
        (videoId, source, {streamQuality}) => NowPlaying(
          title: title,
          artist: artist,
          titleLatin: titleLatin,
          artistLatin: artistLatin,
          language: language,
          coverOf: coverOf,
          version: version,
          source: source,
          coverSeed: coverSeed,
          cover: cover?.withVideo(videoId),
          searchQuery: searchQuery,
          playlistName: playlistName,
          youtubeVideoId: videoId,
          streamQuality: streamQuality,
        ),
        onConnecting: () => onStatus?.call(l10n.trackPlayerConnectingYouTube),
        onStatus: onStatus,
        allowExternal: allowExternal,
        externalUri: externalUri,
        findStandIn: hit == null || !settings.ageRestrictedStandIn
            ? null
            : () async {
                final known = youTubeLibrary.standInFor(videoId);
                if (known != null) {
                  return YouTubeVideo(id: known, title: '', channel: '');
                }
                if (youTubeLibrary.noStandInFor(videoId)) return null;
                onStatus?.call(l10n.trackPlayerAgeRestrictedSearching);
                return standIn = await findStandIn(hit, videoId);
              },
      );
      switch (via) {
        case YouTubePlayedVia.youtubeApp:
          return PlayOutcome.external(l10n.trackPlayerOpenedInYouTubeApp);
        case YouTubePlayedVia.youtubeAppAgeRestricted:
          return PlayOutcome.external(
            l10n.trackPlayerOpenedInYouTubeAppAgeRestricted,
          );
        case YouTubePlayedVia.cache || YouTubePlayedVia.stream:
      }
      // The phone picked this video itself, so say which one it is.
      if (standIn case final standIn?) {
        return PlayOutcome.played(
          l10n.trackPlayerAgeRestrictedStandIn(standIn.title, standIn.channel),
        );
      }
      return PlayOutcome.played(
        foundVideo == null
            ? null
            : l10n.trackPlayerFromYouTube(foundVideo.title, foundVideo.channel),
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
