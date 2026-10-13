# 0009 - Syncing playlist and mood covers

## Status

Proposed (2026-10-13). Asked of MusicDatabase in
[`../handoffs/musicdatabase-covers.md`](../handoffs/musicdatabase-covers.md); the phone side is
built after its answer. Until then picked covers stay on the phone
([`../agent-notes/covers.md`](../agent-notes/covers.md)).

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

## Consequences

- An extra round trip per new cover (upload before the PUT, download on a new hash).
- A cover of a global mood the server no longer has just lies unused.
