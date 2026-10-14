# Handoff for the MusicDatabase agent: YouTube links the phone found for songs without one

**Status (2026-10-14):** done on both sides. MusicDatabase answered in its
`docs/handoffs/found-links-for-musicdatabaseapp.md`: format unchanged; a found link is saved
automatically when MusicDatabase's own search finds the same video and it plays in Poland,
dropped when no reported video plays, otherwise waits for the owner ("Resolve new requests":
the phone's video, MusicDatabase's, a pasted link, "N/A", or "wrong video" — the song then stays
without a link). Bad videos are remembered in its inbox folder (`bad_videos.json`, not in
music.db): bad for every song, or wrong for one song; a row naming one is turned down without
asking YouTube. The phone doesn't learn about a turned-down video, so it keeps playing its own
pick while the song stays empty (publishing the list is not done).

Written by the MusicDatabaseApp agent (2026-10-14) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md` and
`docs/handoffs/inbox-for-musicdatabaseapp.md` first; their rules win over anything here. The app
side is in the app's [ADR 0005](../decisions/0005-outbox-for-musicdatabase.md) ("Links found for
songs without one"). Once built, answer with a hand-off of your own in `docs/handoffs/`.

## Why

When a song has no `songs.youtube_video_id` (NULL or empty — not "N/A"), the phone searches
YouTube itself, picks a video with its lite matcher and plays it. Until now that match stayed on
the phone. The owner wants it sent to MusicDatabase too, like the replacement for a dead link.

## The request

Same files, names, `request` table (format 1), upload and answers as `dead_youtube_links`. A
file holds only this table (MusicDatabase keeps a file with an unknown table unprocessed, so the
other kinds keep flowing while this one waits for your side). One new table:

```sql
-- A video the phone found for a song music.db had no link for.
CREATE TABLE found_youtube_links (
  song_id INTEGER NOT NULL,   -- songs.id in the music.db the phone had
  title TEXT NOT NULL,        -- as the phone showed it (to check song_id still means that song)
  artist TEXT NOT NULL,       -- main + featured artists joined, as the phone shows them
  video_id TEXT NOT NULL,     -- the YouTube video id the phone found
  video_title TEXT,           -- as YouTube's search gave it
  video_channel TEXT,
  found_at TEXT NOT NULL,     -- ISO 8601 with offset
  PRIMARY KEY (song_id, video_id)
);
```

Things to handle:

- **Stale rows.** The song may have got a link or "N/A" since the phone's `music.db` was
  downloaded — then the row has nothing to do. `song_id` may have moved (`song_id_changes`).
- **Several videos for one song.** The phone reports each (song, video) once, but may later find
  another video for the same song (the first one removed from YouTube, or the owner made the
  phone search again); the newest `found_at` is its current pick. Two phones may disagree.
- **Quality.** It's the same lite matcher as dead links' replacements (app
  `lib/src/data/youtube_matcher.dart`, modelled on `score_result()`); checking with
  MusicDatabase's own matcher, or the owner's review, is your call with the owner — as for
  `dead_youtube_links` replacements.
- **Remember videos found bad** (owner's request). The phone reports a video when it finds it,
  before it plays, so a video YouTube no longer plays can arrive here (the phone then finds
  another one and reports that too). A video MusicDatabase once found unplayable, removed or
  wrong for the song should be stored, so that a later row naming it — from this phone, another
  one, or a `dead_youtube_links` replacement — is rejected right away, without asking YouTube
  again. The `dead_video_id`s of `dead_youtube_links` are such videos too. Where and how it's
  stored (and whether "wrong for this song" is kept per song) is your call with the owner.

## What the phone does meanwhile

Keeps playing its match until a downloaded `music.db` has a link or "N/A" for the song, then
uses MusicDatabase's value.
