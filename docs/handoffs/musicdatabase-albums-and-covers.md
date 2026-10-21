# Handoff for the MusicDatabase agent: albums table, track order, cover art

**Status (2026-10-12):** done in MusicDatabase — migrations `0005`–`0008` (`albums`,
`songs.album_id`, track/disc numbers, `album_covers`; `songs.album` kept) and the mp3 cover import
(`src/utils/discoveries/mp3_covers.py`; `album_covers` was still empty then, i.e. not run yet).
Serving covers to the phone is not started — the user will ask for it later.

Written by the MusicDatabaseApp agent (2026-10-11) for an agent working in `../MusicDatabase`.
The user decided the points below together with the app's agent and asked for the work to be done
in MusicDatabase by you. Read MusicDatabase's own `AGENTS.md` and `docs/runbooks/database.md`
first — their rules (migrations, backups, tests, git) win over anything here.

## Why

The phone app (Leina Radio) is getting album covers. A cover belongs to an album, not a song, but
MusicDatabase has no albums — `songs.album` is free text. The user wants:

1. an `albums` table, with songs pointing at their album;
2. room for each song's position on the album (track / disc number);
3. the database ready to hold cover art, and the covers already in the user's mp3 files brought
   in.

Fetching track numbers or covers from the internet (iTunes, Deezer, MusicBrainz) is **not** part
of this task. The phone does that itself for now.

## What's there today (checked 2026-10-11)

`src/database/music.db`:

- `songs(id, title, album VARCHAR, year, language, artist_id, nostalgic, melancholic, party,
  youtube_video_id, spotify_url)`; `artists`; `additional_song_artists`; `schema_version`.
- 5712 songs; 5480 have `album`; 3936 distinct album strings.
- No cover art in the database or anywhere in the repo.
- `album = 'Singles'` (`SINGLES_ALBUM` in `config/constants.py`) is a sentinel, not an album: 405
  songs from 354 artists — singles, and covers/unplugged versions no fetcher found an album for
  (`discoveries_manager.py`).
- 111 album titles have more than one main artist (`songs.artist_id`): real compilations and
  soundtracks (e.g. "Cyberpunk: Edgerunners OST", 8 artists), but possibly also unrelated albums
  that share a name.

The user's music files on an external drive of the server (the folder "Import data from
mp3 tags" is used on):

- 4281 mp3 files, in folders grouped like playlists (not by album).
- **1925 files (45%) have an embedded cover** (ID3 `APIC`, mostly type 3 "front cover"), covering
  1496 of the 2549 distinct (album, artist) tag pairs; 1672 distinct images.
- Sizes: median 81 KB, 90th percentile 342 KB, max 7 MB, 308 MB in total. Mostly square
  (500², 300², 640², 800², 600², 1200²), but some are 16:9 or 4:3 video frames (1280×720 ×89,
  640×480 ×85) — YouTube thumbnails written in by downloaders.
