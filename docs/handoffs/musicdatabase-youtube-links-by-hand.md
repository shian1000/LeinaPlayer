# Handoff for the MusicDatabase agent: YouTube links set by hand, and a music video column

**Status (2026-10-15):** done on both sides. MusicDatabase answered in its
`docs/handoffs/youtube-links-by-hand-for-musicdatabaseapp.md`: migration
`0012_song_music_video.sql` adds `songs.music_video_youtube_id` (name unchanged; the owner sets
it in Song actions › "Set music video link"). Both YouTube columns are reviewed, or saved
automatically from users with `apply_corrections` — a video id only after checking it plays and
isn't in `bad_youtube_videos` for the song. Accepting a `youtube_video_id` takes the video off
`bad_youtube_videos`, and the review asks (default no) whether to mark the replaced one
`wrong_for_song`. A newer link correction settles older dead / found link reports of the song in
the same batch. Take-backs (`new_value` = `old_value`) work for every column; one taken back
after the owner accepted the older correction goes to review as a real change back.

Written by the MusicDatabaseApp agent (2026-10-15) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md` and
its `docs/handoffs/field-corrections-for-musicdatabaseapp.md` first; their rules win over
anything here. This extends the app's field corrections
([`musicdatabase-field-corrections.md`](musicdatabase-field-corrections.md)); the app side is in
its [ADR 0005](../decisions/0005-outbox-for-musicdatabase.md) ("Field corrections"). Once built,
answer with a hand-off of your own in `docs/handoffs/` (e.g.
`youtube-links-by-hand-for-musicdatabaseapp.md`): what was built and anything changed from this
one — especially if you name the column differently.

## Why

The owner wants two things from the phone's song info ("Informacje o utworze" under the full
player):

1. **Change a song's YouTube link by hand** when music.db's video is wrong (or missing).
2. **A separate link to the song's music video** (teledysk). `songs.youtube_video_id` is the
   audio the phone plays — often a "Topic" upload or an official audio video, which the matcher
   prefers on purpose. The music video (official video with a clip, intro, other length) is a
   different thing the owner wants to open in YouTube from the player. The phone's YouTube
   button now asks "Utwór na YouTube" / "Teledysk na YouTube" when a song has both.

## 1. New column `songs.music_video_youtube_id`

A migration (next free number in `migrations/music/`, after `0011_latin_names.sql`):

```sql
-- The song's music video on YouTube, apart from youtube_video_id (the audio played).
-- Set by hand (or from a phone correction); NULL: none known.
ALTER TABLE songs ADD COLUMN music_video_youtube_id VARCHAR;
```

- A bare 11-character video id, like `youtube_video_id`. No "N/A" sentinel is needed (the phone
  never searches for music videos); NULL = none.
- Goes into the shared `music.db` as it is — the phone reads `songs.music_video_youtube_id` when
  the column is there (a `music.db` without it simply has no music videos).
- Editable in MusicDatabase's own song edit UI, next to `youtube_video_id`. Whether
  MusicDatabase should ever *find* music videos itself (search, enrichment) is the owner's call;
  not needed for the phone.
- Should **not** be used for playback, playlist creation on YouTube, `bad_youtube_videos` or
  the matcher — it's only a link to open.

## 2. Field corrections of the YouTube columns

The `field_corrections` table and request files are unchanged (format 1). Two columns are new in
what the phone sends:

| `table_name` | `column_name` | `new_value` |
|---|---|---|
| `songs` | `youtube_video_id` | an 11-character video id, `'N/A'` (not on YouTube — MusicDatabase's `NO_VIDEO_SENTINEL`), or NULL (no link) |
| `songs` | `music_video_youtube_id` | an 11-character video id, or NULL (no music video) |

`old_value` is music.db's value as the phone had it (trimmed; NULL for empty, `'N/A'` kept). The
phone accepts any YouTube link the user pastes (`watch?v=`, `youtu.be/`, `shorts/`, music.…) and
always sends only the id. For `music_video_youtube_id` the phone may send corrections before
your music.db has the column: their `old_value` is NULL.

Today `inbox_field_corrections.py` only knows the columns in its table (`("songs", "title")`
etc.); both new ones need adding there, with a label for the review ("YouTube video",
"music video"), and wherever else a correction's column is checked (`inbox_auto.py`'s verdict,
the review UI).

### Unlike other corrections, the phone uses these at once

For every other field the phone keeps showing music.db's value until MusicDatabase accepts the
correction. A YouTube link is different: the point of correcting it is that the right video
plays. So the phone **plays (and opens) the user's link** in place of music.db's from the
moment it's set, and keeps doing so while the downloaded music.db still has the `old_value`.
As soon as a downloaded music.db has *any* other value there (accepted, or settled otherwise),
the phone drops its own and follows music.db again (the app's server-wins rule).

Consequences worth handling:

- **A rejected correction keeps the phone on the user's link** (there's no answer channel), until
  music.db's value changes. Worth saying in the review prompt; if the owner rejects because
  music.db's video is right, nothing else is needed (the user can set it back on the phone).
- **Accepting a `youtube_video_id` correction is a manual pick** — treat it like the owner
  choosing the video in MusicDatabase's own UI: whatever that does today (e.g. the video comes
  off `bad_youtube_videos`, `search_video()` stops searching for the song, cached search results
  for the song go) should happen too. Whether the replaced video should go onto
  `bad_youtube_videos` as `wrong_for_song` is the owner's call — the phone would then keep it
  away from that song for good.
- A `'N/A'` correction is the user saying the song isn't on YouTube; NULL means "no link,
  search again". Both are legitimate values, not errors.
- The phone **no longer sends `found_youtube_links`** for a song the user set a link for by hand
  (the correction says it better). An older found link for the same song may already be in the
  inbox — the newer correction should win.
- **Automatic saving** (`inbox_auto.py`, users with `apply_corrections`): the owner may want the
  YouTube columns saved automatically like other fields, or always reviewed — ask. If saved
  automatically, a quick check that the video exists (the same check you do for found links)
  would be good.

### Taking a sent correction back (all columns, not only YouTube)

Until now the phone couldn't take back a correction once sent. It now can: when the user sets a
field back to music.db's value after the correction was sent, the phone sends a **newer**
correction with `new_value` equal to `old_value`. Your rule "repeats of one field … the newest
`corrected_at` is the value offered" plus "settled without asking: the database already holds
the new value" should already close such a case without asking — please check, and that the
older report of the same field isn't then offered on its own.

## What the phone does (for reference)

- Song info › Linki: "YouTube (music.db)" and "Teledysk (music.db)", each with a pencil; the
  correction shows under music.db's value ("Poprawka czeka na wysłanie, telefon już używa: X").
- Full player: the YouTube button opens the song (from where the player is, as before); with a
  music video as well (music.db's or the user's), it asks which one; the music video opens from
  its start.
