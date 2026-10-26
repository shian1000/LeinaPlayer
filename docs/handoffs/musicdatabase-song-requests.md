# Handoff for the MusicDatabase agent: songs Leina Radio asks to have added

**Status (2026-10-18):** done on both sides in one change (the owner's request): the phone sends
`song_requests`, and MusicDatabase reads them (its
`docs/handoffs/song-requests-for-musicdatabaseapp.md`) and publishes rejections in music.db's
`rejected_song_requests` (its migration 0015).

## Why

Leina Radio plays songs music.db doesn't have: videos of imported YouTube playlists, Spotify
tracks, files on the phone, shared links (the "*" by a song). The owner wants such a song to be
asked for: MusicDatabase searches for it and adds it. For now nothing is added automatically —
the owner approves, skips or rejects each one in MusicDatabase. A rejected song must not be asked
for again.

## The request table (format 1, files of their own)

```sql
CREATE TABLE song_requests (
  title TEXT NOT NULL,          -- as the phone shows it
  artist TEXT,                  -- as the phone shows it, or music.db's name when that is one of an artist's synonyms (a channel: "familyboombox" -> "Бумбокс"); NULL = it knows none
  album TEXT,                   -- a phone file's tags
  year INTEGER,
  duration_s INTEGER,           -- not filled yet (NULL)
  youtube_video_id TEXT,        -- the playlist's / shared video, or the phone's match
  spotify_track_id TEXT,        -- the Spotify playlist's track
  source TEXT NOT NULL,         -- 'youtube' | 'spotify' | 'phone_file'
  requested_at TEXT NOT NULL    -- ISO 8601 with offset
);
```

- Written when a song not in music.db starts playing (`TrackPlayer.play` →
  `Outbox.requestSong`), only once music.db is loaded, and never for a song the owner rejected.
- Once per song: a song already in any request (waiting, sent or refused) with the same artist and
  title (`normalizeForSearch`) or the same YouTube video isn't asked for again.
- "Czeka na wysłanie" lists the waiting ones.

## The answer: `rejected_song_requests` in music.db

```sql
CREATE TABLE rejected_song_requests (
  id INTEGER PRIMARY KEY,
  artist TEXT,                  -- as the request had it
  title TEXT NOT NULL,
  youtube_video_id TEXT,
  spotify_track_id TEXT,
  rejected_at TEXT NOT NULL
);
```

The phone reads it with music.db (`SongCatalog.rejectedSongRequests`; none before the migration)
and doesn't ask for a song matching a row by artist + title, YouTube video or Spotify track. An
added song simply shows up in the next music.db.
