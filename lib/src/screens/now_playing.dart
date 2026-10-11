import 'dart:math';

import 'package:flutter/material.dart';

import '../dummy.dart';
import '../playback/player_controller.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';

const _id = 'Odtwarzacz';

/// Background tint of the players, taken from the placeholder cover like the reference app does
/// with real artwork.
Color _tint(AppPalette palette, NowPlaying track) => Color.lerp(
  palette.colorForSeed(track.coverSeed),
  palette.background,
  0.45,
)!;

String _formatTime(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Card above the bottom bar showing what's playing; tap to open [NowPlayingScreen].
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = PlayerScope.of(context);
    final track = player.current;
    if (track == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Material(
        color: _tint(palette, track),
        shape: palette.boxShape(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => NowPlayingScreen.open(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                child: Row(
                  children: [
                    CoverArt(seed: track.coverSeed, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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

/// Full-screen player ("Teraz odtwarzane"), slid up from the mini player.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  /// Opens on the root navigator, so it covers the bottom bar like in the reference app.
  static Future<void> open(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = PlayerScope.of(context);
    final track = player.current;
    if (track == null) {
      // Playback failed or was cleared while this screen was open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    void dummy(String label) => showDummy(context, '$_id › $label');
    final size = MediaQuery.sizeOf(context);
    final coverSize = min(size.width - 48, size.height * 0.42);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_tint(palette, track), palette.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Zwiń',
                      icon: const Icon(Icons.keyboard_arrow_down, size: 32),
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
                            style: const TextStyle(fontSize: AppFontSize.small),
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
                      onPressed: () => dummy('Menu (⋮)'),
                    ),
                  ],
                ),
                const Spacer(),
                CoverArt(seed: track.coverSeed, size: coverSize),
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
                      tooltip: 'Dodaj (+)',
                      icon: const Icon(Icons.add_circle_outline, size: 30),
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
                      tooltip: 'Losowo',
                      icon: const Icon(Icons.shuffle, size: 28),
                      onPressed: () => dummy('Losowo'),
                    ),
                    IconButton(
                      tooltip: 'Poprzedni',
                      icon: const Icon(Icons.skip_previous, size: 40),
                      // No queue yet: "previous" restarts the song, as players do mid-track.
                      onPressed: () => player.seek(Duration.zero),
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
                          player.playing ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: player.togglePlay,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Następny',
                      icon: const Icon(Icons.skip_next, size: 40),
                      onPressed: () => dummy('Następny'),
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
                    const Spacer(),
                    IconButton(
                      tooltip: 'Udostępnij',
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => dummy('Udostępnij'),
                    ),
                    IconButton(
                      tooltip: 'Kolejka',
                      icon: const Icon(Icons.queue_music),
                      onPressed: () => dummy('Kolejka'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Position slider with elapsed / total time; dragging only seeks on release.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});

  final PlayerController player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = widget.player.duration ?? Duration.zero;
    return StreamBuilder<Duration>(
      stream: widget.player.position,
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
                Text(
                  _formatTime(total),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: palette.textSecondary,
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
