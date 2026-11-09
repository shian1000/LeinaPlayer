import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/theme_repository.dart';
import 'package:music_database_app/src/screens/theme_browser_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/waiting.dart';

const _c = '#102030';

String _themeJson({
  String id = 'Neon',
  int version = 1,
  int format = 1,
  String brightness = 'dark',
  Map<String, Object?> palette = const {},
}) => jsonEncode({
  'format': format,
  'id': id,
  'name': id,
  'version': version,
  'brightness': brightness,
  'palette': {
    for (final f in const [
      'background',
      'surface',
      'surfaceHigh',
      'chip',
      'accent',
      'onAccent',
      'textPrimary',
      'textSecondary',
      'badge',
      'divider',
      'navBar',
      'snackBackground',
      'snackForeground',
    ])
      f: _c,
    'coverColors': [_c, _c],
    'likedGradient': [_c, _c],
    'chamfered': true,
    ...palette,
  },
});

Map<String, Object?> _listing(String id, {int format = 1}) => {
  'format': format,
  'id': id,
  'name': id,
  'author': 'ktoś',
  'version': 2,
  'brightness': 'dark',
  'preview': {
    'background': _c,
    'border': _c,
    'colors': [_c, _c, _c, _c],
    'rounded': false,
  },
};

ThemeRepository _repository(Map<String, String> files, {List<Uri>? asked}) =>
    ThemeRepository(
      base: Uri.parse('https://themes.test/'),
      download: (url, limit) async {
        asked?.add(url);
        final body = files[url.path];
        if (body == null) throw const HttpException('HTTP 404');
        return Uint8List.fromList(utf8.encode(body));
      },
    );

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('themes_test');
  });
  tearDown(() => root.delete(recursive: true));

  ThemeController controller(ThemeRepository repository) =>
      ThemeController(repository: repository, storageRoot: () async => root);

  test('a theme file gives the palette it describes', () {
    final theme = ThemeFile.parse(
      _themeJson(palette: {'accent': '#80FF0000', 'outline': '#00FF00'}),
    );
    expect(theme.def.id, 'Neon');
    expect(theme.def.palette.accent, const Color(0x80FF0000));
    expect(theme.def.palette.outline, const Color(0xFF00FF00));
    expect(theme.def.palette.chamfered, isTrue);
    expect(theme.def.palette.rounded, isTrue);
  });

  test('bad theme files are refused', () {
    expect(
      () => ThemeFile.parse(_themeJson(palette: {'accent': 'red'})),
      throwsFormatException,
    );
    expect(
      () => ThemeFile.parse(_themeJson(format: 99)),
      throwsFormatException,
    );
    expect(
      () => ThemeFile.parse(_themeJson(id: '../x')),
      throwsFormatException,
    );
    final escaping = jsonDecode(_themeJson()) as Map<String, Object?>;
    escaping['fonts'] = ['../../evil.ttf'];
    expect(() => ThemeFile.parse(jsonEncode(escaping)), throwsFormatException);
  });

  test('the index leaves out what this version cannot read', () async {
    final listings = await _repository({
      '/index.json': jsonEncode({
        'themes': [
          _listing('Dobry'),
          _listing('Nowszy', format: 99),
          {'id': 'Zepsuty'},
        ],
      }),
    }).fetchIndex();
    expect([for (final l in listings) l.id], ['Dobry']);
  });

  test('a downloaded theme is offered, remembered and removable', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.dark_theme': 'Dummify',
    });
    final repository = _repository({'/themes/Neon/theme.json': _themeJson()});
    final themes = controller(repository);
    await themes.load();
    final neon = await themes.install('Neon');
    expect(themes.availableDark.last.id, 'Neon');
    expect(themes.dark, same(dummifyTheme));
    await themes.setDark(neon);

    final later = controller(repository);
    await later.load();
    expect(later.dark.id, 'Neon');
    expect(later.downloadedVersion('Neon'), 1);

    await later.remove('Neon');
    expect(later.dark, same(dummifyTheme));
    expect(later.downloadedVersion('Neon'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appearance.dark_theme'), 'Dummify');
  });

  test(
    'a theme picked before downloads existed comes back by itself',
    () async {
      SharedPreferences.setMockInitialValues({'appearance.dark_theme': 'Lain'});
      final themes = controller(
        _repository({'/themes/Lain/theme.json': _themeJson(id: 'Lain')}),
      );
      await themes.load();
      await waitUntil(() => themes.dark.id == 'Lain');
      expect(themes.downloadedVersion('Lain'), 1);
    },
  );

  test('a phone that stayed on the old default gets Lain back', () async {
    SharedPreferences.setMockInitialValues({'appearance.dark_mode': true});
    final asked = <Uri>[];
    final themes = controller(
      _repository({
        '/themes/Lain/theme.json': _themeJson(id: 'Lain'),
      }, asked: asked),
    );
    await themes.load();
    await waitUntil(() => themes.dark.id == 'Lain');
    expect(asked, isNotEmpty);
  });

  test('a new install connects to nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final asked = <Uri>[];
    final themes = controller(_repository(const {}, asked: asked));
    await themes.load();
    expect(themes.dark, same(dummifyTheme));
    expect(asked, isEmpty);
  });

  test('with no connection Dummify stays and the choice is kept', () async {
    SharedPreferences.setMockInitialValues({'appearance.dark_theme': 'Lain'});
    final themes = controller(_repository(const {}));
    await themes.load();
    await pumpEventQueue();
    expect(themes.dark, same(dummifyTheme));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appearance.dark_theme'), 'Lain');
  });

  test('fonts and the licence are saved beside the theme', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.dark_theme': 'Dummify',
    });
    final raw = jsonDecode(_themeJson()) as Map<String, Object?>;
    raw['license'] = 'OFL.txt';
    final themes = controller(
      _repository({
        '/themes/Neon/theme.json': jsonEncode(raw),
        '/themes/Neon/OFL.txt': 'licencja',
      }),
    );
    await themes.load();
    await themes.install('Neon');
    final entries = await themes.licenses().toList();
    expect(entries.single.packages, ['Neon']);
    await themes.remove('Neon');
    expect(
      File('${root.path}/theme_fonts/Neon__OFL.txt').existsSync(),
      isFalse,
    );
  });

  testWidgets('the browser lists themes and downloads one', (tester) async {
    SharedPreferences.setMockInitialValues({
      'appearance.dark_theme': 'Dummify',
    });
    final themes = ThemeController(
      repository: _repository({
        '/index.json': jsonEncode({
          'themes': [_listing('Neon')],
        }),
        '/themes/Neon/theme.json': _themeJson(),
      }),
      storageRoot: () async => root,
    );
    await tester.runAsync(themes.load);
    await tester.pumpWidget(
      ThemeScope(
        notifier: themes,
        child: MaterialApp(
          theme: buildAppTheme(dummifyTheme),
          home: const ThemeBrowserScreen(),
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('Neon').evaluate().isNotEmpty);
    expect(find.text('Ciemny · ktoś'), findsOneWidget);

    await tester.tap(find.byTooltip('Pobierz'));
    await pumpUntil(tester, () => find.byTooltip('Usuń').evaluate().isNotEmpty);
    expect(themes.downloadedVersion('Neon'), 1);
    expect(find.byTooltip('Aktualizuj'), findsOneWidget);
    expect(find.text('Pobrano motyw Neon'), findsOneWidget);
  });
}
