# Phone library, search and playback

Covers `lib/src/data/local_library.dart`, `song_catalog.dart`, `combined_search.dart`,
`text_normalizer.dart` and `lib/src/playback/`.

## Matching phone files to MusicDatabase

- Artist/title of a file come from its **tags first, the file name only when tags lack a title or
  an artist** — the same rule as MusicDatabase's mp3 import. Decided with the user even though it
  means a file named "Atrapa - Do usuniecia.mp3" tagged as Johnny Cash matches Johnny Cash.
  Don't flip it to filename-first.
- The file-name fallback ports the first two stages of MusicDatabase's `split_artist_title()`
  (spaced ` - `/` – `/` — `/` _ `, then bare `-`/`_`/`~`). Names with neither (e.g. double
  spaces) get no artist and show as "Nieznany wykonawca"; that's inherited, not a bug here.
- Matching is `SongCatalog.findExact`: normalized title equal **and** normalized artist equal to
  one of the song's artists, the whole "A feat. B" label, or an artist synonym.
- `text_normalizer.dart` mirrors MusicDatabase's `normalize()`. Dart has no Unicode
  decomposition, so the accent table is generated from Python's `unicodedata`; regenerate rather
  than hand-edit it.
- `tag.db` holds only MusicDatabase's technical markers today ("album_checked", "spellchecked"),
  and the mood columns are empty — that's why neither is a search field.

## `local.db`

- Lives in `<app support>/local/local.db`, separate from the downloaded `database/` folder.
  Table `local_songs`: MusicDatabase's `songs` columns (artist as a name, no artists table), plus
  `file_path` (unique), `main_db_id`, `pending`, `added_at`, `checked_at`. The user said more
  columns will come; bump `version` and add `onUpgrade` when they do.
- A scan drops rows whose files vanished and re-checks every pending row, so pending files flip
  to matched after a newer `music.db` arrives. Without a downloaded `music.db` everything is
  pending.
- Tags are read in `Isolate.run` (the parser is synchronous). All rows are kept in memory so
  search doesn't hit SQLite per keystroke.

## Device access

- Reading files by path needs READ_EXTERNAL_STORAGE (≤ Android 12; plus
  `requestLegacyExternalStorage` for Android 10) or READ_MEDIA_AUDIO (13+). The screen requests
  both and accepts either.
- On the Huawei test phone the user picked the SD card's Music folder
  (`/storage/2023-3514/Music`), not internal `/storage/emulated/0/Music`.

## Search results and playback

- Results combine MusicDatabase songs (with the phone files linked to them) and phone-only
  pending files. `SongAvailability`: **available** = has a phone file (pending or not);
  **potentiallyAvailable** exists for future sources and is empty; everything else unavailable.
  Only available results play.
- Playback (`PlayerController` over `just_audio`) is one song, no queue, no background/media
  notification service. "Poprzedni" restarts the song. `just_audio`'s `play()` future completes
  only when playback stops — never await it.
