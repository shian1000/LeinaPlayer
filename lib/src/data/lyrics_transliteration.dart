/// Lyrics in another alphabet shown in Latin letters in the card under the full player
/// (Ustawienia › Wygląd › "Transliteracja tekstów piosenek" and "Metoda transliteracji").
///
/// With no method ticked the lyrics card has no button. Neither method is built yet ("Work in progress :)"): the server's waits for MusicDatabase
/// to send a transliteration with the lyrics (hand-off
/// `docs/handoffs/musicdatabase-lyrics-transliteration.md`); the phone's own is only an idea
/// (`docs/ideas/lyrics-transliteration.md`) — the phone doesn't transliterate names either
/// (`latin_names.dart`).
library;

/// When the lyrics card shows a song's lyrics transliterated.
enum LyricsTransliteration {
  never,

  /// A button in the lyrics card switches between the original and the Latin text.
  onRequest,

  always,
}

/// Where a transliteration of the lyrics may come from — any of them, both by default; none
/// ticked means no transliteration at all.
enum TransliterationMethod {
  /// From MusicDatabase's server, with the lyrics (`GET /lyrics/<songs.id>`).
  server,

  /// Worked out on the phone; does nothing yet.
  onDevice,
}
