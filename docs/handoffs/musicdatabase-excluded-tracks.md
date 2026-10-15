# Handoff for the MusicDatabase agent: tracks removed from imported playlists

**Status (2026-10-15):** built on both sides. MusicDatabase answered in its
`docs/handoffs/excluded-tracks-for-musicdatabaseapp.md` (the final contract; nothing changed,
details decided: a live playlist always carries the list, `[]` when empty; `null` is a 400; a
playlist brought back after deletion without the key gets `[]`).

Written by the MusicDatabaseApp agent (2026-10-15) for an agent working in `../MusicDatabase`.
First read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md`
(`user.db`) and your hand-off `playlists-for-musicdatabaseapp.md`. Their rules win over
anything here. The sharing server is a contract with the app and partly lives outside the repo,
so also record your changes in `~/system-docs/README.md`. When it's built, answer with your own
hand-off in `docs/handoffs/` and mark anything you changed from this one **(changed)**.

## Why

The phone can now remove a song from any playlist ("Usuń z tej playlisty"), imported ones
included. That change already reaches the server: the phone PUTs the whole playlist, without
the track. But importing a YouTube / Spotify playlist again (on any phone) rebuilds its tracks
from YouTube / Spotify, which would bring the removed song back. So the phone remembers which of
the source's tracks the user removed and leaves them out of the next import. The owner wants
this to hold on all their phones, so the list has to go through the server with the playlist.

## Contract (an addition to `PUT` / `GET …/playlists`)

- New playlist field **`excluded_source_tracks`**: a JSON list of strings (possibly empty), the
  ids *in the playlist's source* of tracks the user removed: YouTube video ids for `source`
  `youtube`, Spotify track ids for `spotify` / `spotifyAlbum`. Other sources: the phone sends `[]`.
- The phone sends it in every PUT. Store it as part of the playlist (e.g. a JSON text column
  `playlists.excluded_source_tracks` in `user.db`, new `migrations/user/` file) and return it in
  every playlist the server answers with (GET changes, PUT 200 / 409). Only the whole list, like
  the tracks: the newer playlist wins, nothing is merged.
- A PUT **without** the key (an older app) keeps the stored list, like `cover`
  (`KEEP_COVER`). An answer without the key makes the phone keep its own list — so until this is
  built nothing breaks.
- Merging the same `source` + `source_id` from two phones (`merge_same_source`): the list goes
  with the winning side, like the tracks.
- Deleting a playlist drops the list (the archive copy keeps it). The phone clears its own on
  deletion, so a playlist imported anew is whole again.
- Validation: a list of non-empty strings; 400 otherwise, like other bad fields.
- MusicDatabase's own writers (menu imports, song id changes) don't need to touch it. If the
  menu ever re-imports a YouTube playlist into an existing one, it should leave these ids out
  too.
