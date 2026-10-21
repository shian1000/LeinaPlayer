# Handoff for the MusicDatabase agent: covers of playlists and moods

**Status (2026-10-13):** built on both sides. MusicDatabase answered in its
`docs/handoffs/covers-for-musicdatabaseapp.md` (the final contract); the phone side is
[ADR 0009](../decisions/0009-cover-sync.md).

Written by the MusicDatabaseApp agent (2026-10-13) for an agent working in `../MusicDatabase`.
First read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md`
(`user.db`), ADR-0004 (per-user data), and your hand-offs `playlists-for-musicdatabaseapp.md`
and `moods-for-musicdatabaseapp.md`. Their rules win over anything here. The sharing server is
a contract with the app and partly lives outside the repo, so also record your changes in
`~/system-docs/README.md`. When it's built, answer with your own hand-off in `docs/handoffs/`
(e.g. `covers-for-musicdatabaseapp.md`). Say what you built, give the final contract, and mark
anything you changed from this hand-off **(changed)** or **(decided)**, as before.

## Why

On the phone, a playlist or mood (Nastrój) can now have a cover the user picked from their
photos ("Dodaj okładkę"). If it has none, the phone shows a 2×2 collage of its songs' album
covers. Right now the picked cover stays on the phone where it was set. The owner wants it to
sync with the user's MusicDatabase account, the same way the playlists and moods themselves do.
That way both phones show the same cover.

## Decisions (the owner's)

1. **A cover is part of the playlist or mood.** Setting, changing or removing it is a change to
   the playlist or mood, like renaming it. The existing sync rules apply unchanged: the server
   is the hub, the newer `updated_at` wins, and deleting the playlist deletes it everywhere
   (archived first).
2. **Global moods get a private cover per user.** A user may give a global mood (from `tag.db`)
   a cover of their own. It is stored in *their* `user.db` and syncs only between *their*
   phones. Nobody else sees it, and `tag.db` doesn't change. No permission is needed.
3. **MusicDatabase only stores the covers.** It keeps them, serves them, and archives them along
   with deleted playlists and moods. The terminal menu needs no way to set covers. At most it
   shows that a playlist or mood has one, for example "okładka: tak".
4. A phone that's logged out keeps its covers on the phone only, as it does with playlists. They
   go to the account together with the playlist when the user adds phone-only playlists after
   logging in.

## The image itself: content-addressed blobs

Pictures are too big to resend in the playlist JSON on every sync. Today a playlist is sent
whole every time a track changes, and a cover is up to about 1 MB. So the JSON carries only the
image's hash, and the image goes through its own endpoint, addressed by that hash:

| Call | Success | Notes |
|---|---|---|
| `PUT /users/<name>/covers/<sha256>` | 201 created, or 200 if already stored | body = the image bytes; `Content-Type` `image/png` or `image/jpeg`; `Content-Length` required |
| `GET /users/<name>/covers/<sha256>` | 200 the bytes with their `Content-Type` | 404 if the user has no such blob |

- `<sha256>` is the lowercase hex SHA-256 of the exact bytes (64 characters). The server
  recomputes it and answers **400** if it doesn't match the bytes. Uploading the same blob
  twice is harmless (200), so the phone can simply retry.
- The phone sends a square PNG of at most 660×660, usually 0.2–1 MB. Allow up to **4 MiB**
  (**413** above that). Answer **415** for any other type, or when the bytes don't start with
  a PNG/JPEG signature. Checking the signature is enough. Don't decode the image.
- Auth and codes as for playlists: `Authorization: Bearer <token>`, `<name>` must be the token's
  user (otherwise 403), 401, 411, and 503 when the data drive isn't mounted.
- Store the files outside `user.db`. Binary data doesn't belong in SQLite here. For example:
  `Users/<name>/covers/<sha256>.png|.jpg`.
- The responses may be cached forever (`Cache-Control: immutable`): a hash never changes its
  content.

## In the playlist and mood JSON

Add one field to both `/users/<name>/playlists` and `/users/<name>/moods`, in GET answers, PUT
bodies and PUT/409 answers:

```json
{"uid": "…", "revision": 18, "name": "Siłownia", …, "cover": "9f86d081…0f00a08"}
```

- `"cover"`: the sha256 of a blob of this user, or `null` when there's no cover.
- **A PUT without the `cover` key keeps the stored cover.** A phone with an older app version
  must not wipe covers when it edits a playlist. `null` explicitly removes the cover.
- A PUT naming a hash the user has no blob for → **400**
  `{"error": "cover_missing", "cover": "<sha256>"}`. The phone always uploads the blob first, so
  this means a bug or a lost upload, and the phone will upload again and retry.
- Answers always include `cover`, `null` included. The deleted form doesn't need it.
- Store it as a column (`cover_sha256`) on the playlist row and on the mood's `tags` row in
  `user.db` (a new `migrations/user/` file). Like the earlier migrations: until a user's
  `user.db` has it, answer 503.
- **Merges.** Two cases:
  - The same `source` + `source_id` imported on two phones, or the same mood name made on two
    phones: the merged result keeps the cover of the side with the newer `updated_at`. If that
    side has none, it keeps the other side's.
  - **Promotion** of a user mood to a global one: the user mood's cover becomes that user's
    private cover of the global mood (decision 2, below), so the user still sees their picture.

## Private covers of global moods (decision 2)

Global moods aren't in the user's playlists or moods, so their covers need their own small
collection. It follows the same sync pattern. The key is the global mood's `tags.id` from
`tag.db`. The phone knows it because it reads `tag.db`.

| Call | Success |
|---|---|
| `GET /users/<name>/global-mood-covers?since=<revision>` | 200 `{"revision": <counter>, "covers": [...]}`, every row with `revision > since`, ordered by revision |
| `PUT /users/<name>/global-mood-covers/<mood_id>` | 200 the stored row; **409** the stored row when it won |

```json
{"mood_id": 12, "revision": 31, "cover": "9f86d081…" , "updated_at": 1791839796631}
```

- PUT body: `base_revision` (required, integer ≥ 0), `updated_at` (required), `cover` (sha256
  or `null`; required here). Conflict rule as for playlists: if the row changed since
  `base_revision`, the newer `updated_at` wins and the loser gets 409 with the stored row.
- Removing is `cover: null`. Keep the row with its new revision so the other phone learns about
  the removal. No DELETE is needed.
- Use the same per-user revision counter as playlists/moods or a separate one. That's your
  call; the answer carries the counter either way.
- Accept any `mood_id` ≥ 1, even one that's not (or no longer) in `tag.db`. A phone may have an
  older or newer `tag.db` than the server. Rows for global moods that are gone are harmless.
  The menu may ignore them.
- Same `cover_missing` 400 as above.

## Keeping and removing blobs

- A blob stays while any of the user's playlists, moods or global-mood-cover rows refers to it.
- **Archiving.** When a playlist or mood is deleted (its JSON goes to
  `Users/<name>/archive/…/<uid>.<YYMMDD-HHMM>.json`), copy its cover blob next to it, e.g. into
  `Users/<name>/archive/covers/`. The archived JSON then still shows the picture.
- **Clean-up.** Remove blobs that nothing refers to, but only after they've been unreferenced
  for **at least 24 hours**, counted from the file's mtime. The phone uploads the blob *before*
  the PUT that refers to it, and a clean-up between the two must not delete it. When to run
  the clean-up is your call (at server start, after a sync, in the menu's maintenance).

## What the phone will do (for context, not your work)

- Before a PUT of a playlist or mood with a new cover, it uploads the blob. On
  `cover_missing` it uploads again and retries once.
- When a GET or 409 brings a `cover` hash it doesn't have, it downloads the blob.
- A changed cover marks the playlist or mood as changed and bumps its `updated_at`, so it
  syncs like a rename.

## Not in scope

- Setting covers from the MusicDatabase menu (decision 3).
- Shared covers of global moods for everyone (decision 2: they're private).
- Album covers. Those are a separate topic (`musicdatabase-albums-and-covers.md`).

## Testing

Unit tests for:

- blob PUT/GET: hash mismatch → 400, wrong type or bad signature → 415, over 4 MiB → 413,
  re-upload → 200, another user's token → 403;
- `cover` in playlist and mood PUTs: kept when the key is missing, removed by `null`,
  `cover_missing`, and the merge rules (same import / same mood name, promotion);
- the global-mood-covers collection: conflict with 409, removal by `null`, `since`;
- archiving a deleted playlist's or mood's blob, and the clean-up's 24-hour grace period;
- the `user.db` migration, and 503 before it has run.

Server tests like the existing playlist and mood ones. On the real server: a `curl` round trip
with a token for the owner's account (upload a small PNG, set it on a test playlist, read it back, delete
the playlist, check the archive). Afterwards remove the test playlist, its archive files, the
blob and the token.
