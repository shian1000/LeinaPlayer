import 'package:flutter/material.dart';

import '../theme.dart';

/// Small preview of a theme: background with accent, text and two artwork colours.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch(this.preview, {super.key});

  final ThemePreview preview;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(preview.rounded ? 6 : 0);
    return Container(
      width: 56,
      height: 40,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: preview.background,
        border: Border.all(color: preview.border),
        borderRadius: corner,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final color in preview.colors)
            Container(
              width: 9,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(preview.rounded ? 2 : 0),
              ),
            ),
        ],
      ),
    );
  }
}
