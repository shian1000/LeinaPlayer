# 0005 - Outbox: requests the phone sends to MusicDatabase

## Status

Accepted (2026-10-13). Sending works since 2026-10-13, to the inbox MusicDatabase described in
its `docs/handoffs/inbox-for-musicdatabaseapp.md`.

## Context

[ADR 0003](0003-app-supports-musicdatabase.md) said the app will later send what it learned back
to MusicDatabase for review, and left the how to its own ADR. The first case came up on
2026-10-12: four songs in `music.db` ("Chromatic", "Losing Sleep", "Obsession", "Slipping Away"
by Elise Trouw) link to "Elise Trouw - Topic" videos that YouTube no longer plays (`UNPLAYABLE`,
"This video is not available"). The phone now finds another video itself, but the dead link
should be fixed in MusicDatabase, and the phone can't do that.

## Decision (the owner's)

- **The phone keeps an outbox** of requests for MusicDatabase (`lib/src/data/outbox.dart`,
  `<support dir>/outbox/` on the phone). A request is a **small SQLite file** whose tables look
  like music.db's where they can (song ids are `songs.id`), but in its own shape. One request may
  cover one song or many.
- **File name: `[<user>_]<date>_<time>_<number>.db`**, e.g. `2026-10-12_23-44-05_001.db`; the
  date and time are when the request was started (phone's local time), the number counts up and
  is never reused. The user part is left out while the app has no user name.
- **MusicDatabase gets an inbox: a folder on disk.** Where, and how it processes requests, is
  MusicDatabase's to propose — its agent picks a place and confirms it with the owner
  ([`../handoffs/musicdatabase-outbox.md`](../handoffs/musicdatabase-outbox.md)).
- **When the phone can reach MusicDatabase, it sends its requests to that inbox.** Whatever can't
  go stays in the outbox for the next try.
- First request type: **`dead_youtube_links`** — music.db's `youtube_video_id` that YouTube no
  longer plays, with the video the phone found instead when it found one (a suggestion; the
  owner reviews it in MusicDatabase). The phone keeps playing its replacement until a downloaded
  `music.db` has a different link or "N/A" (server values still win).

## How the phone fills it

- A music.db link found gone while playing or caching ahead (`TrackPlayer`) is reported;
  the replacement is added to the same row when the search finds one.
- After each `music.db` load, dead music.db links the phone knew about before (e.g. found by an
  older build) are reported too, with the phone's replacement if it has one.
- A dead link already in any request, waiting or sent (`outbox/sent/`), isn't reported again.
- New reports go into the newest waiting request; a sent request leaves the outbox and the next
  report starts a new file.

## Sending (MusicDatabase's inbox)

- `PUT <server>/inbox/<file name>` with `Content-Length`, to the same addresses as the download,
  best first (`DatabaseSync.serverAddresses`: local on the home Wi-Fi, then remote), at most
  1 MiB per file. Tried on start (after the daily download), on return to the app, and a minute
  after a new report (so the replacement found right after a dead link joins the same file).
  The state and "Wyślij teraz" are in Ustawienia › Źródła muzyki › Baza danych.
- 201 / 200 (stored / this exact file already received) → the file moves to `outbox/sent/`.
- 400 / 409 / 411 / 413 (malformed, number reused, no length, too big — bugs on the phone) →
  `outbox/rejected/`, kept, not sent again.
- 507 (inbox full), 503 (server's drive not mounted) → stays, and automatic sending waits for
  the next day (the next daily download; `outbox.held_on_ms` in `shared_preferences`, so a
  restart doesn't retry) — user's decision. "Wyślij teraz" tries anyway. No answer or another
  code → the next address, else stays; no connection doesn't hold sending back.
- "Wysyłaj zgłoszenia poprawek automatycznie" (on by default, `outbox.auto_send`): off, reports
  are still collected but go only with "Wyślij teraz".
- `sent/` and `rejected/` are kept: they stop a link from being reported twice and a number from
  being reused.

## Open

- ~~User name~~ — settled by [ADR 0006](0006-musicdatabase-login.md): the logged-in MusicDatabase
  user; uploads carry its token.
- Whether `outbox/sent/` is ever pruned (e.g. once music.db reflects its rows).

## Consequences

- The app stores something meant for the server, not a cache: the outbox isn't cleared with
  Pamięć podręczna and has no setting there; its state is shown next to the database download.
- The request format is a contract with MusicDatabase: `request.format` (now 1) goes up on
  incompatible changes, described in the hand-off.
