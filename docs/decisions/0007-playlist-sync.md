# 0007 - Syncing Biblioteka playlists with the MusicDatabase account

## Status

Accepted (2026-10-13). Built on both sides: MusicDatabase's sharing server serves
`/users/<name>/playlists` (its `playlist_sync.py`, `sharing_server.py`; contract in its
`docs/handoffs/playlists-for-musicdatabaseapp.md`), asked for in
[`../handoffs/musicdatabase-playlists.md`](../handoffs/musicdatabase-playlists.md).

Checked against the real server (2026-10-13, Huawei and Pixel 7a): receiving ("0. Fixed" from
MusicDatabase's menu), sending a phone playlist, deleting. Not yet checked by hand, only by
tests (`test/data/playlist_sync_test.dart`): a conflict (the same playlist changed on two phones
before syncing) and logging out / back in hiding and showing the account's playlists.

## Context

Playlists lived only in the phone's `local.db` (imported from YouTube / Spotify). MusicDatabase
keeps per-user playlists in `Users/<name>/user.db` (its ADR-0004), so far made from music folders
in its menu. The owner has two phones and wants one set of playlists per user. Private data needs
no review (unlike the outbox, [ADR 0005](0005-outbox-for-musicdatabase.md)); the login exists
([ADR 0006](0006-musicdatabase-login.md)).

## Decision (the owner's)

- **The server is the hub**; devices only talk to it. **The unit is a whole playlist** (name,
  source, all tracks). JSON over the sharing server, signed with the login token: `GET
  …/playlists?since=<revision>`, `PUT …/playlists/<uid>` (with `base_revision`), `DELETE
  …/playlists/<uid>?base_revision&deleted_at` — an exchange with conflict checks, not a file
  download, so not SQLite files like ADR 0002/0005.
- **Newer change wins**: when both sides changed a playlist since the last sync, the later
  `updated_at` (the device's clock at the change) stays — also deletion against edit.
- **Every playlist of a logged-in user syncs**, automatically: on start, on return to the app,
  a few seconds after a change, and with ⟳ in Konto. Playlists made while logged out are
  phone-only; after logging in the phone asks whether to add them to the account, and Konto
  offers it as long as any are left (a phone logged in before this existed was never asked).
- **Deleting deletes everywhere**; MusicDatabase archives a copy first.
- **All playlists are equal**: one made in MusicDatabase (e.g. `source` `folder`) can be changed
  or deleted on the phone like its own.
- **Logging out hides the account's playlists** (kept in `local.db`, with any unsent change) and
  logging in again shows them.

## On the phone (`playlist_library.dart`, `playlist_sync.dart`, `local.db` v11)

- `playlists` got `uid` (UUID, the id shared with MusicDatabase), `account` (NULL = phone-only),
  `revision` (the server's, last seen), `dirty` (a change waiting to be sent) and `deleted_at` (a
  deletion waiting to be sent — the row stays without tracks). The integer `id` stays local: the
  queue and history refer to it, so a synced playlist is updated in place, never re-inserted.
- The last counter per user is `playlists.sync_revision.<user>` in `shared_preferences`.
- A sync: GET (rows with a change waiting are skipped — sending them settles it), then DELETEs
  (before PUTs, so a re-import isn't merged into a playlist about to be deleted), then PUTs. Both
  200 and 409 carry the stored playlist, which replaces the phone's (possibly under another
  `uid`: MusicDatabase merges the same `source` + `source_id` imported on two phones). A
  playlist changed again while its PUT was on the way only takes the answer's revision.
- `owner` on the phone (the YouTube/Spotify author) is `source_owner` on the wire; MusicDatabase's
  own `owner` (the username) isn't sent.
- `YouTubeLibrary.markVideoRemoved` / `clearVideosRemoved` mark the account playlists with that
  video as changed (`youtube_removed` is synced), without touching `updated_at`.
- 401 → log in again (like the outbox); 503 (drive, or that user's `user.db` not migrated yet)
  stops until the next try; a refused playlist (400/403/413) stays waiting.

## Consequences

- Conflicts depend on the phones' clocks; fine for one household.
- A song id from an older `music.db` is resolved by MusicDatabase (merged → kept song, deleted
  → NULL with title/artist kept); the phone takes the answer.
- Private tags will follow the same pattern later.
