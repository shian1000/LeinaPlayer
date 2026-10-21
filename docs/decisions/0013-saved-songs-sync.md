# 0013 - Syncing liked songs, "Na później" songs and "Na później" links

## Status

Accepted (2026-10-21). Phone side built and checked by tests
(`test/data/saved_songs_sync_test.dart`, against a fake server). MusicDatabase's side was asked
for in [`../handoffs/musicdatabase-saved-songs.md`](../handoffs/musicdatabase-saved-songs.md) and
built the same day as written (its answer: `../MusicDatabase/docs/handoffs/saved-songs-for-musicdatabaseapp.md`
— 64 KiB body limit, one revision counter per collection, the deleted form carries `updated_at`,
merged songs' `song_id` rewritten under a new revision).

## Context

Liked songs ("Polubione utwory") and songs saved "Na później" (`saved_songs.dart`) and the links
saved "Na później" from the native link sheet (`later_links.dart`, kept by `LaterLinks.kt`)
lived only on the phone. When the owner reinstalled the app (2026-10-20, a new signing key)
everything synced with the account came back after logging in, but these three were lost. The
app is about to go to two friends, so they have to survive a reinstall too.

## Decision (the owner's)

- **They sync like Biblioteka's folders** ([ADR 0011](0011-folder-sync.md)): the server is the
  hub, the newer `updated_at` wins, a deletion is kept as a marker and deletes everywhere,
  logging out hides the account's items.
- **Unlike folders, phone-only items join the account without asking**: what was liked or saved
  while logged out goes to the next account that syncs, so nothing is lost and nothing is
  asked.
- **The unit is one item**, not a whole list: liking songs on two phones at once is no conflict.
- **MusicDatabase's side is a hand-off**, built by an agent working in that repo.

## The wire

- `/users/<name>/saved-songs` — both song lists, each item with `list`: `liked` or `later`.
  Its `uid` is a SHA-1 of the list and the song's `TrackRef.key`, so the same song on the same
  list is one item on every phone. The song goes as its music.db `song_id` (looked up with
  `SongCatalog.current`, so a merged song goes under its new id), `title`, `artist` and its
  YouTube / Spotify ids, never the path of a phone file.
- `/users/<name>/later-links` — the link's own UUID (kept by `LaterLinks.kt`), `url`,
  `service`, `kind`, `person` (the sender's **name**), `saved_at`, `opened_at`, `title`,
  `artist`. People stay on each phone: a link from MusicDatabase goes to the person of that name
  (made if missing); renaming a person sends their links again, removing one deletes their
  links.
- Both: `GET ?since=`, `PUT …/<uid>` with `base_revision`, `DELETE …/<uid>?base_revision=&
  deleted_at=`, 409 with the stored item for an older change — the folders' contract.

## On the phone

- `item_sync.dart`: `ItemSync` does the HTTP and the order (phone-only items join the account,
  what changed there comes, then deletions and changes made here go); `SyncFields` is what each
  item remembers (`account`, `revision`, `dirty`, `updatedAt`, `deletedAt`).
- `SavedSongsSync` (over `SavedSongs` and `LikedSongs`, still in `shared_preferences`; lists
  from before keep their order and are uploaded on the first sync) and `LaterLinks` (an
  `ItemSync` itself).
- Links stay stored natively: the sheet saves without Flutter. `LaterLinks.kt` keeps whatever
  fields Dart gives a link and has `putLaterLink` for links from MusicDatabase. A link the sheet
  saves has no account yet; the next sync gives it to the logged-in one. Saving the same link
  from the same person again keeps its id (it moves to the top and goes again).
- Synced on start and login (after the lists are read), on return to the app, 3 s after a
  change, and with ⟳ in Konto ("Polubione i zapisane utwory", "Linki na później").

## Consequences

- The same link saved on two phones independently is two items (different ids); not merged.
- Two people of the same name on one phone are one person on the other.
- A song liked as a phone file not in MusicDatabase reaches the other phone by title and artist
  only (it's searched on YouTube there).
- Conflicts depend on the phones' clocks, as with playlists.
