import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/lyrics.dart';
import '../data/source_settings.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../data/saved_songs.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/queue_toast.dart';
import '../theme_controller.dart';
import '../widgets/song_tile.dart';
import '../widgets/share_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_info.dart';
import 'queue_screen.dart';
import '../widgets/song_names.dart';

const _id = 'Odtwarzacz';

/// Background tint of the players, from the album cover's colour like the reference app (the
/// placeholder's colour when there's no cover); changes fade.
class _CoverTint extends StatefulWidget {
  const _CoverTint({required this.track, required this.builder});

  final NowPlaying track;
  final Widget Function(BuildContext context, Color tint) builder;

  @override
  State<_CoverTint> createState() => _CoverTintState();
}

class _CoverTintState extends State<_CoverTint> {
  Color? _cover;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_CoverTint old) {
    super.didUpdateWidget(old);
    if (old.track.cover.identity != widget.track.cover.identity) _resolve();
  }

  void _resolve() {
    final covers = AlbumCoversScope.maybeOf(context);
    if (covers == null) return;
    final track = widget.track;
    covers
        .colorOf(track.cover)
        .then((color) {
          if (mounted && identical(track, widget.track)) {
            setState(() => _cover = color);
          }
        })
        .catchError((Object e) => debugPrint('Cover colour failed: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themes = ThemeScope.maybeOf(context);
    // A filtered cover's colour is the filter's.
    final filtered = _cover == null
        ? null
        : switch (themes?.coverFilter ?? CoverFilter.none) {
            CoverFilter.none => _cover,
            CoverFilter.lain => const Color(0xFF1C6478),
            // With a background of its own the screen is as much that colour as the dots'.
            CoverFilter.monochrome => Color.lerp(
              themes!.monochromeColor,
              themes.monochromeBackground ?? themes.monochromeColor,
              0.5,
            ),
          };
    final cover = filtered == null
        ? null
        : Color.lerp(_cover, filtered, themes?.coverFilterStrength ?? 1);
    final Color base;
    if (cover == null) {
      base = palette.colorForSeed(widget.track.coverSeed);
    } else {
      // Kept away from the background's own lightness, so the text on it stays readable
      // (placeholder colours already are).
      final dark = palette.background.computeLuminance() < 0.5;
      final hsl = HSLColor.fromColor(cover);
      base = hsl
          .withLightness(
            dark ? min(hsl.lightness, 0.5) : max(hsl.lightness, 0.55),
          )
          .toColor();
    }
    final tint = Color.lerp(base, palette.background, 0.45)!;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint),
      duration: const Duration(milliseconds: 400),
      builder: (context, color, _) => widget.builder(context, color ?? tint),
    );
  }
}

