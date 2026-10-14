# Handoff for the MusicDatabase agent: publish the videos found bad

**Status (2026-10-14):** done on both sides. MusicDatabase answered in its
`docs/handoffs/bad-videos-for-musicdatabaseapp.md`: table `bad_youtube_videos` in music.db
(migration 0010; `song_id` NULL = every song, always a current `songs.id`; `reason` codes
`removed`, `unplayable`, `replaced_dead_link`, `wrong_for_song`, `no_video_for_song`, more may
come). The phone reads it with each music.db (`SongCatalog.badVideos`; a missing table is an
empty list) — see the app's `docs/agent-notes/youtube.md`.

Written by the MusicDatabaseApp agent (2026-10-14) for an agent working in `../MusicDatabase`,
following MusicDatabase's `docs/handoffs/found-links-for-musicdatabaseapp.md` ("Videos found
bad"). Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md` and
`docs/data-model.md` first; their rules (migrations, backups, tests) win over anything here.
Once built, answer with a hand-off of your own in `docs/handoffs/`.

## Why

MusicDatabase now remembers bad videos in `bad_videos.json` and turns down the phone's
suggestions naming them. The phone never learns about that: when the owner picks "wrong video"
for a song, the song stays without a link and Leina Radio keeps playing its own (wrong) pick
forever — it has no reason to search again. The owner wants the phone to know the list.

## What the phone needs

For each bad video:

- the YouTube video id;
- **every song** or **one song** (`songs.id`, following merges like the rest of music.db) —
  the two kinds you already keep;
- optionally the reason (removed, doesn't play here, wrong for the song, replaced dead link) and
  when it was found bad — the phone would only show them, never act on them differently.

Where: preferably **in `music.db`** (e.g. a table `bad_youtube_videos (video_id TEXT NOT NULL,
song_id INTEGER NULL — NULL: bad for every song, reason TEXT, marked_at TEXT)`), because the
phone already downloads it daily and reads it in one place; schema and name are your call with
the owner. A separate shared file is fine too if `music.db` is the wrong home for inbox state —
then it needs to be served by `sharing_server.py` next to `music.db` (a contract with the app:
say its path and format).

When a video comes off your list (the owner chose it, or kept a link reported dead), it should
disappear from the published copy too.

## What the phone will do with it

- **Bad for every song:** treated like a video YouTube removed — never played, skipped in search
  results, and a song or imported playlist track using it gets another video found.
- **Wrong for one song:** dropped as the phone's pick for that song only (the song is searched
  again, without that video); other songs may still use it.
- The phone's own findings still never override music.db (the app's ADR 0003). An older phone
  build ignores the new table.
