# 0003 - The app supports MusicDatabase, not only displays it

## Status

Accepted (2026-10-10). Supersedes the "thin client, no business logic" part of
[ADR 0001](0001-project-setup.md). Its "nothing is sent back yet" is superseded by
[ADR 0005](0005-outbox-for-musicdatabase.md) (the outbox, 2026-10-13).

## Context

ADR 0001 and AGENTS.md described this app as a presentation/consumption layer only: all logic in
MusicDatabase, nothing reimplemented here. The owner has since changed the concept:

- The phone must keep working when the server (MusicDatabase's sharing server) is unreachable.
- The app is meant to support MusicDatabase, not just show it. Later it will send new
  information it gathered back to MusicDatabase, to be reviewed there.

The first concrete case is YouTube. Of 5331 songs in `music.db`, 1825 have `youtube_video_id`, 5
are marked `N/A` (not on YouTube) and 3501 have nothing. The owner wants the phone to find a
missing link itself instead of waiting for MusicDatabase.

## Decision

- **MusicDatabase stays the source of truth.** When the downloaded `music.db` has a value, the
  app uses it as is.
- **When a value is missing, the app may work it out itself** with its own logic, kept in
  `lib/src/data/`. The result is **local and temporary**: stored only in the phone's `local.db`,
  recognisable as found by the phone, and replaced by MusicDatabase's value as soon as a
  downloaded `music.db` has one.
- **That logic is a deliberate "lite" version, not a copy kept in sync.** It may borrow ideas
  from MusicDatabase (e.g. YouTube matching from `score_result()` in
  `src/utils/youtube/manage_youtube_playlists.py`) but is simpler, because the phone has less data
  (no yt-dlp metadata such as tags or `track`) and must not depend on the server. Each such piece
  names its MusicDatabase counterpart in its doc comment or agent note, so nobody "fixes" it into
  a full port or deletes it as duplication.
- **Nothing is sent back to MusicDatabase yet.** Sending phone-found data for review is the
  intended direction but needs its own ADR (transport, review flow on the MusicDatabase side).
  Until then the app only downloads ([ADR 0002](0002-database-download.md)).

## Consequences

- `AGENTS.md` and `docs/architecture.md` describe the app as a client that may fill gaps locally,
  not as a presentation layer only.
- The phone and MusicDatabase can disagree (e.g. a different video for the same song). That's
  accepted: the phone's answer only lives until MusicDatabase has its own.
- MusicDatabase's documentation should say that the phone app may derive missing data locally and
  will later submit it for review, so changes there don't assume a read-only client.
