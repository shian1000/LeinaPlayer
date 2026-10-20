# Handoff for the MusicDatabase agent: liked songs, "Na później" songs and links

**Status (2026-10-21):** the phone side is built ([ADR 0013](../decisions/0013-saved-songs-sync.md));
waiting for MusicDatabase. Until then the phone gets 404 and waits.

Written by the MusicDatabaseApp agent (2026-10-21) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, ADR-0004 (per-user data) and
`docs/handoffs/folders-for-musicdatabaseapp.md` first — this is the same contract for two more
collections, and their rules win over anything here. The sharing server is a contract with the
app and partly lives outside the repo, so record changes in `~/system-docs/README.md` too. Once
built, answer with a hand-off of your own in `docs/handoffs/` (like
`folders-for-musicdatabaseapp.md`): what was built, the final contract, and anything you changed
from this one.

## Why

Three lists on the phone were kept only there: liked songs ("Polubione utwory"), songs saved
"Na później", and links people sent, saved "Na później" from the app's link sheet. The owner
reinstalled the app and lost them, while everything synced with the account came back. The app
is going to two friends; these lists have to sync with the MusicDatabase account like playlists
and folders.

## Decisions (the owner's)

1. **Same rules as folders**: the server is the hub; the newer `updated_at` wins; a deletion is
   kept as a marker and deletes the item on every phone of the account; a PUT newer than the
   deletion brings it back.
2. **One item = one song on one list / one link**, not a whole list.
3. **Private to the user**, no review, no permission. MusicDatabase's menu needn't show them.

## Storage

Two new tables in `user.db` (a new `migrations/user/` file), e.g. `saved_songs` and
`later_links`: `uid` (unique), the fields below (a JSON column is fine — store them verbatim),
`updated_at`, `deleted_at`, `revision`. The revision counter is your call (the folders have
their own).

## `saved-songs`

```json
{"uid": "3f2b0c…(40 hex)", "revision": 12, "list": "liked",
 "added_at": 1791839796631, "updated_at": 1791839796631, "deleted": false,
 "song": {"song_id": 1234, "title": "Группа крови", "artist": "Кино",
          "video_id": "abcdefghijk", "playlist_video_id": "…", "spotify_track_id": "…"}}
```

- `uid`: 1–64 characters `[A-Za-z0-9-]` (the phone sends 40 hex characters: a hash of the list
  and the song, so the same song liked on two phones is the same item).
- `list`: `liked` or `later`. Keep unknown values as given.
- `song`: everything but `title` may be missing. `song_id` is a music.db `songs.id` (the phone
  maps merged ids before sending). **Store `song` verbatim, without checking the song exists**:
  it may be a YouTube video or a Spotify track MusicDatabase doesn't have. If it's cheap,
  rewrite `song_id` when songs are merged (like playlist tracks); the phone copes anyway.
- `added_at`: the list's order (newest first). Saving a song again on top is a PUT with a newer
  `added_at` and `updated_at`.

## `later-links`

```json
{"uid": "a1c4…(UUID)", "revision": 3, "url": "https://youtu.be/abcdefghijk",
 "service": "youtube", "kind": "Film z YouTube", "person": "Ola",
 "saved_at": 1791839796631, "opened_at": null, "title": "…", "artist": "…",
 "updated_at": 1791839796631, "deleted": false}
```

- `service`: `youtube` or `spotify`; `kind` a Polish label; `person` the sender's name (people
  themselves aren't synced); `opened_at`, `title`, `artist` may be null.
- Don't fetch or check the URL.

## Endpoints (both collections; all with the login token, like folders)

- `GET /users/<name>/saved-songs?since=<revision>` →
  `{"revision": <the current counter>, "songs": [<every item, deleted ones too, changed after since>]}`;
  `GET /users/<name>/later-links?since=` → `{"revision", "links": [...]}`.
- `PUT /users/<name>/<collection>/<uid>` with the item and `base_revision` (0 for a new one) →
  200 with the stored item; 409 with the stored item when it changed since `base_revision` and
  the stored `updated_at` (or `deleted_at`) is newer or equal. **A PUT with `base_revision` 0
  for a uid that already exists is normal** (the same song liked on another phone; a list
  uploaded again after a reinstall) — the same rule decides.
- `DELETE /users/<name>/<collection>/<uid>?base_revision=&deleted_at=` → 200 with the deleted
  form `{"uid", "revision", "deleted": true}`; 409 with the stored item when it was changed
  elsewhere after `deleted_at`. A DELETE of a uid you never had: store the marker, 200.
- The same error codes as folders: 401 (bad token — the phone asks to log in again), 403
  (another user's path), 503 (drive missing or `user.db` not migrated — the phone waits),
  400/413 for a bad body.

## Size

A user may have a few thousand liked songs; the first sync after a reinstall PUTs none of them
(the phone fetches with `since=0` first), but a phone with a long list made before syncing
existed PUTs them one by one, once. No batch endpoint needed.

## Tests

Cover at least: a PUT then GET from another revision; `base_revision` 0 on an existing uid
(newer wins, older gets 409); 409 for an older change; a delete marker reaching `since`; a newer
PUT reviving a deleted item; `song` and unknown fields kept verbatim.
