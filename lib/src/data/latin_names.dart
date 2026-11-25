/// Latin forms of names written in another alphabet ("Кино (Kino)") — Ustawienia › Wygląd ›
/// "Nazwy w alfabecie łacińskim" ([LatinNames]).
///
/// The forms come from music.db, where the owner keeps them by hand (`songs.title_latin`,
/// `artists.name_latin`, `albums.title_latin` — see the hand-off
/// `docs/handoffs/musicdatabase-latin-names.md`). The phone never transliterates on its own
/// (user's decision): an artist without `name_latin` falls back to a Latin-only entry of its
/// `artists.synonyms`; a title or album without one shows nothing extra.
library;

final _nonLatinLetter = RegExp(r'(?!\p{Script=Latin})\p{L}', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);

/// Whether [text] has a letter of an alphabet other than Latin (Cyrillic, kana, Hangul, …).
bool hasNonLatinLetters(String? text) =>
    text != null && _nonLatinLetter.hasMatch(text);

/// [latin] as the Latin form of [text]: only when [text] needs one and [latin] says something
/// else; `null` otherwise.
String? latinFormOf(String? text, String? latin) {
  final trimmed = latin?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == text?.trim()) {
    return null;
  }
  return hasNonLatinLetters(text) ? trimmed : null;
}

/// The first entry of `artists.synonyms` (comma-separated) written only in Latin letters.
String? latinSynonym(String? synonyms) {
  for (final synonym in (synonyms ?? '').split(',')) {
    final s = synonym.trim();
    if (_letter.hasMatch(s) && !hasNonLatinLetters(s)) return s;
  }
  return null;
}

/// "Кино (Kino)", or just [text] without a [latin] form.
String withLatin(String text, String? latin) =>
    latin == null ? text : '$text ($latin)';

/// How names in another alphabet are shown (Ustawienia › Wygląd › "Nazwy w alfabecie
/// łacińskim").
enum LatinNames {
  /// "Кино": the Latin form isn't shown.
  original,

  /// "Кино (Kino)".
  inBrackets,

  /// "Kino": the Latin form in place of the name, the name itself where there's none.
  instead;

  /// [text] as this setting shows it, with its Latin form [latin] (`null`: none).
  String show(String text, String? latin) => switch (this) {
    original => text,
    inBrackets => withLatin(text, latin),
    instead => latin ?? text,
  };

  /// Whether the Latin form is shown at all (a cover's credit takes it then).
  bool get shown => this != original;
}

/// Languages written in an alphabet other than Latin, by music.db's `songs.language` names —
/// what "Języki wyłączone z transliteracji" offers (the ones music.db has songs in). Languages
/// written both ways (Serbo-Croatian, Kurdish, Crimean Tatar…) aren't here: their songs are
/// mostly in Latin letters already.
const nonLatinLanguages = [
  'Altai',
  'Arabic',
  'Armenian',
  'Attic Greek',
  'Belarusian',
  'Bulgarian',
  'Cantonese',
  'Chinese',
  'Church Slavonic',
  'Georgian',
  'Greek',
  'Hebrew',
  'Hindi',
  'Japanese',
  'Kannada',
  'Kashmiri',
  'Kazakh',
  'Korean',
  'Macedonian',
  'Mongolian',
  'Persian',
  'Punjabi',
  'Russian',
  'Ruthenian',
  'Serbian',
  'Tatar',
  'Tuvan',
  'Ukrainian',
  'Yiddish',
];

/// The languages of a `songs.language` value: "Japanese / English" → Japanese, English.
List<String> languagesOf(String? language) => [
  for (final part in (language ?? '').split('/'))
    if (part.trim() case final name when name.isNotEmpty) name,
];

/// Whether a song in [language] is left untransliterated: any of its languages is [excluded].
bool excludedFromTransliteration(String? language, Set<String> excluded) =>
    excluded.isNotEmpty && languagesOf(language).any(excluded.contains);
