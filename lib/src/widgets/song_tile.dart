import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../data/youtube_matcher.dart';
import '../data/youtube_search.dart';
import '../playback/player_controller.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import 'cover_art.dart';

/// Result title; the song in the player is highlighted like in the reference app.
class CurrentTitle extends StatelessWidget {
  const CurrentTitle({super.key, required this.text, required this.isCurrent});

  final String text;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        if (isCurrent) ...[
          Icon(Icons.equalizer, size: 18, color: palette.accent),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrent ? TextStyle(color: palette.accent) : null,
          ),
        ),
      ],
    );
  }
}

/// Plays a YouTube video with the user's playback methods, in their order (cache, streaming —
/// downloaded to the cache meanwhile — or the YouTube app); see [YouTubePlayback].
Future<void> playYouTubeVideo(
  BuildContext context, {
  required String videoId,
  required String title,
  required String artist,
  required String coverSeed,
  String? searchQuery,
  String? playlistName,
  YouTubeVideo? foundVideo,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final playback = YouTubePlayback(
    audio: YouTubeScope.audioOf(context),
    library: YouTubeLibraryScope.of(context),
    settings: SourceSettingsScope.of(context),
    player: PlayerScope.of(context),
  );
  void say(String text, {Duration duration = const Duration(seconds: 4)}) =>
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(text), duration: duration));

  try {
    final via = await playback.play(
      videoId,
      (source) => NowPlaying(
        title: title,
        artist: artist,
        source: source,
        coverSeed: coverSeed,
        searchQuery: searchQuery,
        playlistName: playlistName,
        youtubeVideoId: videoId,
      ),
      onConnecting: () =>
          say('Łączę z YouTube…', duration: const Duration(seconds: 30)),
    );
    if (via == YouTubePlayedVia.youtubeApp) {
      say('Otwarto w aplikacji YouTube.');
    } else if (foundVideo != null) {
      say('Z YouTube: „${foundVideo.title}” (${foundVideo.channel})');
    } else {
      messenger.clearSnackBars();
    }
  } on YouTubePlaybackException catch (e) {
    say(e.message);
  }
}

String formatDuration(Duration d) {
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$seconds'
      : '${d.inMinutes}:$seconds';
}

