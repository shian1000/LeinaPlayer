import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

/// A language the app can be switched to on Ustawienia › Wygląd › Język, by its own name.
class AppLanguage {
  const AppLanguage(this.tag, this.locale, this.name);

  /// Saved in `shared_preferences` and sent to Kotlin (`LinkChooserActivity`, notifications).
  final String tag;
  final Locale locale;

  /// Shown in the language itself, so anyone finds theirs whatever the app speaks now.
  final String name;
}

/// Every language the app may know. One without its `.arb` file yet isn't offered
/// ([availableLanguages]).
const _allLanguages = [
  AppLanguage('pl', Locale('pl'), 'Polski'),
  AppLanguage('en-US', Locale('en'), 'English (US)'),
  AppLanguage('en-GB', Locale('en', 'GB'), 'English (UK)'),
  AppLanguage('de', Locale('de'), 'Deutsch'),
  AppLanguage('fr', Locale('fr'), 'Français'),
  AppLanguage('hr', Locale('hr'), 'Hrvatski'),
  AppLanguage('sr-Cyrl', Locale('sr'), 'Српски (ћирилица)'),
  AppLanguage(
    'sr-Latn',
    Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'),
    'Srpski (latinica)',
  ),
  AppLanguage('uk', Locale('uk'), 'Українська'),
  AppLanguage('ru', Locale('ru'), 'Русский'),
  AppLanguage('be-Cyrl', Locale('be'), 'Беларуская (кірыліца)'),
  AppLanguage(
    'be-Latn',
    Locale.fromSubtags(languageCode: 'be', scriptCode: 'Latn'),
    'Biełaruskaja (łacinka)',
  ),
  AppLanguage('lt', Locale('lt'), 'Lietuvių'),
  AppLanguage('el', Locale('el'), 'Ελληνικά'),
  AppLanguage('ro', Locale('ro'), 'Română'),
  AppLanguage('hu', Locale('hu'), 'Magyar'),
];

/// The languages with translations, Polish first.
final List<AppLanguage> availableLanguages = [
  for (final language in _allLanguages)
    if (AppLocalizations.supportedLocales.contains(language.locale)) language,
];

/// "Język telefonu": the saved tag when the app follows the phone.
const systemLanguageTag = 'system';

AppLanguage? languageByTag(String tag) =>
    availableLanguages.where((l) => l.tag == tag).firstOrNull;

/// English with British spelling where the phone is set to a country that writes it.
const _britishEnglishCountries = {'GB', 'IE', 'AU', 'NZ', 'ZA', 'IN', 'MT'};

/// The app's language for the phone's [preferred] ones: the first the app knows, else Polish.
/// Serbian and Belarusian follow the phone's script, English its country.
Locale resolveSystemLocale(Iterable<Locale>? preferred) {
  for (final locale in preferred ?? const <Locale>[]) {
    final candidates = [
      for (final language in availableLanguages)
        if (language.locale.languageCode == locale.languageCode)
          language.locale,
    ];
    if (candidates.isEmpty) continue;
    Locale? pick(bool Function(Locale) test) =>
        candidates.where(test).firstOrNull;
    final found = switch (locale.languageCode) {
      'en' when _britishEnglishCountries.contains(locale.countryCode) => pick(
        (l) => l.countryCode == 'GB',
      ),
      'sr' || 'be' when locale.scriptCode == 'Latn' => pick(
        (l) => l.scriptCode == 'Latn',
      ),
      _ => null,
    };
    return found ??
        pick((l) => l.countryCode == null && l.scriptCode == null) ??
        candidates.first;
  }
  return const Locale('pl');
}

/// The locale for a saved [tag] ([systemLanguageTag] or one of [availableLanguages]).
Locale localeForTag(String tag) =>
    languageByTag(tag)?.locale ?? resolveSystemLocale(_phoneLocales());

/// Through the binding where there is one, so widget tests can set the phone's language;
/// plain unit tests have none.
List<Locale> _phoneLocales() {
  try {
    return WidgetsBinding.instance.platformDispatcher.locales;
  } on FlutterError {
    return PlatformDispatcher.instance.locales;
  }
}

AppLocalizations _current = lookupAppLocalizations(const Locale('pl'));

/// The app's texts in its current language. Reachable without a `BuildContext`, so data code
/// (notifications, mood names, errors shown later) and widgets use the same one; widget tests
/// without localization delegates get Polish.
AppLocalizations get l10n => _current;

/// Sets [l10n] before the first frame (`ThemeController.load`).
void setAppLocale(Locale locale) {
  _current = lookupAppLocalizations(locale);
}

/// Called from `MaterialApp.builder`, under the app's `Localizations`: takes the language it
/// resolved, and when that changed, rebuilds every widget — most read [l10n] rather than
/// depending on `Localizations`, so they wouldn't notice by themselves.
void syncAppLocale(BuildContext context) {
  final locale = Localizations.localeOf(context);
  if (_current.localeName == lookupAppLocalizations(locale).localeName) return;
  _current = lookupAppLocalizations(locale);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    void markAll(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markAll);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(markAll);
  });
}
