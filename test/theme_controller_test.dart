import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/latin_names.dart';
import 'package:music_database_app/src/data/lyrics_transliteration.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'saved colours: newest first, no repeats, at most the limit, kept',
    () async {
      final themes = ThemeController();
      for (var i = 0; i < ThemeController.maxSavedColors + 2; i++) {
        await themes.saveColor(Color(0xFF000000 + i));
      }
      await themes.saveColor(const Color(0xFF000005));
      expect(themes.savedColors.first, const Color(0xFF000005));
      expect(themes.savedColors, hasLength(ThemeController.maxSavedColors));
      expect(
        themes.savedColors.where((c) => c == const Color(0xFF000005)),
        hasLength(1),
      );
      await themes.forgetColor(const Color(0xFF000005));

      final restarted = ThemeController();
      await restarted.load();
      expect(restarted.savedColors, themes.savedColors);
      expect(restarted.savedColors, isNot(contains(const Color(0xFF000005))));
    },
  );

  test(
    'the background colour is kept, and null goes back to automatic',
    () async {
      final themes = ThemeController();
      await themes.setMonochromeBackground(const Color(0xFF9BBC0F));
      var restarted = ThemeController();
      await restarted.load();
      expect(restarted.monochromeBackground, const Color(0xFF9BBC0F));

      await themes.setMonochromeBackground(null);
      restarted = ThemeController();
      await restarted.load();
      expect(restarted.monochromeBackground, isNull);
    },
  );

  test('Latin names: in brackets at first, the choice kept', () async {
    final themes = ThemeController();
    await themes.load();
    expect(themes.latinNames, LatinNames.inBrackets);
    await themes.setLatinNames(LatinNames.instead);
    final restarted = ThemeController();
    await restarted.load();
    expect(restarted.latinNames, LatinNames.instead);
  });

  test('Latin names switched off before the three ways stay off', () async {
    SharedPreferences.setMockInitialValues({'appearance.latin_names': false});
    final themes = ThemeController();
    await themes.load();
    expect(themes.latinNames, LatinNames.original);
  });

  test('lyrics transliteration: never and no method at first, kept', () async {
    final themes = ThemeController();
    await themes.load();
    expect(themes.lyricsTransliteration, LyricsTransliteration.never);
    expect(themes.transliterationMethod, TransliterationMethod.none);
    await themes.setLyricsTransliteration(LyricsTransliteration.onRequest);
    final restarted = ThemeController();
    await restarted.load();
    expect(restarted.lyricsTransliteration, LyricsTransliteration.onRequest);
  });

  test('a language left out of transliteration shows no Latin names', () async {
    final themes = ThemeController();
    await themes.load();
    await themes.setLatinNames(LatinNames.instead);
    await themes.setLanguageExcluded('Serbian', true);
    expect(themes.latinNamesFor('Serbian'), LatinNames.original);
    expect(themes.latinNamesFor('English / Serbian'), LatinNames.original);
    expect(themes.latinNamesFor('Russian'), LatinNames.instead);
    expect(themes.latinNamesFor(null), LatinNames.instead);
    expect(themes.transliteratesLyricsOf('Serbian'), isFalse);
    expect(themes.transliteratesLyricsOf('Russian'), isTrue);

    final restarted = ThemeController();
    await restarted.load();
    expect(restarted.excludedLanguages, {'Serbian'});
    await restarted.setLanguageExcluded('Serbian', false);
    expect(restarted.latinNamesFor('Serbian'), LatinNames.instead);
  });

  test('each filter keeps its own intensity', () async {
    final themes = ThemeController();
    await themes.setFilterStrength(CoverFilter.lain, 0.4);
    final restarted = ThemeController();
    await restarted.load();
    expect(restarted.strengthOf(CoverFilter.lain), 0.4);
    expect(restarted.strengthOf(CoverFilter.monochrome), 1);
  });
}
