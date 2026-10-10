import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// "Ustawienia › Wygląd": the chosen light and dark theme and which of the two is shown.
/// Saved in `shared_preferences`, so the choice survives restarts.
class ThemeController extends ChangeNotifier {
  static const _lightKey = 'appearance.light_theme';
  static const _darkKey = 'appearance.dark_theme';
  static const _darkModeKey = 'appearance.dark_mode';
  static const _followSystemKey = 'appearance.follow_system';

  AppThemeDef _light = lightThemes.first;
  AppThemeDef _dark = darkThemes.first;
  bool _darkMode = true;
  bool _followSystem = false;

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

  static ThemeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
}
