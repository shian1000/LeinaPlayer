/// Latin forms of names written in another alphabet ("Кино (Kino)") — Ustawienia › Wygląd ›
/// "Nazwy w alfabecie łacińskim".
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
