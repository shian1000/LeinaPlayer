# Handoff for the MusicDatabase agent: Biblioteka folders

**Status (2026-10-16):** built on both sides. MusicDatabase answered in its
`docs/handoffs/folders-for-musicdatabaseapp.md` (contract unchanged; also rewrites refs on
merges); the phone side is [ADR 0011](../decisions/0011-folder-sync.md).

Written by the MusicDatabaseApp agent (2026-10-16) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, ADR-0004 (per-user data),
`docs/handoffs/playlists-for-musicdatabaseapp.md` and `docs/handoffs/moods-for-musicdatabaseapp.md`
first. Their rules win over anything here. The sharing server is a contract with the app and
partly lives outside the repo, so record changes in `~/system-docs/README.md` too. Once built,
answer with a hand-off of your own in `docs/handoffs/` (like
`playlists-for-musicdatabaseapp.md`): what was built, the final contract, and anything you
changed from this one.

## Why

The phone's Biblioteka has **folders** holding playlists and moods. They lived only on the
phone. The owner uses two phones and wants the same folders on both, synced through their
MusicDatabase account like playlists and moods. Only the folders: the phone's sort order and
"recently opened" stay on each phone.

## Decisions (the owner's)

1. **Same rules as playlists**: the server is the hub; the unit is a whole folder (its name and
   items); the newer `updated_at` wins; a deletion is kept as a marker and deletes the folder on
   every phone of the account.
2. **Private to the user**, like playlists: no review, no permission.
3. Folders don't nest. An item is in one folder at most (the phone enforces this; the server
   needn't).
4. MusicDatabase's menu doesn't have to show or edit folders. Showing them under Users › (a
   user) is welcome but optional.

## Storage

A new table in `user.db` (a new `migrations/user/` file), e.g. `folders`: `uid` (unique),
`name`, `items` (JSON, see below), `created_at`, `updated_at`, `deleted_at`, `revision`. The
revision counter can be the playlists' one or its own; your call. Archiving a deleted folder is
not needed: it holds no songs, only references.

## The wire

```json
{"uid": "3f2b…", "revision": 12, "name": "Do auta", "created_at": 1791839796631,
 "updated_at": 1791839796631, "deleted": false,
 "items": [{"type": "playlist", "uid": "a1c4…"},
           {"type": "mood", "uid": "77de…"},
           {"type": "global_mood", "id": 5}]}
```

- `uid`: any string of 1–64 characters `[A-Za-z0-9-]`. New folders send a UUID; folders made on
  the phone before syncing keep a short base-36 id. Don't require the UUID format.
- `items`, in the user's order. `playlist` and `mood` name the user's own playlist / mood by its
  `uid`; `global_mood` names a tag.db mood by its `tags.id`.
- **Store items as given, without checking that they exist.** A folder may name a playlist only
  on that phone (never synced), or one the other phone hasn't received yet; the phone keeps
  such refs and sends them back. Unknown `type`s should be kept too, for later app versions.
- The deleted form: `{"uid", "revision", "deleted": true}`.

### Endpoints (all with the login token, like playlists)

- `GET /users/<name>/folders?since=<revision>` →
  `{"revision": <the current counter>, "folders": [<every folder, deleted ones too, changed after since>]}`
- `PUT /users/<name>/folders/<uid>` with the folder and `base_revision` (0 for a new one) →
  200 with the stored folder; 409 with the stored folder when it changed since `base_revision`
  and the stored `updated_at` is newer or equal (the phone then takes the stored one). A PUT
  for a folder deleted on the server with an older `deleted_at` brings it back.
- `DELETE /users/<name>/folders/<uid>?base_revision=&deleted_at=` → 200 with the deleted form;
  or the stored folder (409) when it was changed elsewhere after `deleted_at`.
- The same error codes as playlists: 401 (bad token — the phone asks to log in again), 403
  (another user's path), 503 (drive missing or the user's `user.db` not migrated — the phone
  waits), 400/413 for a bad body. Until this exists the phone gets 404 and waits.

## Keeping refs right (nice to have)

When the server merges a playlist into another (the same `source` + `source_id` imported on two
phones) or a mood into one of the same name, the folder refs naming the dropped `uid` become
stale. The phone heals this itself: it sees the playlist's new `uid` and sends the folder again.
If it's cheap, rewrite the refs in the user's folders at merge time (and bump their revision)
as well.

## Tests

Cover at least: a PUT then GET from another revision; 409 for an older change; a delete marker
reaching `since`; items kept verbatim, including unknown refs and unknown types.
