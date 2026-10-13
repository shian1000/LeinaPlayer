# Handoff for the MusicDatabase agent: Nastroje (moods)

**Status (2026-10-13):** built on both sides. MusicDatabase answered in its
`docs/handoffs/moods-for-musicdatabaseapp.md` (the final contract; the same permission also
removes songs from global moods); the phone side is [ADR 0008](../decisions/0008-moods.md).

Written by the MusicDatabaseApp agent (2026-10-13) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md` (`tag.db`,
`user.db`, "References to songs.id from other files"), ADR-0004 (per-user data) and
`docs/handoffs/playlists-for-musicdatabaseapp.md` first. Their rules win over anything here.
The sharing server is a contract with the app and partly lives outside the repo, so record
changes in `~/system-docs/README.md` too. Once built, answer with a hand-off of your own in
`docs/handoffs/` (like `playlists-for-musicdatabaseapp.md`): what was built, the final contract,
and anything you changed from this one.

## Why

The owner wants **Nastroje** ("moods"): sets of songs with the same feel, e.g. music for
exercise or for chilling. A song may be in many moods. A mood has no order, so it's not a
playlist. The phone will play a mood (shuffled) and let the user add songs to moods.

There are two kinds:

- **Global moods.** Every user sees them.
- **User moods.** Only the user who made them sees them, plus the owner in MusicDatabase.

They are built on the existing tags. Global moods are tags in `tag.db`. A user's moods are the
private tags in their `user.db` (user migration 0002, unused so far).

## Decisions (the owner's)

1. **Only songs in `music.db` can be in a mood.** Every member is a `songs.id`. There is no
   title/artist fallback like playlist tracks have. The phone only offers "Dodaj do nastroju" for
   songs it knows from `music.db`.
2. **In MusicDatabase the owner can see every user's moods without logging in as that user.**
   The terminal menu reads `Users/<name>/user.db` directly.
3. **A user mood can be promoted to a global one** (MusicDatabase menu, owner only). Promoting
   **moves** it: its songs go into a global mood and the user's mood is deleted. The user then
   sees the global one. If a global mood with the same name already exists, the two are
   **merged**: the global mood gets the union of the songs.
4. **Users create their own moods and add songs to them.** This is private data, so it needs no
   review, like playlists.
5. **Some users may also edit global moods** by adding songs to them from the phone. That takes
   a permission the owner grants. The phone shows the option only to users who have it. Nothing
   goes through the review inbox: the permission is the trust.
6. **A permissions menu in MusicDatabase.** Main menu › Users gets a place where the owner
   grants and revokes permissions per user. Mood editing is the first permission. Build it so
   more permissions can be added later.
7. In the phone's UI a mood is called **"Nastrój"** (plural "Nastroje"). The code and the wire
   may say `mood`.

## Telling moods from other tags

`tag.db` holds only technical markers today: `spellchecked` and `album_checked`, about 5,700
songs each. Those must never show up as moods. Add a `kind` column to `tags`, both in `tag.db`
(a new `migrations/tag/` file) and in `user.db` (a new `migrations/user/` file):

- `'mood'` marks a mood.
- Everything else, including all existing rows, is `'marker'` or whatever name you choose.
  Later kinds (e.g. genre) can be added the same way.

The phone will read only `kind = 'mood'` from `tag.db`.

`tags.name` is unique per file. A global mood and a global marker can't share a name. If a
promotion meets a marker with that name, refuse it with a clear message and don't merge.

## Changing global moods without the owner's review (decision 5)

This is the part that needs real design. Today the sharing server serves only a **copy** of
`tag.db`. The copy is refreshed about once a day (`sharing.py`), and the original isn't on T7.
A permitted user's change must:

- take effect without the owner accepting it;
- reach the original `tag.db` and, from there, every phone. A delay of up to the next sharing
  copy is acceptable, but say what it is;
- be recorded: who added or removed which song in which mood, and when. It changes shared data
  without review, so the owner should be able to see it and undo it by hand.

The phone shows its own change right away. It keeps the change locally until the downloaded
`tag.db` contains it, the same way it already treats its own findings against `music.db`.

Choose the mechanism with the owner and document it. One option fits the existing setup:

1. The server accepts an authenticated change.
2. It checks the permission against `account.json`.
3. It writes the change to a log file on T7.
4. MusicDatabase applies the log to the original `tag.db` at startup and before each sharing
   copy, then archives it.

Writing the original directly from the server is another option.

**Removing a song from a global mood:** decide with the owner whether the same permission
allows it. The app's agent assumes yes, but this wasn't asked.

Creating, renaming, deleting and promoting global moods happen only in the MusicDatabase menu.

## Permissions

- Store them outside `user.db`, e.g. `"permissions": ["edit_global_moods"]` in `account.json`.
  Permissions say what the owner trusts a user with; they aren't the user's own data.
- The phone needs to read them. Return them from `POST /login`
  (`{"username", "token", "permissions": [...]}`), and also from an authenticated call the phone
  can repeat, e.g. `GET /users/<name>` → `{"username", "permissions": [...]}`. A revoked
  permission must disappear from the phone without logging in again.
- Every endpoint that writes global moods checks the permission itself. If it's missing, answer
  403 with a body the phone can tell apart from "another user's token", e.g.
  `{"error": "permission", "permission": "edit_global_moods"}`.

## Syncing user moods with the phone

Follow the playlist pattern exactly:

- The server is the hub.
- The unit is a whole mood: its name and all its song ids.
- The newer `updated_at` wins.
- A deletion is kept as a marker and deletes the mood everywhere.
- Archive a copy before deleting.

In `user.db`, a mood is a `tags` row with `kind = 'mood'`. It needs the same sync columns as
playlists: `uid`, `revision` (from the same per-user counter or its own; your call),
`created_at`, `updated_at` and `deleted_at`.

```json
{"uid": "…", "revision": 5, "name": "Siłownia", "created_at": 1791839796631,
 "updated_at": 1791839796631, "deleted": false, "song_ids": [1234, 4601]}
