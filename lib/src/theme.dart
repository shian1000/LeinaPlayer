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
    this.panelHeaders = false,
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

  /// Section headings drawn as window title bars ("NAZWA ×") instead of plain bold text.
  final bool panelHeaders;

  BorderRadius radius(double value) =>
      BorderRadius.circular(rounded ? value : 0);

  BorderSide get outlineSide =>
      outline == null ? BorderSide.none : BorderSide(color: outline!);

  /// Shape for chips and pill buttons.
  OutlinedBorder get pillShape => rounded
      ? StadiumBorder(side: outlineSide)
      : RoundedRectangleBorder(side: outlineSide);

  /// Shape for cards, tiles and banners with the given corner radius.
  RoundedRectangleBorder boxShape(double cornerRadius) =>
      RoundedRectangleBorder(
        borderRadius: radius(cornerRadius),
        side: outlineSide,
      );

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

/// Themes offered under "Motyw jasny".
const lightThemes = [dummifyLightTheme];

/// Themes offered under "Motyw ciemny".
const darkThemes = [dummifyTheme, lainTheme];

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(p.rounded ? 28 : 0),
        ),
        side: p.outlineSide,
      ),
    ),
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
