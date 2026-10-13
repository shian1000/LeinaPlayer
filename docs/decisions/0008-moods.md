# 0008 - Nastroje (moods)

## Status

Accepted (2026-10-13). Built on both sides: MusicDatabase's sharing server serves
`/users/<name>/moods`, `/global-moods/…` and `GET /users/<name>` (its `mood_sync.py`, `moods.py`,
`global_mood_log.py`; contract in its `docs/handoffs/moods-for-musicdatabaseapp.md`), asked for
in [`../handoffs/musicdatabase-moods.md`](../handoffs/musicdatabase-moods.md).

Checked against the real server (2026-10-13, Huawei): making a mood, adding a song from search,
the mood screen, deleting it (archived by MusicDatabase), finding its songs by its name in song
search. Only by tests
(`test/data/moods_test.dart`, `test/data/account_test.dart`): moods made while logged out and
added to the account, the v12 → v13 upgrade, moods arriving from the account,
promotion, the same name on two phones, global mood changes and a revoked permission — there
were no global moods and no permission on the server yet.

## Context

The owner wants sets of songs with the same feel ("Nastroje": for exercise, for chilling…). A
song may be in many moods and a mood has no order, so it isn't a playlist. MusicDatabase already
had tags (`tag.db`, global) and private tags per user (`user.db`, its ADR-0004).

## Decision (the owner's)

- **Moods are tags.** Global moods are `tag.db` tags with `kind = 'mood'` (the others, e.g.
  `spellchecked`, are markers and never shown); a user's moods are tags in their `user.db`.
- **Only MusicDatabase songs** (`songs.id`) can be in a mood — "Dodaj do nastroju" is offered
  only for them.
- **A user's moods sync like playlists** ([ADR 0007](0007-playlist-sync.md)): whole moods,
  newer change wins, deleting deletes everywhere (archived first), names unique per user — the
  same name made on two phones becomes one mood (MusicDatabase merges, the phone adopts its uid).
- **The owner promotes** a user's mood to a global one in MusicDatabase (moved; merged with a
  global mood of that name). On the phone the user's mood just goes; the global one comes with
  the next tag.db.
- **Some users may edit global moods** (add and remove songs): the `edit_global_moods`
  permission, granted in MusicDatabase's menu. Without it the phone doesn't offer it. The
  phone learns permissions from `POST /login` and `GET /users/<name>`.
- In the UI: "Nastrój" / "Nastroje".
- **Moods work without a login** (owner, 2026-10-13): global moods show and play for anyone;
  moods made while logged out stay on the phone, like playlists, and the phone offers them to
  the account after logging in (the same dialog as playlists; Konto keeps a "Nastroje tylko na
  tym telefonie: N" row while any are left). Logging out hides the account's moods.
- **Song search can look at moods** (owner): the "Nastrój" search field (on by default) makes
  typing a mood's name list its songs as ordinary results, not the mood itself.

## On the phone (`moods.dart`, `local.db` v12–13)

- `moods` (`uid`, `account` — NULL for a phone-only mood, v13 —, `revision`, `dirty`,
  `deleted_at` like playlists) and `mood_songs` hold the user's moods; `MoodLibrary.sync` is `PlaylistLibrary.sync` for them
  (`PlaylistSyncClient` with `collection: 'moods'`), counter `moods.sync_revision.<user>`.
- Global moods are read from the downloaded tag.db (again after each download; a tag.db without
  `tags.kind` has none). Changes to them wait in `global_mood_changes`; sent ones (202) stay
  until a downloaded tag.db shows them — MusicDatabase applies them only before its next copy
  for the phones — or a week passes. The last change per song counts; changing back before
  sending sends nothing. 403 (no permission) / 404 (mood or song gone) drop the change; a 403
  also drops the permission on the phone.
- Search: `SearchField.mood`; `SongCatalog.setMoodNames(MoodLibrary.moodNamesOf)` gives each
  song the names of the moods shown (own and global), and the catalog rebuilds its search texts
  when moods change. A search-field selection saved as the old defaults (Tytuł, Wykonawca, Album)
  gets Nastrój added.
- Before each mood sync the phone refreshes the permissions, so a granted or revoked permission
  shows without logging in again.

## Consequences

- A mood shows only songs the phone's music.db has; others wait for a newer download (the
  screen says how many).
- A user's mood edited on the phone after the owner promoted it loses that edit (MusicDatabase
  answers 409 with the deletion); the phone doesn't redirect it to the global mood.