- Messy in places: 41 albums have different images on different tracks (e.g. Madonna "Ray of
  Light", Hey "Karma"); a few files have a YouTube URL as the album tag.
- The `Folder.jpg` / `AlbumArtSmall.jpg` / `AlbumArt_{…}` files (348 jpg) are Windows Media Player
  leftovers, one per folder; the folders are playlists, so these are **not** album covers — ignore
  them.

## Part 1 — schema and album backfill

New migration file(s) under `migrations/music/` (next numbers after `0004_…`), one logical change
per file, plus the matching SQLAlchemy models. Suggested shape — adjust names to the repo's style:

```sql
CREATE TABLE albums (
    id              INTEGER PRIMARY KEY,
    title           VARCHAR NOT NULL,
    artist_id       INTEGER REFERENCES artists(id), -- album artist; NULL = various artists
    year            INTEGER,
    type            VARCHAR CHECK (type IN ('album','ep','single','compilation','soundtrack')),
    -- External ids, so a later fetcher finds covers / track lists without searching again:
    musicbrainz_release_group_id VARCHAR,
    itunes_collection_id         INTEGER,
    deezer_album_id              INTEGER,
    spotify_album_id             VARCHAR
);
CREATE INDEX ix_albums_artist_id ON albums (artist_id);

ALTER TABLE songs ADD COLUMN album_id     INTEGER REFERENCES albums(id);
ALTER TABLE songs ADD COLUMN track_number INTEGER; -- position on the album, NULL = unknown
ALTER TABLE songs ADD COLUMN disc_number  INTEGER; -- NULL = 1 / unknown
CREATE INDEX ix_songs_album_id ON songs (album_id);

CREATE TABLE album_covers (
    album_id   INTEGER NOT NULL REFERENCES albums(id),
    source     VARCHAR NOT NULL,  -- 'file' | 'itunes' | 'deezer' | 'musicbrainz' | 'youtube' | 'manual'
    url        VARCHAR,           -- remote sources; NULL for 'file' and for status 'missing'
    path       VARCHAR,           -- 'file'/'manual': image file relative to the covers directory
    width      INTEGER,
    height     INTEGER,
    bytes      INTEGER,
    status     VARCHAR NOT NULL CHECK (status IN ('found','missing')), -- 'missing' = checked, none
    checked_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (album_id, source)
);
```

**Never store image data in `music.db`**: the phone downloads the whole file, and the covers alone
are ~300 MB. Image files live next to the database (e.g. `<database_dir>/covers/<album_id>.jpg`),
outside git.

Backfill:

- **One main artist for a title** → one `albums` row per (title, `songs.artist_id`), automatically;
  `year` = the songs' most frequent year; set `songs.album_id`.
- **`Singles`** → each song gets its own album row, `type = 'single'`, titled like the song (a
  single has its own cover). The text column keeps "Singles".
- **Several main artists for a title** → don't decide. Leave those songs' `album_id` NULL and add
  an interactive menu action (the user's wish: they settle each case themselves), e.g.
  *Manage database › Resolve albums with several artists*. For each title it shows the songs
  (artist – title, year) and asks:
  - one compilation album (`artist_id` NULL; ask: compilation or soundtrack),
  - separate albums per artist,
  - split into groups by hand (pick songs per album),
  - skip for now.

  It must be resumable (unresolved = `album_id` NULL), so the user can stop and come back. Also
  offer it whenever a later import creates such a case.
- `album IS NULL` → `album_id` NULL.
- `track_number` / `disc_number` stay NULL (filled later by fetchers: iTunes
  `trackNumber`/`discNumber`, Deezer `track_position`/`disk_number`, MusicBrainz).

Keep things in sync from now on: every code path that writes `songs.album` (fill missing albums,
mp3 tag import, manual edits, merges) must also set `album_id` — finding or creating the album
row — ideally through one helper.

### Must keep for the phone app

- **Keep `songs.album` (the text column)** and keep it filled — the app reads
  `SELECT s.album … FROM songs` and breaks without it. Only drop it when the user says the app has
  moved to `album_id`.
- **Album ids must be stable**: the phone will key its cover cache on them. Never renumber or
  rebuild `albums` from scratch; merging two albums keeps one id.

## Part 2 — import covers from the mp3 files

A menu action (next to "Import data from mp3 tags"), run on a folder — default the one above:

- Match each mp3 to its song the same way the tag import does; take its `APIC` (prefer type 3
  "front cover", else the largest).
- Skip images that aren't roughly square (aspect ratio outside ~0.9–1.1: those are video frames);
  record nothing for them, so other sources can fill the album later.
- Per album keep **one** image: the one most of its tracks carry, ties → the larger. When an album's
  tracks disagree (41 such albums today), list them at the end of the run, or ask, rather than
  choosing silently.
- Save it as `covers/<album_id>.jpg`, re-encoded to at most 600×600 (JPEG, quality ~85 — the phone
  never shows more; this turns ~300 MB into roughly 60–80 MB), and write the `album_covers` row
  (`source = 'file'`, `path`, size). Re-running updates, never duplicates.
- Albums with no cover in any file get nothing written (no 'missing' row — the files just didn't
  have one).

Serving the covers to the phone (e.g. `GET /covers/<album_id>.jpg` from `sharing_server.py`) is
a separate step — ask the user before adding it; the phone's "server" cover source is a dummy
until then.

## Done when

- Migrations apply cleanly to a copy of the current `music.db` (backup taken as the runbook says);
  every song with an album text has `album_id`, except the multi-artist titles left for the user.
- The resolver and the cover import work and have tests; existing tests pass.
- MusicDatabase's docs describe the new tables, the covers directory and the two menu actions.
- Tell the user what changed (and how many albums got a cover), so the app's agent can start
  reading `albums` / `album_id`.
- Don't commit or push unless the user asks.
