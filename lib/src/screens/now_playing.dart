import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../dummy.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import '../widgets/queue_toast.dart';
import '../theme_controller.dart';
import '../widgets/song_tile.dart';
import '../widgets/share_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_info.dart';
import 'queue_screen.dart';

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
/// for the song's menu.
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
                showSongMenu(
                  context,
                  hit,
                  idPrefix: 'Mini odtwarzacz › Menu utworu',
                );
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
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: AppFontSize.body,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        track.artist,
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
class NowPlayingScreen extends StatelessWidget {
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

  /// The song in the YouTube app (inside its playlist when played from one); this app's player
  /// pauses so the two don't play over each other.
  static Future<void> _openInYouTube(
    BuildContext context,
    PlayerController player,
    Uri uri,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (player.playing) await player.togglePlay();
    if (!await openInYouTube(uri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć YouTube.')),
      );
    }
  }

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
    void dummy(String label) => showDummy(context, '$_id › $label');
    final youTubeUri = queue.currentYouTubeUri;
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
                            IconButton(
                              tooltip: 'Menu odtwarzacza (⋮)',
                              icon: const Icon(Icons.more_vert),
                              onPressed: () {
                                final hit = queue.current;
                                if (hit == null) return dummy('Menu (⋮)');
                                showSongMenu(
                                  context,
                                  hit,
                                  idPrefix: '$_id › Menu (⋮)',
                                );
                              },
                            ),
                          ],
                        ),
                        const Spacer(),
                        SongCover(cover: track.cover, size: coverSize),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: AppFontSize.largeTitle,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    track.artist,
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
                            IconButton(
                              tooltip: 'Otwórz w YouTube',
                              icon: const Icon(
                                Icons.smart_display_outlined,
                                size: 30,
                              ),
                              onPressed: youTubeUri == null
                                  ? null
                                  : () => _openInYouTube(
                                      context,
                                      player,
                                      youTubeUri,
                                    ),
                            ),
                            IconButton(
                              tooltip: 'Dodaj (+)',
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 30,
                              ),
                              onPressed: () => dummy('Dodaj (+)'),
                            ),
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
                            IconButton(
                              tooltip: 'Wyłącznik czasowy',
                              icon: const Icon(Icons.timer_outlined, size: 28),
                              onPressed: () => dummy('Wyłącznik czasowy'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Urządzenia',
                              icon: const Icon(Icons.devices_other),
                              onPressed: () => dummy('Urządzenia'),
                            ),
                            if (moodFilter != null)
                              IconButton(
                                tooltip: moodFilter.active
                                    ? 'Filtr nastrojów: wł.'
                                    : 'Filtr nastrojów: wył.',
                                icon: Icon(
                                  Icons.filter_list,
                                  color: moodFilter.active
                                      ? palette.accent
                                      : null,
                                ),
                                onPressed: () => showMoodFilterSheet(context),
                              ),
                            Expanded(
                              child:
                                  moodFilter != null &&
                                      moodFilter.active &&
                                      queue.current != null
                                  ? Center(
                                      child: _MoodButton(hit: queue.current!),
                                    )
                                  : const SizedBox.shrink(),
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
                              icon: const Icon(Icons.queue_music),
                              onPressed: () => QueueScreen.open(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  if (queue.current != null)
                    SongInfoCard(hit: queue.current!, track: track),
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

/// "Nastrój" while the mood filter is on: the moods the song is in, tapped to change them.
class _MoodButton extends StatelessWidget {
  const _MoodButton({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final songId = hit.mainSong?.id;
    final names = songId == null
        ? const <String>[]
        : MoodLibraryScope.of(context).moodNameListOf(songId);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => openMoodPicker(context, hit),
      icon: const Icon(moodIcon, size: 20),
      label: Text(
        names.isEmpty ? 'Nastrój' : names.join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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
