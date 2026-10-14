# 0010 - Playing songs from the server's music library

## Status

Accepted (2026-10-14), the owner's request: "play songs from the server when the database has a
path to them". Built on both sides: asked for in
[`../handoffs/musicdatabase-server-files.md`](../handoffs/musicdatabase-server-files.md),
MusicDatabase's answer (the final contract) is its `docs/handoffs/server-files-for-musicdatabaseapp.md`
— implemented as asked; no token (the owner's decision), 404 for anything that isn't a valid id.

Checked against the real server (2026-10-14, Huawei on the home LAN): "Going to California"
played from `/library/2`. Before the endpoint existed, its 404 made the song play from YouTube
instead. Tests: `server_playback_test.dart`, `song_catalog_test.dart`, `database_sync_test.dart`.

## Context

MusicDatabase indexes the audio files of its music library in `files.db` (path relative to the
library folder → `songs.id`; its `files_index.py`). The sharing server already serves `files.db`
with `music.db` and `tag.db`, but not the files themselves.

## Decision

- `files.db` is downloaded with the other two (`DatabaseSync.optionalFileNames`: an older server's
  404 doesn't fail the download, and a copy left from before is removed).
- `SongCatalog` reads it into `CatalogSong.serverFile` (`ServerFile`: `files.id` + path; the
  largest file when a song has several). Songs only — a file `files.db` didn't match to a song
  isn't offered.
- A new `PlaybackSource.server` ("Serwer"), by default between Telefon and YouTube; added to a
  saved order right after Telefon (`SourceSettings._withAll` puts a new value after the one it
  follows by default).
- The file is streamed from `GET /library/<files.id>` on the same addresses as the database
  download (`DatabaseSync.serverAddresses`, home LAN first). A `HEAD` first, with short
  timeouts, tells "no connection" (the queue waits and retries) from "not on the server" (404 /
  503: the queue moves on) and passes over an unreachable address quickly.
- When the server can't play it, the next source in the user's order does (`TrackPlayer`), so a
  song with both a server file and a YouTube link still plays away from home without Tailscale.
- No caching ahead for server files (they stream like phone files play), no token (the
  databases need none either; the owner confirmed it for the files).

## Consequences

- Playing from the server needs the server reachable; over mobile data via Tailscale it uses
  data like YouTube does (no data-saver switch for it yet).
- `files.db` is up to a day old: a file moved since is a 404 until the next download.
- The song row's database icon becomes a server icon (`Icons.dns`) for songs with a server file;
  "Informacje o utworze" shows the file's path. `NowPlaying.serverFileId` marks the playing row
  (like `youtubeVideoId`).
