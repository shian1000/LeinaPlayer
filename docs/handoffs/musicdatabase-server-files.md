# Handoff for the MusicDatabase agent: serving the music library's files to the phone

**Status (2026-10-14):** built on both sides. MusicDatabase answered in its
`docs/handoffs/server-files-for-musicdatabaseapp.md` (the final contract: as asked, no token —
the owner's decision); the phone side is [ADR 0010](../decisions/0010-server-files.md).

Written by the MusicDatabaseApp agent (2026-10-14) for an agent working in `../MusicDatabase`.
First read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, and the docstrings of
`src/utils/database/sharing_server.py`, `sharing.py` and `files_index.py`. Their rules win over
anything here. The sharing server is a contract with the app and partly lives outside the repo
(the systemd unit), so also record your changes in `~/system-docs/README.md`. When it's built,
answer with your own hand-off in `docs/handoffs/` (e.g. `server-files-for-musicdatabaseapp.md`):
say what you built, give the final contract, and mark anything you changed from this hand-off
**(changed)** or **(decided)**, as before.

## Why

The owner wants the phone (Leina Radio) to play a song from the music library on the server
when MusicDatabase knows its file. MusicDatabase already knows it: `files.db` maps each audio
file under `Settings.local_library_dir` (a path relative to that folder) to its `songs.id`, and
the sharing server already serves `files.db` with `music.db` and `tag.db`.

The phone now downloads `files.db` too. A song with a file there gets a new source, "Serwer", in
Ustawienia › Odtwarzanie › Kolejność odtwarzania (default order: Telefon, Serwer, YouTube).
What's missing is a way to get the file's bytes. The sharing server serves nothing but the three
databases, so the phone needs one more endpoint.

## What the phone does (already built)

- Reads `files.db` read-only: `SELECT id, path, song_id FROM files WHERE song_id IS NOT NULL`.
  When a song has several files, it uses the largest (`size`). An unmatched file (`song_id`
  NULL) is never asked for.
- Uses the same base address as the database download: the LAN address on the home Wi-Fi, else
  the Tailscale one. On both it first sends **`HEAD /library/<files.id>`** with a 3-second
  connect timeout:
  - 200: it hands **`GET /library/<files.id>`** to the audio player (ExoPlayer through
    `just_audio`). The player streams it and seeks with `Range` requests, often aborting a
    response mid-body when the user seeks or skips.
  - 404: "the file isn't on the server any more". The queue moves on, or the next source in
    the user's order plays the song.
  - 503: "the library isn't available (drive unplugged?)". Same handling as 404.
  - No answer: the next address is tried. With none left, the song counts as "no connection"
    (the queue waits and retries).
- Sends no `Authorization` header. The `files.id` comes from the shared `files.db`, which may
  be up to a day old.

## The endpoint to add

| Call | Answer |
|---|---|
| `HEAD /library/<id>` | the same headers as `GET`, without a body |
| `GET /library/<id>` | 200 with the whole file, or 206 with one range of it |

`<id>` is `files.id` (a positive decimal integer; anything else gets 400 or 404, your choice).

Look it up in **the shared copy** `<dir>/files.db`, the one the phone downloaded, opened
read-only per request (or cached until its mtime changes). Then serve
`<library root>/<files.path>`.

- **Library root:** a new command-line argument, e.g. `--library DIR`. `install_sharing_service()`
  passes `Settings.local_library_dir` when it is a local folder (`files_index.library_root()`
  rules; leave the argument out for an `smb://` library). Without `--library`, every
  `/library/...` request gets 404. The server stays standard-library only and independent of
  `settings.py`, as its docstring requires.
- **Safety:** never serve anything outside the library root. Resolve with `os.path.realpath`
  and check that the result is under the realpath of the root, so neither a `..` in a row nor a
  symlink can escape. Serve only extensions from `LIBRARY_AUDIO_EXTENSIONS`. Copy the tuple
  into the server, because it can't import `config.constants`. Never list directories. Never
  take a path from the request.
- **Answers:**
  - 404: unknown id, a row whose file is gone or changed into something else, or no `--library`.
  - 503: the drive (`--mount`) isn't mounted or the library folder isn't there. This is what
    happens to the databases today.
  - 416: a range that can't be satisfied, with `Content-Range: bytes */<size>`.
- **Headers:** `Content-Type` by extension (`.mp3` gives `audio/mpeg`; if more types appear
  later: `.flac` `audio/flac`, `.m4a` `audio/mp4`, `.ogg`/`.opus` `audio/ogg`). Also
  `Content-Length`, `Accept-Ranges: bytes`, `Last-Modified`, and `Cache-Control: no-cache`.
  A row keeps its id when the file's contents change, so the bytes behind an id can change.
- **Range:** support one range in each form, `bytes=a-b`, `bytes=a-` and `bytes=-n`, answering
  206 with `Content-Range: bytes a-b/size`. A request with several ranges may get a plain 200
  with the whole file. The player always sends a single range.
- **Streaming:**
  - Copy the file in chunks (e.g. 64 KiB), never reading it whole.
  - The player drops connections all the time (seek, skip, crossfade), so treat
    `BrokenPipeError` / `ConnectionResetError` while writing as normal and don't log them as
    errors.
  - `ThreadingHTTPServer` already keeps a long stream from blocking the database downloads or
    logins. Keep it that way.
  - HTTP/1.0 (the current `protocol_version`) is fine. ExoPlayer opens a new connection for
    each range.

### Who may download (please confirm with the owner)

The phone assumes **no token** is needed, the same reach as `music.db` today: anyone on the
tailnet or the home LAN (the owner's 2026-10-10 decision for the databases). If the owner wants
the music files limited to logged-in users, tell the phone side in your answer. That is a
contract change. The phone would then send `Authorization: Bearer <token>` with both calls,
and a 401 would ask the user to log in again (as it does for the inbox).

## Not asked for

- Transcoding, or a lower bitrate for mobile data.
- Covers taken from the files (`CoverSource.server` on the phone is still a dummy; a separate
  hand-off when it's wanted).
- Changes to `files.db` itself or to how it is matched. The phone reads only `id`, `path`,
  `size` and `song_id`. Tell the phone side if any of these change meaning.

## Tests to add on your side

- Range parsing (`a-b`, `a-`, `-n`, past the end → 416, several ranges → 200).
- An id whose `path` escapes the root, through `..` or a symlink: 404 and nothing read.
- A missing file, an unknown id, and `/library/abc`.
- Drive not mounted: 503.
- HEAD sends no body.
- A client that hangs up mid-body leaves the server serving the next request.

Afterwards check it by hand against the running service, e.g.
`curl -sI http://<tailscale ip>:8002/library/<some id>` (200, `audio/mpeg`) and
`curl -s -r 0-99 http://…/library/<id> | wc -c` (100).
