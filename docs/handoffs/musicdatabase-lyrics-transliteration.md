# Handoff for the MusicDatabase agent: lyrics in Latin letters

**Status (2026-11-20):** asked, not built on either side. The phone has the settings (Ustawienia ›
Wygląd › Transliteracja › "Transliteracja tekstów piosenek" and "Metoda transliteracji" › "Pobierz z serwera"), which
say "Work in progress :)" until the server sends what's below.

Written by the MusicDatabaseApp agent (2026-11-20) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md` and its `docs/handoffs/lyrics-for-musicdatabaseapp.md` (the
lyrics endpoint this extends) first; their rules win over anything here. When it's built, answer
with a hand-off of your own in `docs/handoffs/` (like `lyrics-for-musicdatabaseapp.md`): what was
built and anything that differs from this.

## Why

The full player shows a song's lyrics from `GET /lyrics/<songs.id>`. Many songs are in Cyrillic,
Japanese, Korean, Greek, Georgian…, and the owner wants to read their words in Latin letters too —
on request (a button by the lyrics) or always. Names already have owner-written Latin forms in
music.db (`title_latin`, `name_latin` — `latin-names-for-musicdatabaseapp.md`); lyrics have none,
and writing them all by hand isn't realistic, so they'd be worked out — where that's reliable — by
MusicDatabase, which already has the rules for it (`src/utils/common/romanize.py`,
`suggest_latin()`: English-style Russian, the Ukrainian national system, Belarusian Lacinka,
Serbian Latin, Greek, Georgian, Hangul, Hepburn kana) and knows the song's language and the
artist's origin. The phone doesn't transliterate names on its own (owner's decision, kept); a
phone-side method for lyrics is only an idea (`docs/ideas/lyrics-transliteration.md` in the app).

## Asked: two more fields in the lyrics answer

The same `GET /lyrics/<songs.id>` (no new endpoint, no token, same 200 / 404 / 503), with two
optional fields:

```json
{"song_id": 4, "plain": "Группа крови\nна рукаве", "synced": "[00:01.00] Группа крови\n[00:02.50] на рукаве",
 "instrumental": false, "source": "lrclib_fetcher",
 "plain_latin": "Gruppa krovi\nna rukave", "synced_latin": "[00:01.00] Gruppa krovi\n[00:02.50] na rukave",
 "latin_source": "romanize"}
```

- `plain_latin`: `plain` line for line (the same number of lines, empty lines kept), only letters
  of other alphabets changed; Latin words, numbers and punctuation as they are.
- `synced_latin`: `synced` with the same time stamps in the same order, each line's text
  transliterated — so the phone can swap the texts and keep highlighting the current line.
- `latin_source`: how it was made — e.g. `romanize` (MusicDatabase's rules) or `manual` (written
  by the owner, if that's ever offered). Informative; unknown values may come.
- Left out or `null` when the text has no letter outside the Latin script, when a script has no
  reliable reading yet (kanji / hanzi, Arabic, Hebrew — `suggest_latin()` gives None for them
  today), or when only part of the lyrics could be done: better nothing than a mixed text. A
  `synced_latin` must never come without `synced`, nor `plain_latin` without `plain`.
- The scheme by the song's language (`songs.language`) and the artist's origin, as
  `suggest_latin()` chooses already; a song marked `Unknown` with Cyrillic lyrics by
  `cyrillic_language()`'s guess.

Computed on the fly or kept in `lyrics.db` next to the text — MusicDatabase's choice. If kept, a
form the owner wrote by hand must never be overwritten by a computed one, and a new text (another
fetcher, a correction) drops the old computed form.

## What the phone will do (for reference — nothing to build for it)

- Read the fields when present; older servers simply don't send them (the button then says the
  song has no Latin text).
- "Na życzenie": a button in the lyrics card switches between the original and the Latin text;
  "Zawsze": the Latin text straight away, the original a tap away.
- Nothing new is stored or sent: it's the same request the phone makes today, so Prywatność i
  połączenia and `PRIVACY.md` only gain a line about what comes back.
- A Latin text from the server always beats anything the phone might work out itself (ADR 0003).
