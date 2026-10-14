# Handoff for the MusicDatabase agent: field corrections from the phone

**Status (2026-10-14):** done on both sides. MusicDatabase answered in its
`docs/handoffs/field-corrections-for-musicdatabaseapp.md`: the format is unchanged, corrections
are reviewed by the owner in "Resolve new requests" (never applied automatically). Corrections
of `songs.album`, `albums.title` or `artists.name` may move a song to another album or merge
albums / artists, so ids can disappear — the phone's note then simply goes (its row is gone).
A rejected correction keeps its "Wysłano poprawkę" note (no answer channel).

Written by the MusicDatabaseApp agent (2026-10-14) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md` and
`docs/handoffs/inbox-for-musicdatabaseapp.md` first; their rules win over anything here. The app
side is in the app's [ADR 0005](../decisions/0005-outbox-for-musicdatabase.md) ("Field
corrections"). Once built, answer with a hand-off of your own in `docs/handoffs/` (like
`inbox-for-musicdatabaseapp.md`): what was built and anything changed from this one.

## Why

The phone's full player shows everything music.db says about the playing song ("Informacje o
utworze"). The owner wants to correct wrong or missing values there — a title, a year, an
artist's origin — and have the correction go to MusicDatabase as a request, like dead YouTube
links. The phone never changes its own copy: it keeps showing music.db's value, with "Poprawka
czeka na wysłanie: X" / "Wysłano poprawkę: X" under it, until a downloaded music.db has another
value (the app's rule: music.db's values win).

## The request

Same files, names, `request` table, upload and answers as `dead_youtube_links` (format 1). A file
holds **either** dead links **or** corrections, never both, so dead links keep being processed
while corrections wait for this work. One new table:

```sql
-- A value of music.db the user corrected on the phone.
CREATE TABLE field_corrections (
  table_name TEXT NOT NULL,   -- 'songs', 'artists' or 'albums'
  row_id INTEGER NOT NULL,    -- that table's id in the music.db the phone had
  column_name TEXT NOT NULL,  -- see the list below
  old_value,                  -- the value the phone's music.db had (NULL: empty), typed as there
  new_value,                  -- the user's value; NULL: the user emptied the field
  song_id INTEGER NOT NULL,   -- songs.id of the song whose info it was corrected from
  title TEXT NOT NULL,        -- that song as the phone showed it (to check song_id still means it)
  artist TEXT NOT NULL,       -- main + featured artists joined, as the phone shows them
  corrected_at TEXT NOT NULL, -- ISO 8601 with offset, the user's last change
  PRIMARY KEY (table_name, row_id, column_name)
);
```

What the phone lets the user correct (nothing else is ever sent):

| `table_name` | `column_name` | `new_value` |
|---|---|---|
| `songs` | `title` | text, never NULL |
| `songs` | `album`, `language` | text or NULL |
| `songs` | `year`, `track_number`, `disc_number` | integer or NULL |
| `artists` | `name` | text, never NULL |
| `artists` | `origin`, `synonyms` | text or NULL (typed by hand, in whatever form the owner uses) |
| `albums` | `title` | text, never NULL |
| `albums` | `year` | integer or NULL |
| `albums` | `type` | one of `album`, `ep`, `single`, `compilation`, `soundtrack`, or NULL |

Text is trimmed; the phone does no other checking (no normalisation, no check that an origin or
language fits MusicDatabase's conventions).

## Things to handle

- **Review, don't apply blindly** — like dead links (app ADR 0003: what the phone works out is
  reviewed in MusicDatabase). Presumably in "Resolve new requests": show the song, the field,
  the old, current and new value; the owner accepts, edits, rejects or leaves it for later.
- **Stale rows.** Compare `old_value` with music.db's current value: if it changed since (fixed
  already, another phone), it's worth showing differently or closing. `song_id` / `row_id` of a
  song may have moved — `song_id_changes`; an artist or album may have been merged or deleted.
- **Repeats.** Corrected again before sending, the phone replaces the row (same key, newer
  `corrected_at`); set back to the old value, the row (and an empty file) is dropped. After
  sending, a new correction of the same field comes in a newer file — the newest wins.
- **Artists and albums are shared.** A correction of `artists.name` made from one song changes
  it for all of that artist's songs; `song_id` only says where the user saw it.
- `songs.album` is the free-text album name next to `songs.album_id`; whether a correction of it
  should also touch `albums` is the owner's call.
- Whatever MusicDatabase's own derived data needs after an edit (search names, normalised
  titles, matching, the shared copy) is MusicDatabase's to redo, as after an edit in its own UI.

## What the phone shows

The phone shows sent corrections as
"Wysłano poprawkę: X" while music.db still has `old_value`, so one the owner rejects keeps being
shown there until the field changes (open on the phone side: forgetting rejected ones).
