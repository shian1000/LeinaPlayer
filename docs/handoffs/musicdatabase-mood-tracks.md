# Handoff for the MusicDatabase agent: songs outside music.db in a user's moods

**Status (2026-11-04):** built on the phone; MusicDatabase's side still to do.

Written by the MusicDatabaseApp agent (2026-11-04) for an agent working in `../MusicDatabase`.
First read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md`
(`user.db`) and your hand-off `moods-for-musicdatabaseapp.md`. Their rules win over anything here.
The sharing server is a contract with the app and partly lives outside the repo, so also record
your changes in `~/system-docs/README.md`. When it's built, answer with your own hand-off in
`docs/handoffs/` and mark anything you changed from this one **(changed)**.

## Why

The owner wants songs music.db doesn't have (YouTube videos, Spotify tracks, phone files) in their
own moods. This changes "a mood holds only songs that exist" (decision 1 of the moods hand-off, the
app's [ADR 0008](../decisions/0008-moods.md)) for **users' moods only**. Global moods stay as they
are: `tag.db` holds only `song_id`s.

## Contract (an addition to a user's mood in `PUT` / `GET …/moods`)

New field **`tracks`**, a list, next to `song_ids`. The phone sends it on every PUT:

```json
{"uid": "…", "name": "Siłownia", "updated_at": 1791839796631, "base_revision": 5,
 "song_ids": [1234],
 "tracks": [{"title": "…", "artist": "…", "youtube_video_id": "…", "spotify_track_id": null}]}
```

- `title`: a string, required. `artist`, `youtube_video_id`, `spotify_track_id`: a string or null,
  optional. Anything else in a track → **400** with a plain-text reason, like `song_ids`.
- A body without the key (an older app) keeps the stored tracks. Such a phone can't know about them
  and mustn't erase them.
- Every live mood's answer carries `tracks` (GET changes, PUT 200 / 409), `[]` when it has none. A
  deleted mood's form has none. The phone treats an answer without the key as "this server doesn't
  know them yet": it keeps its own and sends a mood holding any again with each sync, so nothing
  breaks before this is built, and they arrive by themselves once it is. Until then, expect such
  moods' revisions to grow without other changes.
- **Same song, one track:** the phone tells tracks apart by normalized artist + title
  (`songRequestKey`, the same as song requests). Keep the list as sent; on a merge of two same-name
  moods take the union by that key, as `song_ids` are unioned.
- Conflicts, revisions and the 8 MiB limit are the mood's own: `tracks` goes and comes with the
  mood as a whole.
- Tracks aren't checked against music.db and never touch `song_id_changes`. When music.db gets such
  a song, the phone recognises it, moves it to `song_ids` and sends the mood again (`updated_at`
  unchanged, a new `base_revision`). The server doesn't have to do this itself.

## Storage

A new `user.db` table (e.g. `mood_tracks`: tag id, title, artist, video id, Spotify id), in a new
`migrations/user/` file. Include the tracks in the archive JSON of a deleted mood.

## Promoting a user's mood to a global one

`tag.db` can't hold these tracks. **Proposed default, which the owner may still change:** promotion
moves `song_ids` as today, and the tracks stay only in the archive of the promoted user's mood. The
owner's menu should say how many are left out before promoting.

## MusicDatabase's own menu

Users → Moods shows a user's mood's songs: also list its tracks, marked as not in the database. The
existing request flow (`song_requests`) is separate: being in a mood doesn't ask for a song to be
added.
