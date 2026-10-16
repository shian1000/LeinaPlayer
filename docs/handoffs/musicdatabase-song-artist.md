# Handoff for the MusicDatabase agent: another artist for a song

**Status (2026-10-17):** done on both sides, in one session with the owner. MusicDatabase's answer
is its `docs/handoffs/song-artist-for-musicdatabaseapp.md`.

## Why

Until now the only way to fix a song's artist on the phone was the pencil next to the artist's
name — an `artists.name` correction. That renames the artist row, which every song of the artist
shares, or (when the new name is another artist's) offers merging the two artists. Usually the
user means something else: *this song* is by another artist. The owner's decision (2026-10-16):
changing the artist on the phone is a proposal of another artist for the song, not a rename.

## On the phone

The pencil next to the song's own artist ("Wykonawca" › "Nazwa" in "Informacje o utworze") asks
first:

- **"Ten utwór ma innego wykonawcę"** (first, the usual case) — the user types the artist's name;
  it goes out as the correction below.
- **"Popraw pisownię nazwy"** — the old `artists.name` correction, for all the artist's songs.

Co-artists and guests ("Współwykonawca", "Gościnnie") keep only the spelling correction for now.

## The correction

A `field_corrections` row like the others (format 1, see
[`musicdatabase-field-corrections.md`](musicdatabase-field-corrections.md)):

| column | value |
|---|---|
| `table_name` | `songs` |
| `row_id` | `songs.id` |
| `column_name` | `artist_id` |
| `old_value` | the `songs.artist_id` the phone's music.db had (integer) |
| `new_value` | **the name** of the artist the song is by, as typed (trimmed, never NULL) |

The phone doesn't look the name up in music.db: matching it to an artist (or making a new one) is
MusicDatabase's.

Taking it back: the user types the song's current artist again (compared with `normalize()`,
`text_normalizer.dart`) — a waiting correction is dropped; a sent one is taken back with a newer
row whose `new_value` is the old artist's name as music.db has it.

The phone shows "Poprawka czeka na wysłanie: inny wykonawca — X" / "Wysłano poprawkę: inny
wykonawca — X" under the name while music.db still has `old_value` as the song's `artist_id`.
