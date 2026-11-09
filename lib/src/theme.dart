import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Font sizes calibrated by measuring the reference app and this app on the same phone, so text
/// density matches it. Android's dp/sp already adapt to screen density, so these are not scaled
/// further by screen size.
abstract final class AppFontSize {
  static const tabTitle = 24.0;
  static const screenTitle = 17.0;
  static const hero = 28.0;
  static const largeTitle = 24.0;
  static const section = 20.0;
  static const emphasis = 18.0;
  static const listTitle = 16.0;
  static const listSubtitle = 13.0;
  static const body = 14.0;
  static const small = 13.0;
  static const caption = 12.0;
  static const badge = 12.0;
  static const navLabel = 10.0;
}

/// Everything a theme changes besides font sizes: colours, corner style and decorations.
/// Screens read it with `context.palette` instead of hard-coding colours, so switching the theme
/// restyles the whole app.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.chip,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.badge,
    required this.divider,
    required this.navBar,
    required this.snackBackground,
    required this.snackForeground,
    required this.coverColors,
    required this.likedGradient,
    this.outline,
    this.rounded = true,
    this.chamfered = false,
    this.panelHeaders = false,
    this.uppercaseTitles = false,
  });

  final Color background;

  /// App bars, drawer, banners.
  final Color surface;

  /// Cards, tiles, bottom sheets.
  final Color surfaceHigh;
  final Color chip;
  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;
  final Color badge;
  final Color divider;
  final Color navBar;
  final Color snackBackground;
  final Color snackForeground;

  /// Base colours of placeholder artwork and search category tiles.
  final List<Color> coverColors;

  /// "Polubione utwory" cover.
  final List<Color> likedGradient;

  /// Thin border drawn around chips, cards and tiles; none when null.
  final Color? outline;

  /// False gives square corners everywhere.
  final bool rounded;

  /// Cut corners (`ChamferedBorder`) on chips, cards, buttons and sheets instead of rounded or
  /// square ones; what's clipped with [radius] (covers) stays square.
  final bool chamfered;

  /// Section headings drawn as window title bars ("NAZWA ×") instead of plain bold text; with
  /// [chamfered], as a tab with a cut corner.
  final bool panelHeaders;

  /// Tab titles in capitals. Song, artist and playlist names keep their own spelling.
  final bool uppercaseTitles;

  BorderRadius radius(double value) =>
      BorderRadius.circular(rounded ? value : 0);

  BorderSide get outlineSide =>
      outline == null ? BorderSide.none : BorderSide(color: outline!);

  /// Shape for chips and pill buttons.
  OutlinedBorder get pillShape => chamfered
      ? ChamferedBorder(side: outlineSide, cut: 6)
      : rounded
      ? StadiumBorder(side: outlineSide)
      : RoundedRectangleBorder(side: outlineSide);

  /// Shape for cards, tiles and banners with the given corner radius.
  OutlinedBorder boxShape(double cornerRadius) => chamfered
      ? ChamferedBorder(
          side: outlineSide,
          cut: cornerRadius.clamp(6, 12),
          notch: accent,
        )
      : RoundedRectangleBorder(
          borderRadius: radius(cornerRadius),
          side: outlineSide,
        );

  /// Shape for round icon buttons (play, the playlist's play button).
  OutlinedBorder get buttonShape => chamfered
      ? const ChamferedBorder(cut: 12)
      : rounded
      ? const CircleBorder()
      : const RoundedRectangleBorder();

  /// Deterministic colour per title, so placeholders look varied but stay stable between rebuilds.
  Color colorForSeed(String seed) {
    final hash = seed.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return coverColors[hash % coverColors.length];
  }

  @override
  AppPalette copyWith() => this;

  // Themes differ in shape and font too, which can't be interpolated; switch in one step.
  @override
  AppPalette lerp(AppPalette? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// A box with its top-left and bottom-right corners cut off and, given a [notch] colour, a small
/// filled triangle in the top-right corner — the panels and buttons of cyberpunk HUD wallpapers.
class ChamferedBorder extends OutlinedBorder {
  const ChamferedBorder({super.side, this.cut = 8, this.notch});

  final double cut;
  final Color? notch;

  Path _path(Rect rect) {
    final c = math.min(cut, rect.shortestSide / 2);
    return Path()
      ..moveTo(rect.left + c, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right - c, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top + c)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
    }
    if (notch != null && rect.shortestSide >= 32) {
      final size = math.min(8.0, rect.shortestSide / 5);
      final corner = rect.topRight.translate(-3, 3);
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx - size, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + size)
          ..close(),
        Paint()..color = notch!,
      );
    }
  }

  @override
  ShapeBorder scale(double t) =>
      ChamferedBorder(side: side.scale(t), cut: cut * t, notch: notch);

  @override
  ChamferedBorder copyWith({BorderSide? side}) =>
      ChamferedBorder(side: side ?? this.side, cut: cut, notch: notch);

  @override
  bool operator ==(Object other) =>
      other is ChamferedBorder &&
      other.side == side &&
      other.cut == cut &&
      other.notch == notch;

  @override
  int get hashCode => Object.hash(side, cut, notch);
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

