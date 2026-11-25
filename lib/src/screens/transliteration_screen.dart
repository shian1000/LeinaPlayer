import 'package:flutter/material.dart';

import '../data/latin_names.dart';
import '../data/lyrics_transliteration.dart';
import '../data/song_catalog.dart';
import '../l10n.dart';
import '../theme.dart';
import '../theme_controller.dart';
import '../widgets/common.dart';

/// "Ustawienia › Wygląd › Transliteracja": names in another alphabet with their Latin form,
/// lyrics in Latin letters, and the languages left out of both.
class TransliterationScreen extends StatelessWidget {
  const TransliterationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themes = ThemeScope.of(context);
    final excluded = themes.excludedLanguages;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.transliterationTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          SectionTitle(l10n.appearanceLatinNames),
          RadioGroup<LatinNames>(
            groupValue: themes.latinNames,
            onChanged: (value) {
              if (value != null) themes.setLatinNames(value);
            },
            child: Column(
              children: [
                for (final (value, title, example) in [
                  (
                    LatinNames.original,
                    l10n.appearanceLatinNamesOriginal,
                    l10n.appearanceLatinNamesOriginalExample,
                  ),
                  (
                    LatinNames.inBrackets,
                    l10n.appearanceLatinNamesInBrackets,
                    l10n.appearanceLatinNamesInBracketsExample,
                  ),
                  (
                    LatinNames.instead,
                    l10n.appearanceLatinNamesInstead,
                    l10n.appearanceLatinNamesInsteadExample,
                  ),
                ])
                  RadioListTile<LatinNames>(
                    value: value,
                    title: Text(title),
                    subtitle: Text(example),
                  ),
              ],
            ),
          ),
          _Note(l10n.appearanceLatinNamesNote),
          SectionTitle(l10n.appearanceLyricsTransliteration),
          RadioGroup<LyricsTransliteration>(
            groupValue: themes.lyricsTransliteration,
            onChanged: (value) {
              if (value != null) themes.setLyricsTransliteration(value);
            },
            child: Column(
              children: [
                RadioListTile(
                  value: LyricsTransliteration.never,
                  title: Text(l10n.appearanceLyricsTransliterationNever),
                ),
                RadioListTile(
                  value: LyricsTransliteration.onRequest,
                  title: Text(l10n.appearanceLyricsTransliterationOnRequest),
                  subtitle: Text(
                    l10n.appearanceLyricsTransliterationOnRequestSubtitle,
                  ),
                ),
                RadioListTile(
                  value: LyricsTransliteration.always,
                  title: Text(l10n.appearanceLyricsTransliterationAlways),
                ),
              ],
            ),
          ),
          SectionTitle(l10n.appearanceTransliterationMethod),
          RadioGroup<TransliterationMethod>(
            groupValue: themes.transliterationMethod,
            onChanged: (value) {
              if (value == null) return;
              if (!value.works) return showWorkInProgress(context);
              themes.setTransliterationMethod(value);
            },
            child: Column(
              children: [
                RadioListTile(
                  value: TransliterationMethod.none,
                  title: Text(l10n.appearanceTransliterationMethodNone),
                ),
                RadioListTile(
                  value: TransliterationMethod.server,
                  title: Text(l10n.appearanceTransliterationMethodServer),
                  subtitle: Text(
                    l10n.appearanceTransliterationMethodServerSubtitle,
                  ),
                ),
                RadioListTile(
                  value: TransliterationMethod.onDevice,
                  title: Text(l10n.appearanceTransliterationMethodOnDevice),
                  subtitle: Text(
                    l10n.appearanceTransliterationMethodOnDeviceSubtitle,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(l10n.transliterationExcludedLanguages),
            subtitle: Text(
              excluded.isEmpty
                  ? l10n.transliterationExcludedLanguagesNone
                  : (excluded.toList()..sort()).join(', '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _ExcludedLanguagesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: Text(
      text,
      style: TextStyle(
        color: context.palette.textSecondary,
        fontSize: AppFontSize.small,
      ),
    ),
  );
}

/// "Języki wyłączone z transliteracji": the [nonLatinLanguages] music.db has songs in (all of
/// them before music.db is downloaded), ticked ones shown without Latin names or transliterated
/// lyrics.
class _ExcludedLanguagesScreen extends StatelessWidget {
  const _ExcludedLanguagesScreen();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themes = ThemeScope.of(context);
    final songs = SongCatalogScope.maybeOf(context)?.songs ?? const [];
    final inCatalog = {for (final song in songs) ...languagesOf(song.language)};
    final languages = [
      for (final language in nonLatinLanguages)
        if (inCatalog.isEmpty ||
            inCatalog.contains(language) ||
            themes.excludedLanguages.contains(language))
          language,
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.transliterationExcludedLanguages),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          _Note(l10n.transliterationExcludedLanguagesNote),
          const SizedBox(height: 8),
          for (final language in languages)
            CheckboxListTile(
              value: themes.excludedLanguages.contains(language),
              title: Text(language),
              onChanged: (value) =>
                  themes.setLanguageExcluded(language, value ?? false),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
