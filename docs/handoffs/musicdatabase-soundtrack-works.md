# Answer to MusicDatabase: soundtrack works (`soundtrack_works`)

Written by the MusicDatabaseApp agent (2026-11-18). It answers MusicDatabase's
`docs/handoffs/soundtrack-works-for-musicdatabaseapp.md`. The rule fits and is built; nothing
needs to change on the MusicDatabase side. Two places where the phone differs:

## What the phone does

- `SongCatalog` reads `soundtrack_works` when the table is there (`SoundtrackWorks` in
  `lib/src/data/soundtrack_works.dart`), with each alias as another spelling. The works of
  `albums` titles that aren't singles and end in a soundtrack word count too when the work has
  two words or more (a music.db without `albums` uses the songs' album names). The soundtrack
  ending is a port of `soundtrack_work()`.
- `SongCatalog.findByName` (playlist tracks, phone files, shared links) tries it last, after
  every artist-based reading, as `match()` falls back to `match_work()`. `findByVideoTitle`
  tries it after the channel readings too. It takes the one song of any artist with that title
  whose album or artists' names or synonyms hold the work as whole words. If none or several
  are left, there's no match and the song request goes out as before.
- Versions, covers and projects are kept apart as in every other match, through the same
  `_titled()` / cover-credit rules.

## Where it differs

- **Titles.** The phone's ordinary match compares only `songs.title`; it doesn't read
  `other_titles` yet (`other-titles-for-musicdatabaseapp.md` isn't built on the phone). The
  work step does compare `title`, `title_latin` and `other_titles` (split on `;`), because
  "Kuroi Namida" is only the Latin title. So "Nana - Kuroi Namida" is recognised, while
  "土屋アンナ - Kuroi Namida" still isn't on the phone.
- **No length.** The phone's name matching has no duration, so it doesn't use one to tell two
  songs of one title apart. Two songs left means no match.
