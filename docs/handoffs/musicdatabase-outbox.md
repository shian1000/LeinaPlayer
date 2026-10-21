# Handoff for the MusicDatabase agent: an inbox for requests from the phone

**Status (2026-10-13):** done in MusicDatabase — the inbox is
`Settings.phone_inbox_dir` on the data drive (`PUT /inbox/<name>` on the sharing server), described in
MusicDatabase's `docs/handoffs/inbox-for-musicdatabaseapp.md`. The phone sends to it; the first
request (the four Elise Trouw songs, with replacements) arrived on 2026-10-13.

Written by the MusicDatabaseApp agent (2026-10-13) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md` and `docs/runbooks/database.md` first — their rules
(migrations, backups, tests, git, `~/system-docs/README.md` for anything outside the repo) win over
anything here. The app side is decided in the app's
[ADR 0005](../decisions/0005-outbox-for-musicdatabase.md).

## Why

The phone app (Leina Radio) plays songs from YouTube using `songs.youtube_video_id`. Some of those
links stop working: on 2026-10-12, four Elise Trouw songs (ids 4601–4604, "Chromatic", "Losing
Sleep", "Obsession", "Slipping Away") linked to "Elise Trouw - Topic" videos that YouTube answers
with `playabilityStatus` `UNPLAYABLE`, "This video is not available". Note that oEmbed still
answered 200 for all four, so oEmbed is no test of whether a video plays. The phone now finds
another video and plays that, but it only stores it locally; the link has to be fixed in
`music.db`.

The owner wants the phone to report such things to MusicDatabase. The phone has an **outbox** of
requests; MusicDatabase needs an **inbox** for them.

## What you decide, together with the owner

1. **Where the inbox is: a folder on disk.** Pick a place that fits MusicDatabase's layout (e.g.
   next to the sharing copy in `Settings.sharing_dir`, or under the database folder), propose it
   to the owner and **wait for their confirmation** before creating anything.
2. **How a request gets from the phone into that folder.** The phone already reaches
   `sharing_server.py` (port 8002, Tailscale IP + the LAN interface); an upload endpoint there that
   writes into the inbox is the obvious option, but it's your call with the owner. That server is a
   contract with the app (port, file names) and lives partly outside the repo — record changes in
   `~/system-docs/README.md`. Tell the app's agent the result (via the owner) so the phone side can
   send.
3. **How requests are processed** — automatically, in a review screen, or both; what happens to a
   processed file (moved to a `processed/` folder, deleted…). The suggested replacement is a
   suggestion: the owner decided that phone-found data is reviewed in MusicDatabase, not applied
   blindly (app ADR 0003).

## The request files (format 1)

Each request is one SQLite file named `[<user>_]<date>_<time>_<number>.db`, e.g.
`2026-10-12_23-44-05_001.db`:

- `<user>` — the phone user's name (letters, digits and `-` only). **Not defined yet**: the owner
  will decide user names later, so for now files have no user part.
- `<date>_<time>` — when the phone started the request, phone's local time, `YYYY-MM-DD_HH-MM-SS`.
- `<number>` — counts up per phone (at least 3 digits), never reused.

A file holds one request, covering one song or many. Tables:

```sql
-- One row.
CREATE TABLE request (
  format INTEGER NOT NULL,      -- 1; goes up on incompatible changes
  created_at TEXT NOT NULL,     -- ISO 8601 with offset, e.g. 2026-10-12T23:44:05+02:00
  user_name TEXT,               -- NULL until user names exist
  app TEXT NOT NULL             -- 'Leina Radio'
);

-- music.db's songs.youtube_video_id that YouTube no longer plays.
CREATE TABLE dead_youtube_links (
  song_id INTEGER NOT NULL,     -- songs.id in the music.db the phone had
  title TEXT NOT NULL,          -- as the phone showed it (to check song_id still means that song)
  artist TEXT NOT NULL,         -- main + featured artists joined, as the phone shows them
  dead_video_id TEXT NOT NULL,  -- the songs.youtube_video_id the phone had
  detected_at TEXT NOT NULL,    -- ISO 8601 with offset
  replacement_video_id TEXT,    -- a video the phone found and plays instead, if any
  replacement_title TEXT,
  replacement_channel TEXT,
  replacement_found_at TEXT,
  PRIMARY KEY (song_id, dead_video_id)
);
```

What the phone counts as "dead": NewPipeExtractor's `ContentNotAvailableException`,
`PrivateContentException` or `AccountTerminatedException` (youtube_explode's
`VideoUnavailableException`) — removed, private, unavailable, channel closed. Age, region and
payment limits are **not** reported (the video exists).

Things to handle:

- **Stale rows.** `songs.youtube_video_id` may have changed since the phone's `music.db` was
  downloaded (fixed already, or set to "N/A"); compare with `dead_video_id` before acting.
  `song_id` may have moved too — `song_id_changes` has the history.
- **Repeats.** The phone reports a dead link once, but two phones (later) or a reinstalled app may
  report the same one; `(song_id, dead_video_id)` identifies it.
- The replacement comes from the phone's "lite" matcher (app `lib/src/data/youtube_matcher.dart`,
  modelled on `score_result()` in `src/utils/youtube/manage_youtube_playlists.py`): less data than
  MusicDatabase has, so it's worth checking with MusicDatabase's own matcher.
- More request types will come as new tables in the same kind of file (the app's ADR 0003
  direction: anything the phone works out itself). An unknown table should be left alone, not
  fail the whole file.

## What the phone does meanwhile

Requests stay in the phone's outbox; nothing is sent. The phone keeps playing its replacement
until a downloaded `music.db` has a different link or "N/A" for the song, then uses
MusicDatabase's value.