class AppThemeDef {
  const AppThemeDef(
    this.name,
    this.palette, {
    String? id,
    this.fontFamily,
    this.brightness = Brightness.dark,
  }) : id = id ?? name;

  /// What the choice of theme is saved as; unique within the light or the dark themes.
  final String id;

  /// Shown in "Ustawienia › Wygląd" (a light and a dark theme may share a name, e.g. both
  /// variants of Dummify).
  final String name;
  final AppPalette palette;

  /// Whether this is a light theme (offered under "Motyw jasny") or a dark one.
  final Brightness brightness;

  /// Null keeps the platform default (Roboto).
  final String? fontFamily;

  ThemePreview get preview => ThemePreview(
    background: palette.background,
    border: palette.outline ?? palette.divider,
    colors: [
      palette.accent,
      palette.textPrimary,
      palette.coverColors[0],
      palette.coverColors[1],
    ],
    rounded: palette.rounded,
  );
}

/// What a theme's small preview shows (`ThemeSwatch`), for themes on the phone and on GitHub.
class ThemePreview {
  const ThemePreview({
    required this.background,
    required this.border,
    required this.colors,
    required this.rounded,
  });

  final Color background;
  final Color border;
  final List<Color> colors;
  final bool rounded;
}

const dummifyTheme = AppThemeDef(
  'Dummify',
  AppPalette(
    background: Color(0xFF121212),
    surface: Color(0xFF1F1F1F),
    surfaceHigh: Color(0xFF2A2A2A),
    chip: Color(0xFF333333),
    accent: Color(0xFF1ED760),
    onAccent: Colors.black,
    textPrimary: Colors.white,
    textSecondary: Color(0xFFB3B3B3),
    badge: Color(0xFF3D91F4),
    divider: Colors.white12,
    navBar: Colors.black,
    snackBackground: Colors.white,
    snackForeground: Colors.black,
    coverColors: [
      Color(0xFFE8115B),
      Color(0xFF1E3264),
      Color(0xFF8D67AB),
      Color(0xFF006450),
      Color(0xFFBA5D07),
      Color(0xFF477D95),
      Color(0xFFAF2896),
      Color(0xFF503750),
      Color(0xFF148A08),
      Color(0xFFDC148C),
      Color(0xFF0D73EC),
      Color(0xFF8C1932),
    ],
    likedGradient: [Color(0xFF4A1BE0), Color(0xFF8FD6C7)],
  ),
);

