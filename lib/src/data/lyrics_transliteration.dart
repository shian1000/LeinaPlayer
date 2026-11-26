/// Lyrics in another alphabet shown in Latin letters in the card under the full player
/// (Ustawienia › Wygląd › Transliteracja: "Transliteracja tekstów piosenek", "Metoda
/// transliteracji" and "Alternatywne metody transliteracji").
///
/// With no method ticked the lyrics card has no button. "Pobierz z serwera" shows the Latin text
/// MusicDatabase sends with the lyrics (`plain_latin` / `synced_latin`, its hand-off
/// `lyrics-latin-for-musicdatabaseapp.md`), or one of its alternatives for a language
/// ([UkrainianTransliteration]). "Przelicz na miejscu" isn't built ("Work in progress :)"; only
/// an idea, `docs/ideas/lyrics-transliteration.md`) — the phone doesn't transliterate names
/// either (`latin_names.dart`).
library;

import 'lyrics.dart';

/// When the lyrics card shows a song's lyrics transliterated.
enum LyricsTransliteration {
  never,

  /// A button in the lyrics card switches between the original and the Latin text.
  onRequest,

  /// The Latin text straight away, the original a tap on the same button away.
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

/// "Alternatywne metody transliteracji › Ukraiński": which of MusicDatabase's Latin texts
/// Ukrainian lyrics are shown in.
enum UkrainianTransliteration {
  /// MusicDatabase's usual one, the Ukrainian national system of 2010 — `plain_latin`.
  national,

  /// The owner's Slavic alphabet (Lacinka with Slovak's ď ť ľ: "biľšisť, liudy, Ľviv, deń") —
  /// `latin_alternatives["uk-slavic"]`.
  slavic,
}

/// MusicDatabase's name for [UkrainianTransliteration.slavic] in `latin_alternatives`.
const ukrainianSlavicMethod = 'uk-slavic';

/// [lyrics] in Latin letters as [ukrainian] asks — an alternative only where the server sent
/// one, else its usual Latin text; `null` when it sent none.
Lyrics? latinLyrics(Lyrics lyrics, UkrainianTransliteration ukrainian) =>
    (ukrainian == UkrainianTransliteration.slavic
        ? lyrics.latinAlternatives[ukrainianSlavicMethod]
        : null) ??
    lyrics.latin;
