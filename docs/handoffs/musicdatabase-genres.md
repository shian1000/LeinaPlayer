# Handoff for the MusicDatabase agent: a song's genre

**Status (2026-10-16):** done on the MusicDatabase side, as a column of the song (not a tag kind).
MusicDatabase answered in its `docs/handoffs/genres-for-musicdatabaseapp.md`. Migration
`0013_song_genre.sql` adds `songs.genre`. It reaches the shared music.db once MusicDatabase has
been started, and every song starts NULL. `("songs", "genre")` is in `FIELDS`, labelled "song
genre".

Differences worth knowing on the phone:
- **Rhythm and blues is stored as `r&b`**, MusicBrainz's name, not "rhythm and blues".
- **Every value is stored in one lowercase spelling per genre.** The order of lookup is a
  synonym list, then the spelling music.db already uses, then MusicBrainz's genre list. So
  "Synthpop" and "synth pop" become `synth-pop`, and "Hip-Hop" becomes `hip hop`.
- **A correction is cleaned the same way on the way in.** One that differs only in spelling from
  music.db's value is settled as already set. An accepted one may be stored slightly differently
  from what the user typed.

MusicDatabase fills the column from MusicBrainz (Fill missing data › "Genres"):
- It uses the song's own genres first, then the album's. The artist's genres are saved only
  after the owner reviews them.
- A song gets at most 3 genres, the most voted first.
- Many songs will stay NULL for a while; in a trial, 4 of 10 found nothing.

The owner can also set genres by hand in the editor and in Song actions › "Set genre". Nothing
to change on the phone unless the `r&b` spelling matters to its matcher.

Written by the MusicDatabaseApp agent (2026-10-16) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md` and
`docs/handoffs/field-corrections-for-musicdatabaseapp.md` first; their rules win over anything
here. When it's built, answer with a hand-off of your own in `docs/handoffs/` (like
`latin-names-for-musicdatabaseapp.md`): what was built and anything that differs from this.

## Why

The phone has a song radio ("Przejdź do radia utworu"): the song, then up to 50 songs of music.db
like it. MusicDatabase has no radio, so the phone guesses alikeness itself (lite logic, the app's
ADR 0003) from what music.db and tag.db know: a shared artist, global and user moods, language,
the artists' country, the year. The owner wants **the genre** to count too, and asked for it to
be a column of the song in music.db — MusicDatabase owns the value, the phone only reads it.

## The column

One new nullable text column (one migration in MusicDatabase's usual way — `0013_…` after
`0012_song_music_video.sql` if nothing came in between — plus the model in `datatables.py` and
the diagram in `docs/data-model.md`):

| Table | Column | Contents |
|---|---|---|
| `songs` | `genre` | the song's genre(s) |

- **Several genres, comma-separated, the main one first**: `indie pop, synth-pop`. One genre is
  just its name. Empty = NULL (no genre known). Trimmed; the same genre not twice.
- No commas inside a genre name — write "rhythm and blues", "drum and bass" (MusicBrainz already
  uses those forms).
- Free text, but **one spelling per genre across the database** matters more than anything else:
  the phone counts two songs as sharing a genre when the names are equal (ignoring case,
  diacritics and punctuation — so "Synth-pop", "synth pop" and "synthpop" are not all the same
  word to it: "synth-pop"/"synth pop" match each other, "synthpop" doesn't). Pick one form —
  MusicBrainz's genre names (lowercase, e.g. `hip hop`, `synth-pop`, `alternative rock`) are a
  good common vocabulary — and map the other sources' names onto it.
- A song-level column, not the artist's: a band's songs can be in different genres. If a source
  only gives an artist's or album's genre, using it for the song is fine (the owner's call), as
  long as a song-level genre wins where there is one.
- It must reach the shared `music.db` the phone downloads, like every other column.

Considered and left aside: genres as a new `tags.kind = 'genre'` in tag.db (`0003_tag_kind.sql`
foresees it). The owner asked for a column of the song; if MusicDatabase prefers the tag table
after all, say so in your answer before building it — the phone would then read
`song_tags` / `tags` with `kind = 'genre'` instead.

## Where the genres can come from (suggested, the owner's call)

- **Google's Knowledge Panel** is already parsed: `google_search_fetcher.py` maps `skos_genre` to
  `genre` (comma-joined links) but nothing stores it yet.
- **iTunes** search results carry `primaryGenreName` (one, broad: "Pop", "Alternative").
- **MusicBrainz** has genres (voted tags) on recordings, releases / release groups and artists,
  via `inc=genres` on a lookup.
- **Wikipedia** infoboxes of songs and singles have a "Genre" row.

As with the other enrichments: what is found is suggested / filled in by MusicDatabase's usual
discovery flow, and nothing the owner typed is overwritten without them accepting it. A way to
fill in the missing ones in one go (like "Fill in Latin forms of names in other alphabets") would
help, since ~5700 songs start empty.

## Requests from the phone: field corrections

The phone already lets the user correct the field in "Informacje o utworze" (the pencil, label
"Gatunek") — it shows up there as soon as the downloaded music.db has the column, and goes out
as an ordinary `field_corrections` row (format unchanged — the app's
`musicdatabase-field-corrections.md`):

| `table_name` | `column_name` | `new_value` |
|---|---|---|
| `songs` | `genre` | text (comma-separated, as above) or NULL |

Please add `("songs", "genre")` to `FIELDS` in `inbox_field_corrections.py` (text, NULL allowed),
with a `FIELD_LABELS` entry such as "song genre". The phone sends the text as the user typed it;
normalizing it to the database's spelling (trim, drop repeats, map known synonyms) on the way in
is welcome.

## What the phone does with it (for reference — nothing to build for it)

- Reads `songs.genre` when the column exists; older `music.db`s still work (no genres).
- Radio: a genre the two songs share is worth as much as a shared mood (2 points, at most two
  genres counted); without one, a genre with a word of the other's ("indie pop" — "pop",
  "alternative rock" — "punk rock") is worth 1. A shared artist is 3, language / country /
  decade 1 each, a song needs 2 to be in the radio.
- "Informacje o utworze" shows the column with everything else of the song's row.
