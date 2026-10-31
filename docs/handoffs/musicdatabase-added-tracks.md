# Handoff for the MusicDatabase agent: songs added to imported playlists

**Status (2026-10-31):** built on the phone; waiting for MusicDatabase.

Written by the MusicDatabaseApp agent (2026-10-31) for an agent working in `../MusicDatabase`.
First read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md`
(`user.db`) and your hand-offs `playlists-for-musicdatabaseapp.md` and
`excluded-tracks-for-musicdatabaseapp.md`. Their rules win over anything here. The sharing
server is a contract with the app and partly lives outside the repo, so also record your changes
in `~/system-docs/README.md`. When it's built, answer with your own hand-off in `docs/handoffs/`
and mark anything you changed from this one **(changed)**.

## Why

Songs could only be added to playlists made on the phone: importing a YouTube / Spotify playlist
again rebuilds its tracks from the source, which would drop them. The owner reported that as a
bug, so the phone now lets songs be added to imported playlists too and marks those tracks as
added by hand; the next import keeps them, each after the source track it followed. The mark has
to reach the server, or the next import on another phone (or after the phone's data is synced
anew) drops them.

## Contract (an addition to a playlist's tracks in `PUT` / `GET …/playlists`)

- New track field **`added`**: `true` for a track the user added by hand to an imported playlist,
  `false` otherwise. The phone sends it on every track of every PUT.
- Store it with the track (e.g. `playlist_tracks.added INTEGER NOT NULL DEFAULT 0` in `user.db`,
  new `migrations/user/` file) and return it on every track the server answers with (GET changes,
  PUT 200 / 409).
- A track sent without the key (an older app) is `false`.
- Today `parse_playlist` drops the key, which doesn't break anything: an answer whose tracks lack
  it makes the phone keep its own marks (matched by title, artist, song id, video id, Spotify
  track id). Only another phone can't know about them until this is built.
- Validation: `true` / `false`; 400 otherwise, like `youtube_removed`.
- MusicDatabase's own menu may ignore the mark; nothing on the server rebuilds a playlist from
  its source.
