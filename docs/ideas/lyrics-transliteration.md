# Transliterating lyrics on the phone ("Przelicz na miejscu")

**Status (2026-11-20):** an idea only. Ustawienia › Wygląd › "Metoda transliteracji" › "Przelicz na
miejscu" says "Work in progress :)". Nothing is decided; a choice here gets an ADR.

## The problem

Lyrics come from MusicDatabase's server or LRCLIB with no Latin form. The server may send one
(hand-off [`musicdatabase-lyrics-transliteration.md`](../handoffs/musicdatabase-lyrics-transliteration.md));
working it out on the phone would cover LRCLIB's lyrics, songs only on the phone, and use
without the server. Names stay as they are: their Latin forms come only from music.db (user's
decision), never from this.

## Two kinds of scripts

1. **Alphabets read letter by letter** — Cyrillic (by language: Russian, Ukrainian, Belarusian
   Lacinka, Serbian…), Greek, Georgian, Armenian, Hangul (by syllable blocks), Japanese kana. Small
   tables, a few KB of code, fast. This could be built into the app as a "lite" port of
   MusicDatabase's `romanize.py` / `suggest_latin()` (ADR 0003: name the counterpart, don't keep a
   full port in sync). The language comes from `songs.language` / the artist's origin; for songs
   not in music.db it has to be guessed from the letters (Ukrainian і ї є ґ, Belarusian ў…).
2. **Scripts that need a dictionary** — Japanese kanji (a word's reading depends on the word:
   日 is "hi", "nichi", "ka"…; needs a morphological analyser with a dictionary), Chinese hanzi to
   pinyin (polyphones need word segmentation), and Arabic / Hebrew, written without most vowels
   (no reliable reading at all — better left out). Japanese lyrics mix kanji and kana, so without
   a dictionary even kana-heavy songs come out half done.

## An add-on with dictionaries

The dictionaries are what's big: a Japanese analyser with its dictionary (Kuromoji-style
IPADIC, Sudachi's small dictionary) is roughly 15–50 MB, Chinese pinyin data from under 1 MB
(characters only, worse with polyphones) to tens of MB (words). Most users don't need them, so:

- **Built in:** group 1 above — small, no download.
- **An add-on per language group** ("Słowniki: japoński", "Słowniki: chiński"), installed only by
  those who want it. Two ways it could work:
  - *A data pack:* the dictionary files downloaded from a GitHub Release (like themes from
    `LeinaThemes`, ADR 0016) into the app's storage, read by an analyser library that's in the app
    itself. One APK, but the library's code is always in it (a few MB), and the download needs
    its place in Pamięć podręczna and Prywatność i połączenia (with a switch).
  - *A separate add-on APK* (signed with the same release key) with the analyser and its
    dictionary, which the app calls through a bound service or a `ContentProvider` guarded by a
    signature permission: `transliterate(text, language) → text`. The main APK stays small, and it
    matches the add-on plan for YouTube (sharing checklist 8.3). More work: two apps to build,
    release and keep compatible, Android 11+'s package visibility (`<queries>`).
- Either way the phone's result is a fallback: the server's Latin text always wins (ADR 0003),
  and a result that left any non-Latin letter isn't shown as a transliteration.

## Open questions

- Which languages are worth it, by how many songs in music.db have lyrics in them (Japanese is
  the big one; Chinese may be rare).
- Is ~90–95 % reading accuracy for kanji good enough for lyrics, with no way to correct it on the
  phone?
- Data pack or add-on APK — decide together with the YouTube add-on, so there's one mechanism.
