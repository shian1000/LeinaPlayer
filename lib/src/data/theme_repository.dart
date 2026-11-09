import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// The newest file format this version understands; anything newer is left out of the browser.
const supportedThemeFormat = 1;

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _safeFile = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');
final _hexColor = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

Color _color(Object? value, String field) {
  if (value is! String || !_hexColor.hasMatch(value)) {
    throw FormatException('Bad colour in "$field"', value);
  }
  final hex = value.substring(1);
  return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
}

List<Color> _colors(Object? value, String field, {required int atLeast}) {
  if (value is! List || value.length < atLeast) {
    throw FormatException('Too few colours in "$field"', value);
  }
  return [for (final c in value) _color(c, field)];
}

String _id(Object? value) {
  if (value is! String || !_safeId.hasMatch(value)) {
    throw FormatException('Bad theme id', value);
  }
  return value;
}

Brightness _brightness(Object? value) => switch (value) {
  'dark' => Brightness.dark,
  'light' => Brightness.light,
  _ => throw FormatException('Bad brightness', value),
};

/// A theme as the browser lists it, from `index.json`.
class ThemeListing {
  const ThemeListing({
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.brightness,
    required this.preview,
  });

  factory ThemeListing.fromJson(Map<String, Object?> json) {
    final preview = json['preview'] as Map<String, Object?>;
    final colors = _colors(preview['colors'], 'colors', atLeast: 4);
    return ThemeListing(
      id: _id(json['id']),
      name: json['name'] as String,
      author: json['author'] as String? ?? '',
      version: json['version'] as int,
      brightness: _brightness(json['brightness']),
      preview: ThemePreview(
        background: _color(preview['background'], 'background'),
        border: _color(preview['border'], 'border'),
        colors: colors.take(4).toList(),
        rounded: preview['rounded'] as bool? ?? true,
      ),
    );
  }

  final String id;
  final String name;
  final String author;
  final int version;
  final Brightness brightness;
  final ThemePreview preview;
}

/// A downloaded theme: a `theme.json`, kept on the phone in that same form. Only data, so a
/// theme can pick among the looks [AppPalette] has but can't run anything.
class ThemeFile {
  ThemeFile._({
    required this.raw,
    required this.version,
    required this.def,
    required this.fonts,
    required this.license,
  });

  /// Throws a [FormatException] (or a cast's [TypeError]) when [raw] isn't a theme.
  factory ThemeFile.parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    final format = json['format'] as int;
    if (format > supportedThemeFormat) {
      throw FormatException('Theme format $format is too new');
    }
    final p = json['palette'] as Map<String, Object?>;
    Color c(String field) => _color(p[field], field);
    final outline = p['outline'];
    final fonts = [...(json['fonts'] as List? ?? const []).cast<String>()];
    final license = json['license'] as String?;
    for (final file in [...fonts, ?license]) {
      if (!_safeFile.hasMatch(file)) {
        throw FormatException('Bad file name', file);
      }
    }
    return ThemeFile._(
      raw: raw,
      version: json['version'] as int,
      fonts: fonts,
      license: license,
      def: AppThemeDef(
        json['name'] as String,
        AppPalette(
          background: c('background'),
          surface: c('surface'),
          surfaceHigh: c('surfaceHigh'),
          chip: c('chip'),
          accent: c('accent'),
          onAccent: c('onAccent'),
          textPrimary: c('textPrimary'),
          textSecondary: c('textSecondary'),
          badge: c('badge'),
          divider: c('divider'),
          navBar: c('navBar'),
          snackBackground: c('snackBackground'),
          snackForeground: c('snackForeground'),
          coverColors: _colors(p['coverColors'], 'coverColors', atLeast: 2),
          likedGradient: _colors(
            p['likedGradient'],
            'likedGradient',
            atLeast: 2,
          ),
          outline: outline == null ? null : _color(outline, 'outline'),
          rounded: p['rounded'] as bool? ?? true,
          chamfered: p['chamfered'] as bool? ?? false,
          panelHeaders: p['panelHeaders'] as bool? ?? false,
          uppercaseTitles: p['uppercaseTitles'] as bool? ?? false,
        ),
        id: _id(json['id']),
        fontFamily: json['fontFamily'] as String?,
        brightness: _brightness(json['brightness']),
      ),
    );
  }

  final String raw;
  final int version;
  final AppThemeDef def;

  /// Font files next to `theme.json`; [AppThemeDef.fontFamily] names them together.
  final List<String> fonts;

  /// The fonts' licence, a text file next to `theme.json`, for Licencje bibliotek.
  final String? license;

  String get id => def.id;
}

/// The themes on GitHub (`shian1000/LeinaThemes`): `index.json` lists them and each has a
/// folder `themes/<id>/` with its `theme.json` and fonts.
class ThemeRepository {
  ThemeRepository({
    Uri? base,
    Future<Uint8List> Function(Uri url, int limit)? download,
  }) : _base =
           base ??
           Uri.parse(
             'https://raw.githubusercontent.com/shian1000/LeinaThemes/main/',
           ),
       _download = download ?? _get;

  static const _jsonLimit = 1 << 20;
  static const _fileLimit = 8 << 20;
  static const _timeout = Duration(seconds: 30);

  final Uri _base;
  final Future<Uint8List> Function(Uri url, int limit) _download;

  static Future<Uint8List> _get(Uri url, int limit) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final response = await (await client.getUrl(url)).close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        bytes.add(chunk);
        if (bytes.length > limit) {
          throw HttpException('File too large', uri: url);
        }
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  /// A listing this version can't read is left out, so one bad entry doesn't hide the rest.
  Future<List<ThemeListing>> fetchIndex() async {
    final bytes = await _download(_base.resolve('index.json'), _jsonLimit);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return [for (final entry in json['themes'] as List) ?_listing(entry)];
  }

  static ThemeListing? _listing(Object? entry) {
    try {
      final json = entry as Map<String, Object?>;
      if (json['format'] as int > supportedThemeFormat) return null;
      return ThemeListing.fromJson(json);
    } catch (e) {
      debugPrint('Skipping a theme in the index: $e');
      return null;
    }
  }

  /// The theme with its fonts and licence, by file name; all or nothing.
  Future<({ThemeFile theme, Map<String, Uint8List> files})> fetchTheme(
    String id,
  ) async {
    final folder = _base.resolve('themes/${_id(id)}/');
    final raw = utf8.decode(
      await _download(folder.resolve('theme.json'), _jsonLimit),
    );
    final theme = ThemeFile.parse(raw);
    return (
      theme: theme,
      files: {
        for (final file in [...theme.fonts, ?theme.license])
          file: await _download(folder.resolve(file), _fileLimit),
      },
    );
  }
}