```

- `GET /users/<name>/moods?since=<revision>`
- `PUT /users/<name>/moods/<uid>` with `base_revision`
- `DELETE /users/<name>/moods/<uid>?base_revision=&deleted_at=`

These use the same codes as playlists: 401, 403, 409 with the stored mood, 503, and so on. Two
details differ:

- **Duplicate names.** Two phones may each create "Siłownia" before syncing, but `tags.name` is
  unique per file. Merge them the way playlists merge on `source` + `source_id`: union the songs
  and return the existing `uid`. The phone adopts it.
- **Promotion (decision 3).** The user's mood becomes a deletion. Add
  `"promoted_to": "<global mood name>"` (or its id) to the deleted form, so the phone can say
  "przeniesiony do globalnych" and switch to the global mood instead of just making it vanish.

Song ids from a phone with an older `music.db` are resolved through `song_id_changes` as they
are for playlists. A song deleted from `music.db` simply leaves the mood (decision 1).

## The menu (owner only)

- Users › (a user) › show their moods and each mood's songs. Users › permissions (decision 6).
- Global moods: list them, create, rename, delete, and add or remove songs. The existing tag
  helpers in `tags_management.py` may be reusable.
- Promote a user's mood to a global one (decision 3), with the merge and the marker-name refusal
  described above.
- The log of permitted users' global changes from the section above.

## Not in scope

- Anything about the phone. The app records its side in its own ADR once built.
- Suggesting songs for a mood automatically.
- Users seeing other users' moods. Only global moods and their own.

## Testing

Unit tests for:

- `kind` filtering: markers never listed as moods;
- promotion: move, merge with an existing global mood, refusal on a marker name, the deletion
  marker with `promoted_to`;
- the mood sync conflict rules and the duplicate-name merge;
- song id resolution;
- the permission checks: granted, revoked, missing → 403 with the permission body;
- applying permitted users' global changes, and their log.

Server tests like the existing login/inbox/playlist ones. On the real server: a `curl` round
trip with a token for `owner`, then remove the test mood, any test global change and any
granted test permission afterwards.