/// Light counterpart of Dummify: white background, near-black text, a darker green so the
/// accent stays readable as text on white.
const dummifyLightTheme = AppThemeDef(
  'Dummify',
  AppPalette(
    background: Colors.white,
    surface: Color(0xFFF4F4F4),
    surfaceHigh: Color(0xFFECECEC),
    chip: Color(0xFFE4E4E4),
    accent: Color(0xFF14A04A),
    onAccent: Colors.white,
    textPrimary: Color(0xFF121212),
    textSecondary: Color(0xFF5E5E5E),
    badge: Color(0xFF1565C0),
    divider: Colors.black12,
    navBar: Color(0xFFF4F4F4),
    snackBackground: Color(0xFF121212),
    snackForeground: Colors.white,
    coverColors: [
      Color(0xFFE8115B),
      Color(0xFF1E3264),
      Color(0xFF8D67AB),
      Color(0xFF006450),
      Color(0xFFBA5D07),
      Color(0xFF477D95),
      Color(0xFFAF2896),
      Color(0xFF503750),
      Color(0xFF148A08),
      Color(0xFFDC148C),
      Color(0xFF0D73EC),
      Color(0xFF8C1932),
    ],
    likedGradient: [Color(0xFF4A1BE0), Color(0xFF8FD6C7)],
  ),
  brightness: Brightness.light,
);

/// Built into the app, so it always has a look; the others are downloaded (`ThemeController`).
const lightThemes = [dummifyLightTheme];

/// Built into the app, like [lightThemes].
const darkThemes = [dummifyTheme];

ThemeData buildAppTheme(AppThemeDef def) {
  final p = def.palette;
  final isDark = def.brightness == Brightness.dark;
  return ThemeData(
    brightness: def.brightness,
    fontFamily: def.fontFamily,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
    colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.accent,
          onSecondary: p.onAccent,
          surface: p.background,
          onSurface: p.textPrimary,
          onSurfaceVariant: p.textSecondary,
          outline: p.outline ?? p.divider,
        ),
    // Flutter's Android default (PredictiveBackPageTransitionsBuilder) lets a route inside a tab
    // navigator grab the predictive back gesture (Android 16+) whenever it's top of its own
    // navigator — even under the full player, a root bottom sheet or the open drawer — so Back
    // popped the hidden tab screen instead. Same look on push; Back stays with AppShell._onBack.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    iconTheme: IconThemeData(color: p.textPrimary),
    dividerTheme: DividerThemeData(color: p.divider),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.textPrimary,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: def.fontFamily,
        fontSize: AppFontSize.screenTitle,
        fontWeight: FontWeight.bold,
        color: p.textPrimary,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: p.textPrimary,
      titleTextStyle: TextStyle(
        fontFamily: def.fontFamily,
        fontSize: AppFontSize.listTitle,
        color: p.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: def.fontFamily,
        fontSize: AppFontSize.listSubtitle,
        color: p.textSecondary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.snackBackground,
      actionTextColor: p.snackForeground,
      contentTextStyle: TextStyle(
        fontFamily: def.fontFamily,
        color: p.snackForeground,
        fontSize: AppFontSize.body,
      ),
      shape: p.boxShape(4),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceHigh,
      dragHandleColor: p.textSecondary,
      showDragHandle: true,
      shape: p.chamfered
          ? ChamferedBorder(side: p.outlineSide, cut: 20)
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(p.rounded ? 28 : 0),
              ),
              side: p.outlineSide,
            ),
    ),
    dialogTheme: p.chamfered ? DialogThemeData(shape: p.boxShape(12)) : null,
    filledButtonTheme: p.chamfered
        ? FilledButtonThemeData(
            style: FilledButton.styleFrom(shape: p.pillShape),
          )
        : null,
    outlinedButtonTheme: p.chamfered
        ? OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(shape: p.pillShape),
          )
        : null,
    textButtonTheme: p.chamfered
        ? TextButtonThemeData(
            style: TextButton.styleFrom(shape: const ChamferedBorder(cut: 6)),
          )
        : null,
    elevatedButtonTheme: p.chamfered
        ? ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(shape: p.pillShape),
          )
        : null,
    drawerTheme: DrawerThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(side: p.outlineSide),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.onAccent
            : p.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? p.accent : p.chip,
      ),
    ),
  );
}
