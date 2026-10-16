# 0011 - Syncing Biblioteka folders

## Status

Accepted (2026-10-16). Built on both sides: MusicDatabase serves `/users/<name>/folders` (user
migration 0008, its own `folder_revision` counter; contract in its
`docs/handoffs/folders-for-musicdatabaseapp.md`), asked for in
[`../handoffs/musicdatabase-folders.md`](../handoffs/musicdatabase-folders.md). It took the
contract as written and also rewrites folder refs when it merges playlists or moods.

Checked by tests (`test/data/library_folders_sync_test.dart`, against a fake server) and that the
real server answers the path (401 without a token); not yet by hand on a phone.

## Context

Biblioteka's folders hold playlists and moods (`library_folders.dart`). They were kept only on
the phone, in `shared_preferences`, while the playlists and moods in them sync with the
MusicDatabase account ([ADR 0007](0007-playlist-sync.md), [ADR 0008](0008-moods.md)). The owner
uses two phones and wants the same folders on both.

## Decision (the owner's)

- **Folders sync like playlists**: the server is the hub, the unit is a whole folder (name and
  items), the newer `updated_at` wins, deleting deletes everywhere, and folders made while logged
  out stay on the phone until they're added to the account (the same question after logging in,
  and a row in Konto). Logging out hides the account's folders.
- **Only folders**: the sort order ("Sortuj wg") and "Ostatnie" (when each item was last
  opened) stay separate on each phone.
- **MusicDatabase's side is a hand-off**, built by an agent working in that repo.

## On the phone (`library_folders.dart`)

- Still in `shared_preferences` (`library.folders`), each folder with `account`, `revision`,
  `dirty`, `updatedAt` and `deletedAt` like a playlist row. A folder's `id` is its `uid` on the
  wire: new folders get a UUID, ones made before keep their short id (the hand-off allows any
  string up to 64 characters).
- On the phone a folder's items are local keys (`p<playlists.id>`, `u<moods.id>`,
  `g<tag.db id>`), which differ between phones. On the wire each item is a ref: a playlist or
  user mood by its `uid`, a global mood by its tag.db id. `PlaylistSummary.uid` and `Mood.uid`
  exist for this; `main.dart` hands the loaded playlists and moods to
  `LibraryFolders.updateItems` whenever either changes.
- A folder remembers the last ref of each item (`refs`), so an item whose playlist isn't loaded
  at that moment is still sent. Refs the phone has no playlist or mood for yet (`pending`) are
  kept and sent back, and become items once the playlist or mood turns up. A ref that changed
  (MusicDatabase merged the playlist or mood into another) marks the folder to be sent again.
- An item is in one folder at most: a folder from MusicDatabase takes its items out of the
  phone's other folders.
- Synced after the playlists and moods (on start, return to the app, login), so their items are
  already on the phone; also 3 s after a folder change, and with ⟳ in Konto.

## Consequences

- MusicDatabase refuses an empty name (400); the phone never sends one (its dialogs refuse it).
- A mood promoted to a global one isn't rewritten in folders by MusicDatabase; on the phone its
  ref just stays pending (the folder loses it from view). Not handled — rare.
- A folder can hold a phone-only playlist; its ref goes to MusicDatabase but the other phones
  never resolve it, so it stays pending there (harmless, sent back unchanged).
- Conflicts depend on the phones' clocks, as with playlists.
