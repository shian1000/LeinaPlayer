import 'dart:math';

import 'package:flutter/material.dart';

/// The "this song is playing" mark next to a title, like the reference app's: thin bars that
/// bounce while music plays and stand still while it's paused.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = 16,
  });

  final bool playing;
  final Color color;
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  // One slow cycle; each bar runs through it at its own whole-number speed, so the bars look
  // independent yet the loop has no visible seam.
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _BarsPainter(_controller, widget.color)),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  static const _speeds = [3, 5, 4, 6];
  static const _phases = [0.0, 1.3, 2.6, 0.7];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final count = _speeds.length;
    final gap = size.width * 0.12;
    final width = (size.width - gap * (count - 1)) / count;
    final t = progress.value * 2 * pi;
    for (var i = 0; i < count; i++) {
      // 25–100 % of the height; paused, the bars keep whatever height they stopped at.
      final level =
          0.25 + 0.75 * (0.5 + 0.5 * sin(t * _speeds[i] + _phases[i]));
      final height = size.height * level;
      canvas.drawRect(
        Rect.fromLTWH(i * (width + gap), size.height - height, width, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}
