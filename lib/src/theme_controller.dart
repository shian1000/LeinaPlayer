import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/text_normalizer.dart';
import 'data/theme_repository.dart';
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
  ThemeController({
    ThemeRepository? repository,
    Future<Directory> Function()? storageRoot,
  }) : repository = repository ?? ThemeRepository(),
       _storageRoot = storageRoot ?? getApplicationSupportDirectory;

  final ThemeRepository repository;
  final Future<Directory> Function() _storageRoot;

  static const _downloadedKey = 'appearance.downloaded_themes';

  /// Before themes could be downloaded this was the default, saved by nobody.
  static const _oldDefaultDark = 'Lain';
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
  AppThemeDef _dark = dummifyTheme;
  List<ThemeFile> _downloaded = const [];
  final _loadedFonts = <String>{};
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

  /// The built-in light themes and the downloaded ones, offered under "Motyw jasny".
  List<AppThemeDef> get availableLight => _available(Brightness.light);

  /// The built-in dark themes and the downloaded ones, offered under "Motyw ciemny".
  List<AppThemeDef> get availableDark => _available(Brightness.dark);

  List<AppThemeDef> _available(Brightness brightness) => [
    ...brightness == Brightness.dark ? darkThemes : lightThemes,
    for (final file in _downloaded)
      if (file.def.brightness == brightness) file.def,
  ];

  /// The version on the phone of a downloaded theme; `null` when it isn't downloaded.
  int? downloadedVersion(String id) => _fileOf(id)?.version;

  ThemeFile? _fileOf(String id) =>
      _downloaded.where((f) => f.id == id).firstOrNull;

  /// "Przełącz na tryb ciemny" — ignored while [followSystem] is on.
  bool get darkMode => _darkMode;

  /// "Systemowe przełączanie trybu ciemnego".
  bool get followSystem => _followSystem;

  ThemeMode get themeMode => _followSystem
      ? ThemeMode.system
      : (_darkMode ? ThemeMode.dark : ThemeMode.light);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _downloaded = _sorted([
      for (final raw in prefs.getStringList(_downloadedKey) ?? const <String>[])
        ?_parse(raw),
    ]);
    // No saved theme on a phone that already has settings: it was on the old default. A new
    // install saves its own at once, so later starts can tell the two apart.
    if (!prefs.containsKey(_darkKey)) {
      await prefs.setString(
        _darkKey,
        prefs.getKeys().isEmpty ? _dark.id : _oldDefaultDark,
      );
    }
    final lightId = prefs.getString(_lightKey);
    final darkId = prefs.getString(_darkKey);
    _light = _byId(availableLight, lightId) ?? _light;
    _dark = _byId(availableDark, darkId) ?? _dark;
    await Future.wait([_loadFonts(_light), _loadFonts(_dark)]);
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
    // A theme chosen when it was still part of the app: Dummify shows until it's here.
    unawaited(
      _restoreMissing({
        if (lightId != null && _byId(availableLight, lightId) == null) lightId,
        if (darkId != null && _byId(availableDark, darkId) == null) darkId,
      }),
    );
  }

  static ThemeFile? _parse(String raw) {
    try {
      return ThemeFile.parse(raw);
    } catch (e) {
      debugPrint('Reading a downloaded theme failed: $e');
      return null;
    }
  }

  static List<ThemeFile> _sorted(List<ThemeFile> files) => List.unmodifiable(
    files..sort((a, b) => compareNames(a.def.name, b.def.name)),
  );

  static AppThemeDef? _byId(List<AppThemeDef> themes, String? id) =>
      themes.where((t) => t.id == id).firstOrNull;

  Future<void> _restoreMissing(Set<String> ids) async {
    for (final id in ids) {
      try {
        final theme = await install(id);
        final dark = theme.brightness == Brightness.dark;
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(dark ? _darkKey : _lightKey) != id) continue;
        await (dark ? setDark(theme) : setLight(theme));
      } catch (e) {
        debugPrint('Restoring theme $id failed: $e');
      }
    }
  }

  Future<File> _themeFile(String id, String name) async =>
      File('${(await _storageRoot()).path}/theme_fonts/${id}__$name');

  /// Downloads a theme from GitHub, or a newer version of it, without choosing it.
  Future<AppThemeDef> install(String id) async {
    final fetched = await repository.fetchTheme(id);
    for (final MapEntry(key: name, value: bytes) in fetched.files.entries) {
      final file = await _themeFile(id, name);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    final theme = fetched.theme;
    _downloaded = _sorted([..._downloaded.where((f) => f.id != id), theme]);
    await _saveDownloaded();
    if (_dark.id == id) _dark = theme.def;
    if (_light.id == id) _light = theme.def;
    notifyListeners();
    return theme.def;
  }

  /// Takes a downloaded theme off the phone; if it was in use, Dummify takes its place.
  Future<void> remove(String id) async {
    final theme = _fileOf(id);
    if (theme == null) return;
    _downloaded = List.unmodifiable(_downloaded.where((f) => f.id != id));
    await _saveDownloaded();
    if (_dark.id == id) await setDark(dummifyTheme);
    if (_light.id == id) await setLight(dummifyLightTheme);
    notifyListeners();
    for (final name in [...theme.fonts, ?theme.license]) {
      try {
        await (await _themeFile(id, name)).delete();
      } catch (e) {
        debugPrint('Deleting a theme file failed: $e');
      }
    }
  }

  Future<void> _saveDownloaded() async =>
      (await SharedPreferences.getInstance()).setStringList(_downloadedKey, [
        for (final f in _downloaded) f.raw,
      ]);

  /// Without its files (or if they're damaged) the theme just shows in the system font.
  Future<void> _loadFonts(AppThemeDef def) async {
    final theme = _fileOf(def.id);
    final family = def.fontFamily;
    if (theme == null || family == null || theme.fonts.isEmpty) return;
    if (!_loadedFonts.add(family)) return;
    try {
      final loader = FontLoader(family);
      for (final name in theme.fonts) {
        final bytes = await (await _themeFile(theme.id, name)).readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    } catch (e) {
      _loadedFonts.remove(family);
      debugPrint('Loading the fonts of theme ${def.id} failed: $e');
    }
  }

  /// The licences of downloaded themes' fonts, for Licencje bibliotek.
  Stream<LicenseEntry> licenses() async* {
    for (final theme in _downloaded) {
      final license = theme.license;
      if (license == null) continue;
      try {
        yield LicenseEntryWithLineBreaks([
          theme.def.fontFamily ?? theme.def.name,
        ], await (await _themeFile(theme.id, license)).readAsString());
      } catch (e) {
        debugPrint('Reading the licence of theme ${theme.id} failed: $e');
      }
    }
  }

  Future<void> setLight(AppThemeDef theme) async {
    await _loadFonts(theme);
    _light = theme;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _lightKey,
      theme.id,
    );
  }

  Future<void> setDark(AppThemeDef theme) async {
    await _loadFonts(theme);
    _dark = theme;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_darkKey, theme.id);
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
