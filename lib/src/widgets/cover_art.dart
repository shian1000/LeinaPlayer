import 'package:flutter/material.dart';

import '../theme.dart';

/// Gradient placeholder instead of real artwork — cheap to draw on the old target phone.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.seed,
    this.size = 56,
    this.icon = Icons.music_note,
    this.circle = false,
  });

  final String seed;
  final double size;
  final IconData icon;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = palette.colorForSeed(seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : palette.radius(4),
        border: palette.outline == null
            ? null
            : Border.all(color: palette.outline!),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, palette.background, 0.55)!],
        ),
      ),
      child: Icon(
        icon,
        color: palette.textPrimary.withValues(alpha: 0.7),
        size: size * 0.4,
      ),
    );
  }
}
