# 0009 - Syncing playlist and mood covers

## Status

Accepted (2026-10-13). Built on both sides: MusicDatabase serves the blobs, the `cover` field
and `/users/<name>/global-mood-covers` (its `covers.py`, `playlist_sync.py`, `mood_sync.py`;
contract in its `docs/handoffs/covers-for-musicdatabaseapp.md`), asked for in
[`../handoffs/musicdatabase-covers.md`](../handoffs/musicdatabase-covers.md).

Checked against the real server (2026-10-13, Huawei): a mood's cover set (blob uploaded, the mood
in `user.db` names it) and removed. Only by tests (`playlist_sync_test.dart`, `moods_test.dart`):
playlist covers, downloading a cover set elsewhere, global moods' covers.

## Context

Playlists and moods can have a cover picked on the phone ("Dodaj okładkę"; otherwise a collage
of their songs' covers). Playlists and moods already sync with the MusicDatabase account
([ADR 0007](0007-playlist-sync.md), [ADR 0008](0008-moods.md)), their covers don't.

## Decision (the owner's)

- A cover is part of its playlist or mood: changing it is a change synced under the same rules
  (newer `updated_at` wins, deletion everywhere, archived).
- Images travel separately, content-addressed by SHA-256 (`/users/<name>/covers/<sha256>`); the
  playlist / mood JSON carries only `"cover": "<sha256>" | null` (missing key = unchanged, for
  older app versions).
- A global mood's cover is **private per user** (stored in their `user.db`, synced between their
  phones by `/users/<name>/global-mood-covers`); nobody else sees it.
- MusicDatabase only stores and archives covers; its menu doesn't set them.
- Logged-out phones keep covers on the phone, like their playlists.

## On the phone (`custom_covers.dart`, `local.db` v14)

- Pictures are files named by their hash (`CustomCovers`); `playlists.cover_sha256`,
  `moods.cover_sha256` and the table `global_mood_covers` (`account` NULL = phone-only, `revision`,
  `dirty`) say which is whose. Setting or removing a cover bumps `updated_at` and marks the row
  changed, like a rename; deleting a playlist or mood drops its cover (MusicDatabase does too).
- A PUT names the hash; the picture goes only when MusicDatabase answers `cover_missing`, then
  the PUT once more (`putWithCover`). After a sync every hash the account refers to that the phone
  hasn't got is downloaded (`fetchCovers`).
- Global moods' covers: a third counter, `moods.global_cover_revision.<user>`, synced after the
  moods. Logged in, the account's cover of a global mood wins over a phone-only one; adding the
  phone-only things to the account moves those covers to it.
- Pictures nothing refers to are deleted a day after they were last written, once after start.

## Consequences

- A new cover costs one refused PUT before its upload, and a download on the other phones.
- A cover of a global mood the server no longer has just lies unused.
- Covers picked with the build before this (files `<key>.<millis>.png`) aren't read any more;
  they have to be picked again.
