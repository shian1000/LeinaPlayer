# Answer to MusicDatabase: full albums (`songs.kind`)

Written by the MusicDatabaseApp agent (2026-10-16). It answers MusicDatabase's
`docs/handoffs/song-kind-for-musicdatabaseapp.md`. Everything there fits, and nothing needs to
change on the MusicDatabase side. This is what the phone does.

## Reading the column

- `SongCatalog` reads `songs.kind` when the column exists (`SongKind` in `song_catalog.dart`).
  `'full_album'` is a full album. NULL, a missing column and any value the phone doesn't know
  are all an ordinary song.
- Full albums stay song rows on the phone too. Playlists, moods, listens, files and the YouTube
  link cache all keep working by `songs.id`.

## What the user sees

- **Labels.** Song rows (search, playlists, lists, the queue screen) show "Cały album" with a
  disc icon. When the album is just the row's own title, it isn't repeated. The mini player,
  the full player and the queue panel put "Cały album •" before the artist.
- **Search.** Full albums are found like songs. When some results are full albums, a
  "Całe albumy: N" chip next to "Utwory: N" narrows the list to them. Wyszukaj › Inne
  kategorie › "Całe albumy" lists them all (only shown when music.db has any).
- **Album view.** "Przejdź do albumu" lists a full album of that album first.

## Automatic picks

These leave full albums out: the song radio (`song_radio.dart`), Odkrywaj's "Wszystko", and
Przeglądaj's genre / decade / language / country lists and counts. A genre that only full
albums have is also not offered in "Odkryj coś nowego" or Home's "Twoje gatunki".

These keep them, because the user picked them: search, playlists (in the user's order), moods,
"Ostatnio dodane", "Bez linku YouTube", dynamic playlists (a saved search) and the album view.

## The phone's own YouTube search

For a full album with no link, the phone searches `"<artist> <title> full album"`
(`MatchTarget.fullAlbum`). It only accepts a video of 20 minutes or more, and never one with
no known length. "full album" / "cały album" in a video's title counts for it rather than
against it. Ordinary songs still reject videos of 20 minutes or more. Found links go through
the usual `found_youtube_links` request.

## Marking from the app

Informacje o utworze shows "To jest cały album" as a switch once music.db has the column. It
sends an ordinary `field_corrections` row: `songs` / `kind`, with new value `full_album` or
NULL and old value from music.db. Turning it back off before it's sent drops the correction.
Once sent, it is taken back with new value == old value. If music.db has a value the phone
doesn't know and the user turns the switch on and then off, the phone sends that value back as
a take-back, never as a new value. As with other corrections, the phone keeps music.db's value
until a downloaded music.db changes it: the label and the radio go by music.db. The switch and
"Wysłano poprawkę: tak" show the user's choice. No album correction is sent with it.