void _showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// A song row — search results, playlists: cover, title (highlighted while it plays), details,
/// the source icons, and tapping plays it from the user's preferred source.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.hit,
    this.searchQuery,
    this.playlistName,
    this.subtitle,
    this.trailing,
  });

  final SearchHit hit;

  /// Where the song is played from, shown in the full player: a search, or a playlist.
  final String? searchQuery;
  final String? playlistName;

  /// Replaces the default "artist • album • year".
  final String? subtitle;

  /// Shown after the source icons (e.g. a ⋮ menu).
  final Widget? trailing;

  static const coverSize = 48.0;

  String get _coverSeed => hit.mainSong != null
      ? '${hit.mainSong!.id}'
      : hit.phoneFiles.isNotEmpty
      ? hit.phoneFiles.first.filePath
      : hit.youtubeVideoId ?? hit.title;

  /// Plays from the first source in the user's [SourceSettings.playbackOrder] that has the song;
  /// only when none has it, and YouTube might, YouTube is searched and the best-scoring video
  /// ([pickYouTubeVideo]) is played.
  Future<void> _onTap(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final player = PlayerScope.of(context);
    final settings = SourceSettingsScope.of(context);
    final source = settings.playbackOrder.where(hit.playableFrom).firstOrNull;
    switch (source) {
      case PlaybackSource.phone:
        final messenger = ScaffoldMessenger.of(context);
        final ok = await player.play(
          NowPlaying(
            title: hit.title,
            artist: hit.artistLabel,
            source: hit.phoneFiles.first.filePath,
            coverSeed: _coverSeed,
            searchQuery: searchQuery,
            playlistName: playlistName,
          ),
        );
        if (!ok && player.lastError != null) {
          messenger.showSnackBar(SnackBar(content: Text(player.lastError!)));
        }
      case PlaybackSource.youtube:
        await playYouTubeVideo(
          context,
          videoId: hit.youtubeVideoId!,
          title: hit.title,
          artist: hit.artistLabel,
          coverSeed: _coverSeed,
          searchQuery: searchQuery,
          playlistName: playlistName,
        );
      case null:
        if (hit.youTube == YouTubeLink.unknown) {
          await _findOnYouTube(context, settings);
        } else {
          _showSnack(
            context,
            'Ten utwór jest niedostępny — nie ma go na telefonie ani na YouTube.',
          );
        }
    }
  }

  Future<void> _findOnYouTube(
    BuildContext context,
    SourceSettings settings,
  ) async {
    if (!settings.youTubeSearchEnabled) {
      _showSnack(
        context,
        'Utworu nie ma na telefonie, a szukanie w serwisie YouTube jest wyłączone '
        '(Ustawienia › Źródła muzyki › YouTube).',
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final search = YouTubeScope.searchOf(context);
    // Clearing the queue too: a fast answer would otherwise wait behind "Szukam…".
    void say(String text, {Duration duration = const Duration(seconds: 4)}) =>
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(text), duration: duration));

    say('Szukam na YouTube…', duration: const Duration(seconds: 30));
    final target = hit.youTubeTarget;
    final List<YouTubeVideo> videos;
    try {
      videos = await search.search(target.query, settings);
    } on YouTubeSearchException catch (e) {
      say(e.message);
      return;
    }
    final video = pickYouTubeVideo(target, videos);
    if (video == null) {
      say('Nie znaleziono na YouTube pewnego dopasowania tego utworu.');
      return;
    }
    if (!context.mounted) return;
    // Remembered, so the next tap plays it (or its cached audio) without searching again, and
    // the icon turns full (ADR 0003: kept on the phone only).
    final mainSong = hit.mainSong;
    if (mainSong != null) {
      await YouTubeLibraryScope.of(context).saveMatch(mainSong.id, video);
    }
    if (!context.mounted) return;
    await playYouTubeVideo(
      context,
      videoId: video.id,
      title: hit.title,
      artist: hit.artistLabel,
      coverSeed: _coverSeed,
      searchQuery: searchQuery,
      playlistName: playlistName,
      // The phone picked this video itself, so say which one it is.
      foundVideo: video,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = PlayerScope.of(context).current;
    final videoId = hit.youtubeVideoId;
    final isCurrent =
        current != null &&
        (hit.phoneFiles.any((f) => f.filePath == current.source) ||
            (videoId != null && current.youtubeVideoId == videoId));
    final details =
        subtitle ??
        [
          hit.artistLabel,
          if (hit.album != null && hit.album!.isNotEmpty) hit.album!,
          if (hit.year != null) '${hit.year}',
        ].join(' • ');
    final trailing = this.trailing;
    return ListTile(
      contentPadding: trailing == null
          ? null
          : const EdgeInsets.only(left: 16, right: 4),
      leading: CoverArt(seed: _coverSeed, size: SongTile.coverSize),
      title: CurrentTitle(text: hit.title, isCurrent: isCurrent),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing == null
          ? _SourceIcons(hit: hit)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SourceIcons(hit: hit),
                trailing,
              ],
            ),
      onTap: () => _onTap(context),
    );
  }
}

/// Column of three small icons next to a result, as tall as the cover and half as wide:
/// in MusicDatabase, on the phone (with "*" when not in MusicDatabase yet), and on YouTube.
/// Each icon keeps its slot even when hidden, so they line up from row to row.
class _SourceIcons extends StatelessWidget {
  const _SourceIcons({required this.hit});

  final SearchHit hit;

  static const _slot = SongTile.coverSize / 3;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget slot({
      required bool visible,
      required String tooltip,
      required Widget child,
    }) => SizedBox.square(
      dimension: _slot,
      child: visible
          ? Tooltip(
              message: tooltip,
              child: Center(child: child),
            )
          : null,
    );

    return SizedBox(
      width: SongTile.coverSize / 2,
      height: SongTile.coverSize,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          slot(
            visible: hit.inMainDatabase,
            tooltip: 'W bazie danych',
            child: Icon(Icons.storage, size: 14, color: palette.textSecondary),
          ),
          slot(
            visible: hit.onPhone,
            tooltip: hit.pending
                ? 'Na telefonie, spoza bazy danych'
                : 'Na telefonie',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.smartphone, size: 14, color: palette.textSecondary),
                if (hit.pending)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Text(
                      '*',
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Full: MusicDatabase has the video. Dimmed: it doesn't, but searching YouTube may find
          // it. None: marked in MusicDatabase as not on YouTube.
          slot(
            visible: hit.youTube != YouTubeLink.notOnYouTube,
            tooltip: hit.youTube != YouTubeLink.linked
                ? 'Do wyszukania na YouTube'
                : hit.phoneMatch != null
                ? 'Na YouTube (znalezione przez telefon)'
                : 'Na YouTube',
            child: Icon(
              Icons.smart_display,
              size: 16,
              color: hit.youTube == YouTubeLink.linked
                  ? palette.textSecondary
                  : palette.textSecondary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}
