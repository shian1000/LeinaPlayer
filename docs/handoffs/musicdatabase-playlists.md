# Handoff for the MusicDatabase agent: syncing playlists with the phone

**Status (2026-10-13):** built on both sides. MusicDatabase answered in its
`docs/handoffs/playlists-for-musicdatabaseapp.md` (the final contract; it differs from this one
in details — e.g. a source match answers 409 when the phone's change is older); the phone side is
[ADR 0007](../decisions/0007-playlist-sync.md).

Written by the MusicDatabaseApp agent (2026-10-13) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, ADR-0004 (per-user data) and
`docs/data-model.md` ("References to songs.id from other files") first. Their rules win over
anything here. The sharing server is a contract with the app and partly lives outside the repo,
so record changes in `~/system-docs/README.md` too. Once built, answer with a hand-off of your own
in `docs/handoffs/`, like `inbox-for-musicdatabaseapp.md`: what was built, the final contract,
and anything you changed from this one.

## Why

Users' playlists live in `Users/<name>/user.db` on the server (ADR-0004; so far the owner has
one, "0. Fixed", imported from a folder) and in the phone's own `local.db` (imported from YouTube
and Spotify). The owner wants them to be one set per user. The phone should receive the server's
playlists and send its own, and a user's phones (the owner has two) should see each other's
changes through the server.

## Decisions (the owner's)

1. **The server is the hub.** Every device (the phones and MusicDatabase's own menu) changes
   `user.db`. Devices exchange changes with it, never with each other.
2. **The unit is a whole playlist.** A change sends the playlist with all its tracks. Nothing is
   synced track by track.
3. **Conflicts: the newer change wins.** If the same playlist was changed on two devices between
   syncs, the one with the later `updated_at` (the device's clock when it was changed) stays.
   The same rule applies to a deletion against an edit.
4. **Every playlist of a logged-in user syncs, automatically.** There is no per-playlist switch.
   Before logging in, playlists are phone-only. After a login the phone asks whether to add them
   to the account.
5. **Deleting deletes everywhere** (the server and every phone), so the deletion is kept as a
   marker. **Before deleting, the server copies the playlist to an archive.** No code reads the
   archive (for now); it's there so the owner can recover a playlist by hand. This applies to
   deletions from the menu as well as from the phone.
6. **All playlists are equal.** A playlist made on the server (e.g. from a folder in the menu)
   counts as one made on the phone. The phone may rename, edit, re-order or delete it, like its
   own. The server makes no "read-only" distinction by `source`.
7. Logging out on the phone hides the account's playlists there and logging back in shows them
   again. That's phone-side only; nothing to do here.

## What's needed in `user.db` (a new `migrations/user/` file + `user_datatables.py`)

- `playlists.uid`: a text UUID, unique, created by whoever creates the playlist (phone or menu).
  This is the id both sides use. The integer `id` stays local to each file. Give existing
  playlists one in the migration.
- `playlists.revision`: an integer the **server** sets. Every change to a playlist (its row or
  any of its tracks, from any writer) gives it the next number of a per-user counter, e.g. a
  one-row table like `applied_song_changes`. "Changed since N" is then `revision > N`. This
  includes MusicDatabase's own writes: menu imports, renames and deletions, and
  `song_references.apply_song_id_changes()` changing a track's `song_id` (the phones need the
  new id).
- `playlists.deleted_at`: Unix ms, NULL = live. A deleted playlist keeps its row (with `uid`,
  `revision` and `updated_at`) but loses its tracks. The menu's "Show playlists" and
  `list_playlists()` skip deleted rows.
- `playlists.source_owner`: on the phone, "owner" is the **author** of the YouTube/Spotify
  playlist (shown as "Playlista • <author>"), while `user.db`'s `owner` holds the username. Keep
  `owner` as it is and add `source_owner` for the author. The phone sends and reads only
  `source_owner`.
- `playlists.source` may also be `'spotify'` and `'spotifyAlbum'` (with the Spotify playlist /
  album id in `source_id`), not just `folder` / `youtube`. Add the constants.
- `playlist_tracks.spotify_track_id` (text, NULL): the Spotify track id of a Spotify import.
- `playlist_tracks.youtube_removed` (integer 0/1, default 0): the track's video was removed from
  YouTube, so the phone searches another one.

`updated_at` keeps its meaning (the time of the last change, from the device that made it). It's
what decides conflicts, so the server stores the one sent, not its own clock.

## The archive (decision 5)

Before a playlist's tracks are dropped for deletion, write the whole playlist (the same JSON as
below, with its tracks) to a file. A good place is `Users/<name>/archive/playlists/<uid>.<deleted
at, as in the backup file names>.json`, but choose what fits the existing `archive/` conventions.
Never overwrite an archive file. Nothing reads these files and backups don't need them (they are
already the backup). Mention the folder in the runbook so the owner knows where to look.

## The sharing server: new endpoints (only with `--users`)