String _formatTime(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// The cover's size in [NowPlayingScreen].
double _fullCoverSize(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return min(size.width - 48, size.height * 0.42);
}

/// Gets the full player's cover ready (found, decoded, filtered) as soon as a song is on, so
/// opening the player shows it in its first frame.
class _FullCoverReady extends StatefulWidget {
  const _FullCoverReady({required this.track, required this.child});

  final NowPlaying track;
  final Widget child;

  @override
  State<_FullCoverReady> createState() => _FullCoverReadyState();
}

class _FullCoverReadyState extends State<_FullCoverReady> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also when the filter changes (coverImageFor depends on the theme scope).
    _prepare();
  }

  @override
  void didUpdateWidget(_FullCoverReady old) {
    super.didUpdateWidget(old);
    if (old.track.cover.identity != widget.track.cover.identity) _prepare();
  }

  void _prepare() => precacheSongCover(
    context,
    widget.track.cover,
    _fullCoverSize(context),
  ).catchError((Object e) => debugPrint('Preparing the cover failed: $e'));

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Card above the bottom bar showing what's playing; tap to open [NowPlayingScreen], long press
/// for quick actions ([_showQuickActions]).
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = PlayerScope.of(context);
    final track = player.current;
    if (track == null) return const SizedBox.shrink();

    return _FullCoverReady(
      track: track,
      child: _CoverTint(
        track: track,
        builder: (context, tint) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Material(
            color: tint,
            shape: palette.boxShape(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => NowPlayingScreen.open(context),
              onLongPress: () {
                final hit = PlaybackQueueScope.of(context).current;
                if (hit == null) return;
                _showQuickActions(context, hit);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SwipeTracks(
                            child: Row(
                              children: [
                                SongCover(cover: track.cover, size: 40),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.shownTitle(context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: AppFontSize.body,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        withFullAlbumLabel(
                                          PlaybackQueueScope.of(context)
                                              .current,
                                          track.shownArtist(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: AppFontSize.small,
                                          color: palette.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _AddToPlaylistButton(
                          hit: PlaybackQueueScope.of(context).current,
                        ),
                        IconButton(
                          tooltip: player.playing ? 'Pauza' : 'Odtwórz',
                          icon: Icon(
                            player.playing ? Icons.pause : Icons.play_arrow,
                            size: 30,
                          ),
                          onPressed: player.togglePlay,
                        ),
                      ],
                    ),
                  ),
                  _ProgressLine(player: player),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Dodaj do playlisty" by the song's title; like Spotify's, an accent tick when the song is
/// liked (liking is in the sheet it opens).
class _AddToPlaylistButton extends StatelessWidget {
  const _AddToPlaylistButton({required this.hit, this.size});

  final SearchHit? hit;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final hit = this.hit;
    final liked =
        hit != null &&
        (LikedSongsScope.maybeOf(context)?.contains(hit) ?? false);
    return IconButton(
      tooltip: liked ? 'Polubione · Dodaj do playlisty' : 'Dodaj do playlisty',
      icon: Icon(
        liked ? Icons.check_circle : Icons.add_circle_outline,
        size: size,
        color: liked ? context.palette.accent : null,
      ),
      onPressed: () {
        final entry = hit == null ? null : playlistMenuEntry(context, [hit]);
        entry?.onTap?.call();
      },
    );
  }
}

/// Held mini player: a few buttons just above it, so the common things need no menu
/// (Juxtopposed's redesign); "Więcej" opens the full song menu.
Future<void> _showQuickActions(BuildContext context, SearchHit hit) {
  final saved = SavedSongsScope.maybeOf(context);
  final moods = MoodLibraryScope.maybeOf(context);
  final playlist = playlistMenuEntry(context, [hit]);
  final box = context.findRenderObject() as RenderBox?;
  final top = box == null
      ? MediaQuery.sizeOf(context).height / 2
      : box.localToGlobal(Offset.zero).dy;
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Zamknij',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, _) {
      final palette = dialogContext.palette;
      Widget action(IconData icon, String label, VoidCallback onTap) =>
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: palette.surfaceHigh,
                shape: palette.boxShape(12),
                child: InkWell(
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppFontSize.badge),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
      return Stack(
        children: [
          Positioned(
            left: 8,
            right: 8,
            top: max(top - 80, 0),
            child: Row(
              children: [
                if (moods != null)
                  action(
                    moodIcon,
                    'Nastrój',
                    () => openMoodPicker(context, hit),
                  ),
                if (saved != null)
                  saved.contains(hit)
                      ? action(
                          Icons.bookmark,
                          'Zapisane',
                          () => saved.toggle(hit),
                        )
                      : action(
                          Icons.bookmark_border,
                          'Na później',
                          () => saved.toggle(hit),
                        ),
                if (playlist?.onTap case final onTap?)
                  action(Icons.add_circle_outline, 'Playlista', onTap),
                action(
                  Icons.more_horiz,
                  'Więcej',
                  () => showSongMenu(
                    context,
                    hit,
                    idPrefix: 'Mini odtwarzacz › Menu utworu',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The mini player's song: dragged sideways like in the reference app — left for the next song,
/// right for the previous one (always that song, not the start of this one). Past a quarter of
/// its width it slides out and the new song slides in from the other side; without a song to
/// go to it only gives a little and springs back.
class _SwipeTracks extends StatefulWidget {
  const _SwipeTracks({required this.child});

  final Widget child;

  @override
  State<_SwipeTracks> createState() => _SwipeTracksState();
}

class _SwipeTracksState extends State<_SwipeTracks>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);
  double _drag = 0;
  double _width = 0;

  static const _slide = Duration(milliseconds: 160);

  bool _can(double drag, PlaybackQueue queue) =>
      drag < 0 ? queue.hasNext : queue.hasPrevious;

  void _update(DragUpdateDetails details, PlaybackQueue queue) {
    _drag += details.primaryDelta!;
    // Nowhere to go that way: it only gives a little.
    _offset.value = _can(_drag, queue) ? _drag : _drag * 0.2;
  }

  Future<void> _end(PlaybackQueue queue) async {
    final drag = _drag;
    _drag = 0;
    if (drag.abs() < _width / 4 || !_can(drag, queue)) {
      await _offset.animateTo(0, duration: _slide, curve: Curves.easeOut);
      return;
    }
    final next = drag < 0;
    await _offset.animateTo(
      next ? -_width : _width,
      duration: _slide,
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    unawaited(
      runQueueAction(
        context,
        (onStatus) => next
            ? queue.next(onStatus: onStatus)
            : queue.previous(restart: false, onStatus: onStatus),
      ),
    );
    _offset.value = next ? _width : -_width;
    await _offset.animateTo(0, duration: _slide, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = PlaybackQueueScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => _update(d, queue),
          onHorizontalDragEnd: (_) => _end(queue),
          onHorizontalDragCancel: () => _end(queue),
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _offset,
              child: widget.child,
              builder: (context, child) => Transform.translate(
                offset: Offset(_offset.value, 0),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return StreamBuilder<Duration>(
      stream: player.position,
      initialData: player.currentPosition,
      builder: (context, snapshot) {
        final total = player.duration?.inMilliseconds ?? 0;
        final done = snapshot.data?.inMilliseconds ?? 0;
        return LinearProgressIndicator(
          value: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
          minHeight: 2,
          color: palette.textPrimary,
          backgroundColor: palette.textPrimary.withValues(alpha: 0.2),
        );
      },
    );
  }
}

/// How much of "Informacje o utworze" shows below the full player before scrolling.
const _infoPeek = 44.0;

/// Full-screen player ("Teraz odtwarzane"), slid up from the mini player; scrolled down, the
/// song's details ([SongInfoCard]).
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  /// Opens on the root navigator, so it covers the bottom bar like in the reference app.
  static Future<void> open(BuildContext context) {
    QueueToastScope.maybeOf(context)?.hide();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const NowPlayingScreen(),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  /// The song in the YouTube app (inside its playlist when played from one), from the moment
  /// this app's player is at; the player pauses so the two don't play over each other.
  static Future<void> _openInYouTube(
    BuildContext context,
    PlayerController player,
    Uri uri, {
    bool fromHere = true,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final at = player.currentPosition;
    if (player.playing) await player.togglePlay();
    if (!await openInYouTube(fromHere ? youTubeUriAt(uri, at) : uri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć YouTube.')),
      );
    }
  }

  /// With a music video as well as the song, asks which of them; the video from its start —
  /// it doesn't run in step with the song.
  static Future<void> _chooseOnYouTube(
    BuildContext context,
    PlayerController player, {
    required Uri? song,
    required Uri? musicVideo,
  }) async {
    if (musicVideo == null || song == null) {
      final uri = (song ?? musicVideo)!;
      return _openInYouTube(context, player, uri, fromHere: song != null);
    }
    await showMenuSheet(
      context,
      idPrefix: '$_id › Otwórz w YouTube',
      entries: [
        MenuSheetEntry(
          Icons.music_note_outlined,
          'Utwór na YouTube',
          subtitle: 'Od miejsca, w którym jest odtwarzacz',
          onTap: () => _openInYouTube(context, player, song),
        ),
        MenuSheetEntry(
          Icons.movie_outlined,
          'Teledysk na YouTube',
          subtitle: 'Od początku',
          onTap: () =>
              _openInYouTube(context, player, musicVideo, fromHere: false),
        ),
      ],
    );
  }

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

/// What the full player shows where the cover is.
enum _Stage { cover, queue }

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  _Stage _stage = _Stage.cover;

  /// Tapping the shown one's button again brings the cover back.
  void _toggle(_Stage stage) =>
      setState(() => _stage = _stage == stage ? _Stage.cover : stage);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = PlayerScope.of(context);
    final queue = PlaybackQueueScope.of(context);
    final track = player.current;
    if (track == null) {
      // Playback failed or was cleared while this screen was open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    final youTubeUri = queue.currentYouTubeUri;
    final musicVideoUri = queue.currentMusicVideoUri;
    final coverSize = _fullCoverSize(context);
    final moodFilter = MoodFilterScope.maybeOf(context);

    return _CoverTint(
      track: track,
      builder: (context, tint) => Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tint, palette.background],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  SizedBox(
                    // The info card's top shows below the player, so it's clear there's more.
                    height: max(constraints.maxHeight - _infoPeek, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Zwiń',
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                size: 32,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    track.playlistName != null
                                        ? 'Odtwarzanie z playlisty'
                                        : track.searchQuery != null
                                        ? 'Odtwarzanie z wyników wyszukiwania'
                                        : 'Teraz odtwarzane',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: AppFontSize.small,
                                    ),
                                  ),
                                  if (track.playlistName != null ||
                                      track.searchQuery != null)
                                    Text(
                                      track.playlistName ??
                                          '„${track.searchQuery}” w wyszukiwarce',
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: AppFontSize.body,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Balances "Zwiń"; the menu is down by the thumb.
                            const SizedBox(width: 48),
                          ],
                        ),
                        // Lyrics and the queue open here, so the controls stay where they
                        // are, under the thumb (Juxtopposed's Spotify redesign).
                        Expanded(
                          child: switch (_stage) {
                            _Stage.cover => Center(
                              child: SongCover(
                                cover: track.cover,
                                size: coverSize,
                              ),
                            ),
                            _Stage.queue => _QueuePanel(
                              onClose: () => _toggle(_Stage.queue),
                            ),
                          },
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.shownTitle(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: AppFontSize.largeTitle,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    withFullAlbumLabel(
                                      queue.current,
                                      track.shownArtist(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.listTitle,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (queue.current case final hit?)
                              _MoodButton(hit: hit),
                            _AddToPlaylistButton(hit: queue.current, size: 30),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SeekBar(player: player),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: queue.shuffle
                                  ? 'Losowo: wł.'
                                  : 'Losowo: wył.',
                              icon: Icon(
                                Icons.shuffle,
                                size: 28,
                                color: queue.shuffle ? palette.accent : null,
                              ),
                              onPressed: () => queue.setShuffle(!queue.shuffle),
                            ),
                            IconButton(
                              tooltip: 'Poprzedni',
                              icon: const Icon(Icons.skip_previous, size: 40),
                              // Restarts the song, or near its start goes back (PlaybackQueue.previous).
                              onPressed: () => runQueueAction(
                                context,
                                (onStatus) =>
                                    queue.previous(onStatus: onStatus),
                              ),
                            ),
                            Material(
                              color: palette.textPrimary,
                              shape: palette.rounded
                                  ? const CircleBorder()
                                  : const RoundedRectangleBorder(),
                              child: IconButton(
                                tooltip: player.playing ? 'Pauza' : 'Odtwórz',
                                iconSize: 44,
                                padding: const EdgeInsets.all(12),
                                color: palette.background,
                                icon: Icon(
                                  player.playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                onPressed: player.togglePlay,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Następny',
                              icon: const Icon(Icons.skip_next, size: 40),
                              onPressed: queue.hasNext
                                  ? () => runQueueAction(
                                      context,
                                      (onStatus) =>
                                          queue.next(onStatus: onStatus),
                                    )
                                  : null,
                            ),
                            // The sleep timer moved to the song's menu.
                            IconButton(
                              tooltip: switch (queue.repeat) {
                                QueueRepeat.off => 'Powtarzaj: wył.',
                                QueueRepeat.all => 'Powtarzaj: wszystkie',
                                QueueRepeat.one => 'Powtarzaj: utwór',
                              },
                              icon: Icon(
                                queue.repeat == QueueRepeat.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                size: 28,
                                color: queue.repeat == QueueRepeat.off
                                    ? null
                                    : palette.accent,
                              ),
                              onPressed: () => queue.setRepeat(
                                QueueRepeat.values[(queue.repeat.index + 1) %
                                    QueueRepeat.values.length],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: 'Otwórz w YouTube',
                              icon: const Icon(Icons.smart_display_outlined),
                              onPressed:
                                  youTubeUri == null && musicVideoUri == null
                                  ? null
                                  : () => NowPlayingScreen._chooseOnYouTube(
                                      context,
                                      player,
                                      song: youTubeUri,
                                      musicVideo: musicVideoUri,
                                    ),
                            ),
                            IconButton(
                              tooltip: moodFilter?.active ?? false
                                  ? 'Filtr nastrojów: wł.'
                                  : 'Filtr nastrojów: wył.',
                              icon: Icon(
                                Icons.filter_list,
                                color: moodFilter?.active ?? false
                                    ? palette.accent
                                    : null,
                              ),
                              onPressed: moodFilter == null
                                  ? null
                                  : () => showMoodFilterSheet(context),
                            ),
                            IconButton(
                              tooltip: 'Udostępnij',
                              icon: const Icon(Icons.share_outlined),
                              onPressed: queue.current == null
                                  ? null
                                  : () => showSongShareSheet(
                                      context,
                                      queue.current!,
                                      idPrefix: _id,
                                    ),
                            ),
                            IconButton(
                              tooltip: 'Kolejka',
                              icon: Icon(
                                Icons.queue_music,
                                color: _stage == _Stage.queue
                                    ? palette.accent
                                    : null,
                              ),
                              onPressed: () => _toggle(_Stage.queue),
                            ),
                            IconButton(
                              tooltip: 'Menu odtwarzacza (⋮)',
                              icon: const Icon(Icons.more_vert),
                              onPressed: () {
                                final hit = queue.current;
                                if (hit == null) return;
                                showSongMenu(
                                  context,
                                  hit,
                                  idPrefix: '$_id › Menu (⋮)',
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  // The lyrics peek out under the player; the song's details below them.
                  if (queue.current != null) ...[
                    if (SourceSettingsScope.maybeOf(context)?.lyrics ??
                        true) ...[
                      const _LyricsCard(),
                      const SizedBox(height: 16),
                    ],
                    SongInfoCard(hit: queue.current!, track: track),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The song's lyrics in a card under the player, from LRCLIB ([LyricsFinder]) while
/// MusicDatabase has none: time-synced lines follow the song (the current one highlighted,
/// kept in view inside the card), else the plain text.
class _LyricsCard extends StatefulWidget {
  const _LyricsCard();

  @override
  State<_LyricsCard> createState() => _LyricsCardState();
}

class _LyricsCardState extends State<_LyricsCard> {
  SearchHit? _hit;
  Future<Lyrics?>? _lyrics;
  final _lineKeys = <int, GlobalKey>{};
  final _scroll = ScrollController();
  int _shownLine = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hit = PlaybackQueueScope.of(context).current;
    if (hit != null && !identical(hit, _hit)) {
      _hit = hit;
      _lyrics = LyricsFinder.instance.find(hit);
      _lineKeys.clear();
      _shownLine = -1;
    }
  }

  void _keepInView(int line) {
    if (line == _shownLine) return;
    _shownLine = line;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only the card scrolls: Scrollable.ensureVisible would move the whole player too.
      final row = _lineKeys[_shownLine]?.currentContext?.findRenderObject();
      if (row == null || !_scroll.hasClients) return;
      final offset = RenderAbstractViewport.of(row)
          .getOffsetToReveal(row, 0.35)
          .offset;
      _scroll.animateTo(
        offset.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = PlayerScope.of(context);
    Widget note(String text, {Widget? action}) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, size: 48, color: palette.textSecondary),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
    return Container(
      height: 360,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: palette.surfaceHigh.withValues(alpha: 0.7),
        borderRadius: palette.radius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Tekst',
              style: TextStyle(
                fontSize: AppFontSize.listTitle,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<Lyrics?>(
              future: _lyrics,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return note('Szukam tekstu…');
                }
                if (snapshot.hasError) {
                  return note(
                    'Nie udało się pobrać tekstu. Brak połączenia?',
                    action: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Spróbuj ponownie'),
                      onPressed: () => setState(() {
                        _lyrics = LyricsFinder.instance.find(_hit!);
                      }),
                    ),
                  );
                }
                final lyrics = snapshot.data;
                if (lyrics == null) {
                  return note('Nie znalazłem tekstu tego utworu.');
                }
                if (lyrics.instrumental) return note('Utwór instrumentalny.');
                if (lyrics.synced.isEmpty) {
                  return SingleChildScrollView(
                    child: Text(
                      lyrics.plain!,
                      style: const TextStyle(
                        fontSize: AppFontSize.listTitle,
                        height: 1.5,
                      ),
                    ),
                  );
                }
                return StreamBuilder<Duration>(
                  stream: player.position,
                  initialData: player.currentPosition,
                  builder: (context, position) {
                    final at = position.data ?? Duration.zero;
                    final current = lyrics.synced.lastIndexWhere(
                      (line) => line.at <= at,
                    );
                    _keepInView(current);
                    return SingleChildScrollView(
                      controller: _scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, line) in lyrics.synced.indexed)
                            GestureDetector(
                              key: _lineKeys.putIfAbsent(i, GlobalKey.new),
                              // Tapping a line jumps the song there.
                              onTap: () => player.seek(line.at),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  line.text.isEmpty ? '♪' : line.text,
                                  style: TextStyle(
                                    fontSize: AppFontSize.listTitle,
                                    fontWeight: i == current
                                        ? FontWeight.bold
                                        : null,
                                    color: i == current
                                        ? palette.textPrimary
                                        : i < current
                                        ? palette.textSecondary
                                        : palette.textPrimary.withValues(
                                            alpha: 0.75,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Text(
            'Teksty: LRCLIB',
            style: TextStyle(
              fontSize: AppFontSize.badge,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What plays next, in place of the cover: tapping a song plays it; the whole queue
/// (reordering, removing, "Poprzednie") is one tap away.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final queue = PlaybackQueueScope.of(context);
    final upcoming = queue.upcoming;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      decoration: BoxDecoration(
        color: palette.surfaceHigh.withValues(alpha: 0.7),
        borderRadius: palette.radius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _PanelHeader(
              title: 'Następne',
              onClose: onClose,
              action: TextButton(
                onPressed: () => QueueScreen.open(context),
                child: const Text('Cała kolejka'),
              ),
            ),
          ),
          Expanded(
            child: upcoming.isEmpty
                ? Center(
                    child: Text(
                      'Po tym utworze nic więcej nie zagra.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: upcoming.length,
                    itemBuilder: (context, i) {
                      final entry = upcoming[i];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: SongCover(
                          cover: CoverRequest.of(entry.hit),
                          size: 40,
                        ),
                        title: Text(
                          entry.hit.shownTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          withFullAlbumLabel(
                            entry.hit,
                            entry.hit.shownArtist(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => runQueueAction(
                          context,
                          (onStatus) => queue.jumpTo(entry, onStatus: onStatus),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.onClose, this.action});

  final String title;
  final VoidCallback onClose;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: AppFontSize.listTitle,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      ?action,
      IconButton(
        tooltip: 'Pokaż okładkę',
        icon: const Icon(Icons.close),
        onPressed: onClose,
      ),
    ],
  );
}

/// The song's moods (accent when it's in any), tapped to change them; in place of "Polub".
class _MoodButton extends StatelessWidget {
  const _MoodButton({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final songId = hit.mainSong?.id;
    final names = songId == null
        ? const <String>[]
        : MoodLibraryScope.of(context).moodNameListOf(songId);
    return IconButton(
      tooltip: names.isEmpty ? 'Nastrój' : 'Nastrój: ${names.join(', ')}',
      icon: Icon(
        moodIcon,
        size: 28,
        color: names.isEmpty ? null : context.palette.accent,
      ),
      onPressed: () => openMoodPicker(context, hit),
    );
  }
}

/// Position slider with elapsed / total time; dragging only seeks on release. Tapping the
/// total time switches it to the time left (and back), remembered like in Spotify.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});

  final PlayerController player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  static const _showRemainingKey = 'player.show_remaining_time';

  /// Kept across opens of the full player so it never shows the other time for a frame.
  static bool? _rememberedShowRemaining;

  double? _dragMs;
  bool _showRemaining = _rememberedShowRemaining ?? false;

  @override
  void initState() {
    super.initState();
    if (_rememberedShowRemaining == null) unawaited(_load());
  }

  Future<void> _load() async {
    final value =
        (await SharedPreferences.getInstance()).getBool(_showRemainingKey) ??
        false;
    _rememberedShowRemaining ??= value;
    if (mounted) setState(() => _showRemaining = _rememberedShowRemaining!);
  }

  void _toggleRemaining() {
    final value = !_showRemaining;
    _rememberedShowRemaining = value;
    setState(() => _showRemaining = value);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_showRemainingKey, value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = widget.player.duration ?? Duration.zero;
    return StreamBuilder<Duration>(
      stream: widget.player.position,
      initialData: widget.player.currentPosition,
      builder: (context, snapshot) {
        final maxMs = max(total.inMilliseconds.toDouble(), 1.0);
        final positionMs =
            _dragMs ??
            (snapshot.data?.inMilliseconds.toDouble() ?? 0).clamp(0.0, maxMs);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: palette.textPrimary,
                inactiveTrackColor: palette.textPrimary.withValues(alpha: 0.25),
                thumbColor: palette.textPrimary,
              ),
              child: Slider(
                value: positionMs,
                max: maxMs,
                onChanged: total == Duration.zero
                    ? null
                    : (v) => setState(() => _dragMs = v),
                onChangeEnd: (v) {
                  widget.player.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragMs = null);
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(Duration(milliseconds: positionMs.round())),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: palette.textSecondary,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleRemaining,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      _showRemaining
                          ? '-${_formatTime(total - Duration(milliseconds: positionMs.round()))}'
                          : _formatTime(total),
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
