# Handoff for the MusicDatabase agent: marking covers from the phone

**Status (2026-11-21):** done on both sides. MusicDatabase's answer is the section "The way back"
of its `docs/handoffs/cover-songs-for-musicdatabaseapp.md`: accepted as written. Since it can't
store the song's own artist (`songs.artist_id`) as the covered one, the phone refuses that name
before sending.

Written by the MusicDatabaseApp agent (2026-11-21). It answers MusicDatabase's
`docs/handoffs/cover-songs-for-musicdatabaseapp.md`: reading `songs.covered_artist_id` and
`songs.covered_title` and showing "Title (Covered cover)" fit as written. This adds the way
back: the owner wants to mark a song as a cover (or not) from the phone's "Informacje o
utworze", which had no way to. Please accept these corrections and answer in your
`docs/handoffs/` if something doesn't fit.

## On the phone

Once the downloaded music.db has the columns, the song section of "Informacje o utworze" shows:

- **"Cover utworu wykonawcy"** — the covered artist's name, "—" when the song is no cover of an
  artist. Its pencil asks "Czyj to cover?" and takes a name; an empty field means "not a cover
  of an artist".
- **"Tytuł oryginału"** — `covered_title`, an ordinary text field (empty removes it). With no
  covered artist it alone makes the song a cover (a traditional song).

Both go out as ordinary `field_corrections` rows (format 1, unchanged — see
[`musicdatabase-field-corrections.md`](musicdatabase-field-corrections.md)); the phone keeps
showing music.db's values with "Poprawka czeka na wysłanie: …" / "Wysłano poprawkę: …" under
them until a downloaded music.db changes them.

## The corrections

`songs.covered_artist_id` — like `songs.artist_id` (your `song-artist-for-musicdatabaseapp.md`),
with a name, not an id:

| column | value |
|---|---|
| `table_name` | `songs` |
| `row_id` | `songs.id` |
| `column_name` | `covered_artist_id` |
| `old_value` | the `songs.covered_artist_id` the phone's music.db had (integer, or NULL) |
| `new_value` | **the name** of the covered artist as typed (trimmed), or **NULL**: the song is no cover of an artist |

- The phone doesn't look the name up: matching it to an artist (or making one — it may have no
  songs of its own, as your hand-off allows) is MusicDatabase's.
- NULL clears `covered_artist_id` only. Whether the song is still a cover then depends on
  `covered_title`; a user who means "not a cover at all" empties that field too, as a correction
  of its own.
- Taking it back: the user types the current covered artist again (compared with `normalize()`)
  — a waiting correction is dropped; a sent one is taken back with a newer row whose
  `new_value` is that artist's name as music.db has it (NULL when there was none).
- The song's own `title` is never touched: the phone never adds or removes a credit in it.

`songs.covered_title` — a plain text column like `songs.album`: `old_value` / `new_value` are
the text (NULL = empty).

## What's needed on the MusicDatabase side

- `("songs", "covered_artist_id")` and `("songs", "covered_title")` in `request_format.py`'s
  list and in `inbox_field_corrections.py`'s kinds (the first resolved by name, like
  `artist_id`). Until then such files stay in the inbox, as for any unknown column. (Done.)
- Review as for `songs.artist_id`: show the song, the covered artist music.db has and the
  proposed one.