All under `/users/<name>/playlists`, plain HTTP on the same port and addresses, JSON bodies with
`Content-Length` (no chunked). Every request needs `Authorization: Bearer <token>`. The `<name>`
in the path must be the token's user: no token or an unknown/revoked one → 401 (the phone asks
to log in again), another user's token → 403. As with the inbox, check the mount first (503).

The server writes `user.db` itself, with the standard library's `sqlite3` (it stays
standard-library only). Use one transaction per request and a `busy_timeout`: the menu or
startup may hold the file at the same moment. If `user.db` hasn't got the migration yet (the
columns above), answer 503 rather than migrating it. Migrations stay MusicDatabase's job at
startup.

### A playlist in JSON

```json
{
  "uid": "8f0c…",
  "revision": 17,
  "name": "0. Fixed",
  "source": "folder",
  "source_id": "/media/…/0. Fixed",
  "source_owner": null,
  "created_at": 1791839796631,
  "updated_at": 1791839796631,
  "deleted": false,
  "tracks": [
    {"song_id": 1234, "title": "…", "artist": "…", "youtube_video_id": "…",
     "spotify_track_id": null, "youtube_removed": false, "duration_s": 215}
  ]
}
```

Track order is the array order (`position` = index). A deleted playlist is
`{"uid", "revision", "updated_at", "deleted": true}` with no tracks.

### `GET /users/<name>/playlists?since=<revision>`

- 200 `{"revision": <the user's current counter>, "playlists": [<every playlist with revision >
  since, deleted ones included>]}`. `since` defaults to 0 (everything).
- The phone stores `revision` and asks with it next time.

### `PUT /users/<name>/playlists/<uid>`

The body is a playlist (without `revision` and `deleted`) plus `"base_revision"`: the revision
the phone last saw, or 0 for a playlist the server has never had.

- `<uid>` unknown → create it. **Except:** if a live playlist of this user already has the same
  `source` + `source_id` (non-NULL; two phones imported the same YouTube/Spotify playlist before
  syncing), update that one instead of making a duplicate. The answer then carries the existing
  `uid` and the phone adopts it.
- `base_revision` equal to the stored revision → apply it.
- `base_revision` older (someone else changed it meanwhile, maybe deleted it) → decision 3:
  the body's `updated_at` later than the stored one → apply it (this may bring a deleted
  playlist back). Otherwise → 409 with the stored playlist; the phone takes that.
- Applied → 200 with the stored playlist as it now is (new `revision`, possibly another `uid`,
  song ids resolved as below). The phone saves exactly that.
- 400 bad JSON / missing fields, 413 body too big (a playlist may have up to 5000 tracks, so
  allow a few MiB), 411 no `Content-Length`.
- A resend after a lost answer must be harmless. The resend comes with the old `base_revision`
  and the same `updated_at`, which isn't later, so it gets a 409 with the playlist that already
  matches what was sent. That's fine for the phone.

### `DELETE /users/<name>/playlists/<uid>?base_revision=<n>&deleted_at=<unix ms>`

- Same conflict rule as `PUT`, with `deleted_at` acting as `updated_at`. If it wins: archive it
  (above), drop its tracks, set `deleted_at`, `updated_at` = `deleted_at`, and give it a new
  revision → 200 with the deleted form. If it loses → 409 with the stored playlist.
- Unknown `uid` or already deleted → 200 with the deleted form (or a made-up one with
  `revision` 0 for an unknown uid). The phone only needs to know it's gone.

## Song ids from a phone with an older `music.db`

A track's `song_id` comes from the phone's copy of `music.db`, which may be days old. If that id
has since been merged or deleted, `user.db` has already replayed that change (its cursor in
`applied_song_changes` is past it), so the old id would stay forever. Ids are never reused, so
the fix is safe: before storing tracks, run every incoming `song_id` through `music.db`'s
`song_id_changes` (following chains: merged → its kept song, deleted → NULL with the
title/artist kept). The server is standard-library only and reads the shared copy in `--dir`,
which may lag the original by up to a day. Decide how to close that gap, e.g. also re-check
those ids at the next `apply_song_id_changes()`, or keep a per-track marker of which log
position its id was checked against. Write down what you chose.

## Not in scope

- Private tags: they'll follow the same pattern later, but not now.
- Track-level merging of two edits: the whole playlist wins or loses (decision 3).
- Anything about the phone (sync timing, the outbox of changes waiting to be sent, hiding on
  logout). The app side will be recorded in the app's ADR 0007 once built.

## Testing

Unit tests for the conflict rules (equal base, stale base newer/older, delete vs edit, resend),
the `source` + `source_id` merge, the archive file being written before deletion, revisions
bumped by menu writes and by `apply_song_id_changes()`, and song id resolution. Server tests
like the existing ones in `tests/` for login/inbox (401/403/409/503). On the real server: a
`curl` round trip with a token for the owner's account (GET, PUT of a test playlist, DELETE, then check
the archive), and remove the test playlist and its archive file afterwards.
