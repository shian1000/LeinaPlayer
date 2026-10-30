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
    this.fontFamily,
    this.brightness = Brightness.dark,
  });

  /// Shown in "Ustawienia › Wygląd" and used as the theme's id within its list (a light and a
  /// dark theme may share a name, e.g. both variants of Dummify).
  final String name;
  final AppPalette palette;

  /// Whether this is a light theme (offered under "Motyw jasny") or a dark one.
  final Brightness brightness;

  /// Null keeps the platform default (Roboto).
  final String? fontFamily;
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

/// Retro desktop/terminal look after "Serial Experiments Lain" fan desktops: near-black navy,
/// cyan phosphor accents, steel-blue window chrome, monospace text, square corners.
const lainTheme = AppThemeDef(
  'Lain',
  AppPalette(
    background: Color(0xFF05080F),
    surface: Color(0xFF0A1424),
    surfaceHigh: Color(0xFF0E1B30),
    chip: Color(0xFF0C1A2C),
    accent: Color(0xFF5CD6EB),
    onAccent: Color(0xFF02121A),
    textPrimary: Color(0xFFCDE6F0),
    textSecondary: Color(0xFF6E8BA6),
    badge: Color(0xFF8FB8FF),
    divider: Color(0xFF1C3550),
    navBar: Color(0xFF03060B),
    snackBackground: Color(0xFF0E2A40),
    snackForeground: Color(0xFF9BE8F5),
    coverColors: [
      Color(0xFF0E3A5A),
      Color(0xFF145E73),
      Color(0xFF1B6E8C),
      Color(0xFF0B2A4A),
      Color(0xFF2A4F7A),
      Color(0xFF12515E),
      Color(0xFF1F3B66),
      Color(0xFF0D4D5C),
    ],
    likedGradient: [Color(0xFF1E3F73), Color(0xFF5CD6EB)],
    outline: Color(0xFF2B5B7E),
    rounded: false,
    panelHeaders: true,
  ),
  // Android's built-in monospace face, so nothing has to be bundled.
  fontFamily: 'monospace',
);

/// After cyberpunk HUD phone wallpapers (user's Pins folder, red/cyan "cyberdeck" ones): a
/// near-black page with a red tint, red frames and subtitles, cyan accents, cut corners with a
/// notch, tab-like section headings and the narrow technical Rajdhani font (bundled, OFL).
const cyberpunkTheme = AppThemeDef(
  'Cyberpunk',
  AppPalette(
    background: Color(0xFF0E0A0D),
    surface: Color(0xFF170F13),
    surfaceHigh: Color(0xFF16191D),
    chip: Color(0xFF1C2226),
    accent: Color(0xFF5FE3E8),
    onAccent: Color(0xFF051416),
    textPrimary: Color(0xFFD8F4F5),
    textSecondary: Color(0xFFD65A50),
    badge: Color(0xFFE0524A),
    divider: Color(0xFF3A1D20),
    navBar: Color(0xFF0A0C0F),
    snackBackground: Color(0xFF0F2A2D),
    snackForeground: Color(0xFF8FF3F6),
    coverColors: [
      Color(0xFF7A2420),
      Color(0xFF16585C),
      Color(0xFF9E3A33),
      Color(0xFF0F3E42),
      Color(0xFF5A1A26),
      Color(0xFF1F6F73),
      Color(0xFF3B1418),
      Color(0xFF24474F),
    ],
    likedGradient: [Color(0xFF8C2A2A), Color(0xFF5FE3E8)],
    outline: Color(0xFFB8403A),
    rounded: false,
    chamfered: true,
    panelHeaders: true,
    uppercaseTitles: true,
  ),
  fontFamily: 'Rajdhani',
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

/// After the light Home of Juxtopposed's Spotify redesign: a soft grey page with lighter grey
/// cards and chips, near-black text and a deep green accent.
const redesignLightTheme = AppThemeDef(
  'Redesign',
  AppPalette(
    background: Color(0xFFF2F2F0),
    surface: Color(0xFFE9E9E6),
    surfaceHigh: Color(0xFFDFDFDB),
    chip: Color(0xFFE2E2DE),
    accent: Color(0xFF138A43),
    onAccent: Colors.white,
    textPrimary: Color(0xFF151515),
    textSecondary: Color(0xFF646462),
    badge: Color(0xFF2E5BBA),
    divider: Colors.black12,
    navBar: Color(0xFFE9E9E6),
    snackBackground: Color(0xFF1C1C1C),
    snackForeground: Colors.white,
    coverColors: [
      Color(0xFF5B6FD6),
      Color(0xFF2BB39B),
      Color(0xFFE2574C),
      Color(0xFFE5A53A),
      Color(0xFF8E6BC8),
      Color(0xFF3D8FD1),
      Color(0xFFD9578C),
      Color(0xFF4FA35A),
    ],
    likedGradient: [Color(0xFF5B6FD6), Color(0xFF8FD6C7)],
  ),
  brightness: Brightness.light,
);

/// Themes offered under "Motyw jasny".
const lightThemes = [dummifyLightTheme, redesignLightTheme];

/// Themes offered under "Motyw ciemny".
const darkThemes = [dummifyTheme, lainTheme, cyberpunkTheme];

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
