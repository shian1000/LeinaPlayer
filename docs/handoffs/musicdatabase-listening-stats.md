# Handoff for the MusicDatabase agent: listening stats (plays)

**Status (2026-10-16):** built on both sides. MusicDatabase answered in its
`docs/handoffs/listening-stats-for-musicdatabaseapp.md` (contract unchanged; `limit` capped at
1000; `song_id` not remapped on merges); the phone side is
[ADR 0012](../decisions/0012-listening-stats.md).

Written by the MusicDatabaseApp agent (2026-10-16) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, ADR-0004 (per-user data),
`docs/handoffs/playlists-for-musicdatabaseapp.md` and `docs/handoffs/folders-for-musicdatabaseapp.md`
first. Their rules win over anything here. The sharing server is a contract with the app and
partly lives outside the repo, so record changes in `~/system-docs/README.md` too. Once built,
answer with a hand-off of your own in `docs/handoffs/` (e.g.
`listening-stats-for-musicdatabaseapp.md`): what was built, the final contract, and anything you
changed from this one.

## Why

The phone is getting listening stats like Spotify's (top songs, artists and albums over a
period, minutes listened, yearly and seasonal summaries). The owner uses two phones and wants
the listening of both counted together, kept with their MusicDatabase account. The phone
records each song it plays with how long it was really heard ("a play"); MusicDatabase only
stores and hands back the plays — the stats are computed on the phone.

## Decisions (the owner's)

1. **Private to the user**, like playlists: no review, no permission.
2. Plays are only added, or the same play reported again with a longer listened time (the phone
   sends the song still playing, then its final time later). **The longer `listened_ms` wins**;
   nothing else about a play changes. No deletions for now.
3. MusicDatabase's menu doesn't have to show them. A count or "top 10" under Users › (a user) is
   welcome but optional. Using them in MusicDatabase's own features later is up to the owner.

## Storage

A new table in `user.db` — the next user migration, `migrations/user/0009_listens.sql` — e.g.
`listens`: `uid` (unique), the fields below as columns, the rest of the JSON object kept as given
(e.g. an `extra` JSON column — later app versions may add fields), and `revision` with **its own
counter** (e.g. `listen_revision`, like folders' `folder_revision`). The logic fits next to
`folder_sync.py` / `playlist_sync.py` (e.g. `src/utils/database/listen_sync.py`), routes in
`sharing_server.py`. Expect tens of thousands of rows per year: index `revision` (and
`started_at` if you query it).

## The wire

```json
{"uid": "3f2b…", "started_at": 1791839796631, "listened_ms": 183400, "duration_ms": 214000,
 "title": "Gruppa krovi", "artist": "Kino", "album": "Gruppa krovi", "song_id": 1234,
 "youtube_video_id": "abc123", "spotify_track_id": null, "source": "youtube",
 "playlist_uid": "a1c4…", "playlist_name": "Do auta",
 "mood_uid": null, "global_mood_id": 5, "mood_name": "Do biegania"}
```

- `uid`: a UUID made on the phone; 1–64 characters `[A-Za-z0-9-]`.
- `started_at`: ms since the epoch, the phone's clock. `listened_ms`: how long it was heard
  (≥ 0). `duration_ms`: the song's length when known, else null.
- `title` is always there; `artist`, `album` are the names the phone showed, any may be null.
- `song_id`: music.db's `songs.id`, null for songs not in MusicDatabase. **Store as given**, don't
  check that it exists (the phone may have an older or newer music.db).
- `source`: `phone` (a file on the phone), `server` (streamed from `/library/<id>`) or
  `youtube`. Keep unknown values.
- `playlist_uid` / `playlist_name`: the playlist it played from (the user's playlist `uid`, which
  may be phone-only). The mood it played from: `mood_uid` (the user's own mood's `uid`) or
  `global_mood_id` (tag.db's `tags.id`), with `mood_name`. All may be null; store as given.

### Endpoints (all with the login token, like playlists)

- `GET /users/<name>/listens?since=<revision>&limit=<n>` →
  `{"revision": <r>, "listens": [<plays changed after since, by revision, at most n>], "more": <bool>}`.
  With `more: true`, `r` is the revision of the last play listed (the phone asks again from
  there); otherwise it's the current counter. Each play comes with its `revision`. `limit`
  defaults to e.g. 1000, capped at what's sensible (the phone asks for 500).
- `POST /users/<name>/listens` with `{"listens": [<plays>]}` (the phone sends up to 500) →
  200 `{"revision": <the current counter>}`. Each play is stored by `uid`: a new one is added; a
  known one is updated (and its revision bumped) only when its `listened_ms` is larger, and
  `duration_ms` filled in if it was null. A play from another phone with the same uid can't
  happen in practice; treat it the same way.
- Errors as for playlists and folders: 401 (bad token — the phone asks to log in again), 403
  (another user's path), 503 (drive missing or the user's `user.db` without migration 0009 — the
  phone waits), 400 for a bad body (e.g. a play without `uid` or `title`, `listened_ms` not an
  integer ≥ 0), 411 without `Content-Length`, 413 over the body limit. 500 plays are ~250 KB of
  JSON, so folders' 1 MiB limit is enough. A batch is all or nothing: one bad play → 400 for the
  whole request, nothing stored (the phone sends the same batch again later). Until this exists the phone gets 404 and
  waits.

## Tests

Cover at least: a POST then GET from revision 0 and from a later revision; a repeated POST with a
longer time updating the play (and its revision), with a shorter one leaving it as it was;
paging with `limit` and `more`; unknown fields and `source` values kept.
