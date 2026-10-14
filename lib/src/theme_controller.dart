import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// "Ustawienia › Wygląd › Filtry do albumów": a look laid over every album cover.
enum CoverFilter {
  none('Brak'),

  /// Blue-green, grainy, with scan lines — like Serial Experiments Lain (1996).
  lain('Lain'),

  /// One colour on black: shades come from how many dots are lit, like old monochrome screens.
  monochrome('Monochromatic');

  const CoverFilter(this.label);

  final String label;
}

/// "Ustawienia › Wygląd": the chosen light and dark theme and which of the two is shown.
/// Saved in `shared_preferences`, so the choice survives restarts.
class ThemeController extends ChangeNotifier {
  static const _lightKey = 'appearance.light_theme';
  static const _darkKey = 'appearance.dark_theme';
  static const _darkModeKey = 'appearance.dark_mode';
  static const _followSystemKey = 'appearance.follow_system';
  static const _coverFilterKey = 'appearance.cover_filter';
  static const _monochromeColorKey = 'appearance.monochrome_color';
  static const _monochromeBackgroundKey = 'appearance.monochrome_background';
  static const _savedColorsKey = 'appearance.saved_colors';
  static const _latinNamesKey = 'appearance.latin_names';
  static const maxSavedColors = 8;
  static String _strengthKey(CoverFilter f) =>
      'appearance.cover_filter_strength.${f.name}';

  /// Phosphor green.
  static const defaultMonochromeColor = Color(0xFFC6F27B);

  AppThemeDef _light = lightThemes.first;
  AppThemeDef _dark = lainTheme;
  bool _darkMode = true;
  bool _followSystem = false;
  CoverFilter _coverFilter = CoverFilter.none;
  Color _monochromeColor = defaultMonochromeColor;
  Map<CoverFilter, double> _strengths = const {};
  Color? _monochromeBackground;
  List<Color> _savedColors = const [];
  bool _latinNames = true;

  /// "Nazwy w alfabecie łacińskim": names in another alphabet followed by their Latin form
  /// from music.db, "Кино (Kino)" (`latin_names.dart`).
  bool get latinNames => _latinNames;

  CoverFilter get coverFilter => _coverFilter;

  /// The one colour of [CoverFilter.monochrome].
  Color get monochromeColor => _monochromeColor;

  /// The colour of unlit dots in [CoverFilter.monochrome]; `null`: the dot colour, dimmed.
  Color? get monochromeBackground => _monochromeBackground;

  /// Colours the user picked themselves, newest first (at most [maxSavedColors]).
  List<Color> get savedColors => _savedColors;

  /// How strongly [filter] is applied, 0–1 (the cover mixed with its filtered look); each filter
  /// keeps its own.
  double strengthOf(CoverFilter filter) => _strengths[filter] ?? 1;

  /// [strengthOf] the chosen filter.
  double get coverFilterStrength => strengthOf(_coverFilter);

  AppThemeDef get light => _light;
  AppThemeDef get dark => _dark;

  /// "Przełącz na tryb ciemny" — ignored while [followSystem] is on.
  bool get darkMode => _darkMode;

  /// "Systemowe przełączanie trybu ciemnego".
  bool get followSystem => _followSystem;

  ThemeMode get themeMode => _followSystem
      ? ThemeMode.system
      : (_darkMode ? ThemeMode.dark : ThemeMode.light);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _light = _byName(lightThemes, prefs.getString(_lightKey)) ?? _light;
    _dark = _byName(darkThemes, prefs.getString(_darkKey)) ?? _dark;
    _darkMode = prefs.getBool(_darkModeKey) ?? _darkMode;
    _followSystem = prefs.getBool(_followSystemKey) ?? _followSystem;
    _latinNames = prefs.getBool(_latinNamesKey) ?? _latinNames;
    _coverFilter =
        CoverFilter.values
            .where((f) => f.name == prefs.getString(_coverFilterKey))
            .firstOrNull ??
        _coverFilter;
    final color = prefs.getInt(_monochromeColorKey);
    if (color != null) _monochromeColor = Color(color);
    final background = prefs.getInt(_monochromeBackgroundKey);
    _monochromeBackground = background == null ? null : Color(background);
    _savedColors = List.unmodifiable([
      for (final c in prefs.getStringList(_savedColorsKey) ?? const <String>[])
        if (int.tryParse(c) case final v?) Color(v),
    ]);
    _strengths = {
      for (final f in CoverFilter.values) f: ?prefs.getDouble(_strengthKey(f)),
    };
    notifyListeners();
  }

  static AppThemeDef? _byName(List<AppThemeDef> themes, String? name) =>
      themes.where((t) => t.name == name).firstOrNull;

  Future<void> setLight(AppThemeDef theme) async {
    _light = theme;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _lightKey,
      theme.name,
    );
  }

  Future<void> setDark(AppThemeDef theme) async {
    _dark = theme;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _darkKey,
      theme.name,
    );
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_darkModeKey, value);
  }

  Future<void> setCoverFilter(CoverFilter filter) async {
    _coverFilter = filter;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _coverFilterKey,
      filter.name,
    );
  }

  Future<void> setMonochromeColor(Color color) async {
    _monochromeColor = color.withValues(alpha: 1);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(
      _monochromeColorKey,
      _monochromeColor.toARGB32(),
    );
  }

  /// `null` goes back to the automatic background.
  Future<void> setMonochromeBackground(Color? color) async {
    _monochromeBackground = color?.withValues(alpha: 1);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_monochromeBackground == null) {
      await prefs.remove(_monochromeBackgroundKey);
    } else {
      await prefs.setInt(
        _monochromeBackgroundKey,
        _monochromeBackground!.toARGB32(),
      );
    }
  }

  /// Puts [color] first among [savedColors] (the oldest drops off past the limit).
  Future<void> saveColor(Color color) => _setSavedColors(
    [
      color.withValues(alpha: 1),
      ..._savedColors.where((c) => c.toARGB32() != color.toARGB32()),
    ].take(maxSavedColors).toList(),
  );

  Future<void> forgetColor(Color color) => _setSavedColors([
    for (final c in _savedColors)
      if (c.toARGB32() != color.toARGB32()) c,
  ]);

  Future<void> _setSavedColors(List<Color> colors) async {
    _savedColors = List.unmodifiable(colors);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _savedColorsKey,
      [for (final c in colors) '${c.toARGB32()}'],
    );
  }

  Future<void> setFilterStrength(CoverFilter filter, double strength) async {
    final value = strength.clamp(0.0, 1.0);
    _strengths = {..._strengths, filter: value};
    notifyListeners();
    await (await SharedPreferences.getInstance()).setDouble(
      _strengthKey(filter),
      value,
    );
  }

  Future<void> setLatinNames(bool value) async {
    _latinNames = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _latinNamesKey,
      value,
    );
  }

  Future<void> setFollowSystem(bool value) async {
    _followSystem = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _followSystemKey,
      value,
    );
  }
}

/// Makes the [ThemeController] reachable from any screen (e.g. "Ustawienia › Wygląd").
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController super.notifier,
    required super.child,
  });

  static ThemeController of(BuildContext context) => maybeOf(context)!;

  /// `null` where no scope is set up (widget tests).
  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}
