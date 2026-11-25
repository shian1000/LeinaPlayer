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

  test(
    'lyrics transliteration: on request from the server at first, kept',
    () async {
      final themes = ThemeController();
      await themes.load();
      expect(themes.lyricsTransliteration, LyricsTransliteration.onRequest);
      expect(
        themes.transliterationMethods,
        TransliterationMethod.values.toSet(),
      );
      expect(themes.offersLyricsTransliteration('rus'), isTrue);
      await themes.setLyricsTransliteration(LyricsTransliteration.never);
      final restarted = ThemeController();
      await restarted.load();
      expect(restarted.lyricsTransliteration, LyricsTransliteration.never);
      expect(restarted.offersLyricsTransliteration('rus'), isFalse);
    },
  );

  test('no method ticked offers no lyrics transliteration, kept', () async {
    final themes = ThemeController();
    await themes.load();
    await themes.setTransliterationMethod(TransliterationMethod.server, false);
    expect(themes.offersLyricsTransliteration('rus'), isTrue);
    await themes.setTransliterationMethod(
      TransliterationMethod.onDevice,
      false,
    );
    expect(themes.offersLyricsTransliteration('rus'), isFalse);
    final restarted = ThemeController();
    await restarted.load();
    expect(restarted.transliterationMethods, isEmpty);
  });

  test('"Brak" picked before both could be ticked stays none', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.transliteration_method': 'none',
    });
    final themes = ThemeController();
    await themes.load();
    expect(themes.transliterationMethods, isEmpty);
  });

  test('a language left out of transliteration shows no Latin names', () async {
    final themes = ThemeController();
    await themes.load();
    await themes.setLatinNames(LatinNames.instead);
    await themes.setLanguageExcluded('srp', true);
    expect(themes.latinNamesFor('srp'), LatinNames.original);
    expect(themes.latinNamesFor('eng / srp'), LatinNames.original);
    expect(themes.latinNamesFor('rus'), LatinNames.instead);
    expect(themes.latinNamesFor(null), LatinNames.instead);
    expect(themes.offersLyricsTransliteration('srp'), isFalse);
    expect(themes.offersLyricsTransliteration('rus'), isTrue);

    final restarted = ThemeController();
    await restarted.load();
    expect(restarted.excludedLanguages, {'srp'});
    await restarted.setLanguageExcluded('srp', false);
    expect(restarted.latinNamesFor('srp'), LatinNames.instead);
  });

  test('languages left out by their old names become codes, kept', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.transliteration_excluded_languages': [
        'Attic Greek',
        'Serbian',
      ],
    });
    final themes = ThemeController();
    await themes.load();
    expect(themes.excludedLanguages, {'grc', 'srp'});
    expect(themes.latinNamesFor('Serbian'), LatinNames.original);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('appearance.transliteration_excluded_languages'),
      ['grc', 'srp'],
    );
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
