# 0012 - Listening stats: recording and syncing plays

## Status

Accepted (2026-10-16). Stage 1 of the listening stats (Ja › Statystyki słuchania) — recording
and syncing — built on both sides: MusicDatabase serves `/users/<name>/listens` (user migration
0009, its own `listen_revision` counter; contract in its
`docs/handoffs/listening-stats-for-musicdatabaseapp.md`), asked for in
[`../handoffs/musicdatabase-listening-stats.md`](../handoffs/musicdatabase-listening-stats.md). It
took the contract as written; `limit` is capped at 1000 (the phone asks for 500).

Checked by tests (`test/listening_log_test.dart`, against a fake server) and that the real server
answers the path (401 without a token); not yet by hand on a phone.

## Context

The owner wants listening stats like Spotify's (top songs / artists / albums over 4 weeks, half
a year, a year; minutes listened), yearly Wrapped-style cards and season summaries (spring,
summer, autumn, winter). "Ostatnie" (`play_history`) can't serve them: it keeps at most 1000
plays from the last 90 days by default, and records a song when it starts, so a song skipped
after two seconds counts like one heard through, and nothing says how long anything was heard.

## Decision (the owner's)

- **Stats count from this version on.** The old history isn't imported (it has no listened
  time).
- **Synced with MusicDatabase**, so both phones' listening adds up and survives a new phone.
- Built in stages: 1. recording and sync (this ADR), 2. the stats screen, 3. highlights,
  4. yearly and seasonal summary cards.

## On the phone

- A new `listens` table in `local.db` (version 17), never cut down: one row per song the queue
  started in this app's player, with how long it was really heard (`listened_ms` — the song's
  position moving on while playing; seeks over 3 s and paused time don't count), its length,
  title / artist / album as shown, music.db's song id, YouTube video / Spotify track, the source
  (phone file, MusicDatabase's server, YouTube) and the playlist or mood it played from (the
  synced `uid` — or a global mood's tag.db id — and the name). A song handed to the YouTube app isn't recorded (nothing tells how long
  it played). `play_history` stays as it was, for "Ostatnie".
- What counts as a stream (Spotify: 30 s), a skip or a finished song is decided when the stats
  are computed, from `listened_ms` and `duration_ms` — the raw time is what's kept.
- `ListeningTracker` (`lib/src/playback/`) feeds `ListeningLog` (`lib/src/data/listening_log.dart`)
  from `PlaybackQueue.played` and `PlayerController.positionChanges`. The current play's time is
  written every 30 s of listening, when the next song starts and when the app goes to the
  background.
- Plays made while nobody is logged in (`account` NULL) go to the next account that logs in,
  without asking — they're the phone owner's listening, unlike a playlist one may not want in
  the account.
- Sync: a play is only ever added or heard longer, so there are no conflicts — the longer
  `listened_ms` wins. The phone fetches what changed since its last revision (pages of 500),
  then posts its new plays and longer times (500 per request). Synced on start, on return to the
  app, after a login, every 20 finished songs, and with ⟳ in Konto.

## Stage 2: the stats screen

Ja › Statystyki słuchania (`listening_stats_screen.dart`), computed on the phone from the
`listens` of the logged-in account (and the not yet sent ones of nobody) by
`ListeningStats.of` (`listening_stats.dart`):

- Periods like Spotify's, rolling and ending now: 4 weeks, 6 months, a year, everything.
- A play counts from 30 s of listening; the minutes count every second heard. Songs, artists
  and albums are ranked by plays, ties by time; decades, languages, countries and sources by
  their share of the time.
- A song is counted by music.db's id after `song_id_changes` (`SongCatalog.current`), with
  music.db's names; songs not in it by their video, else by artist + title. Artists are split
  from the label as "Przejdź do wykonawców" does (`artistNamesOf`); albums are grouped by name
  like "Przejdź do albumu", without "Singles".

## Stage 3: highlights

"Ten tydzień" on top of the stats screen: cards about the last 7 days, worked out on the phone
from every play (`listening_highlights.dart`), after Spotify's weekly highlights. The rules are
the phone's own (MusicDatabase has no counterpart):

- Milestones reached this week: hours of all time (1, 10, 24, 50, 100, …), a song's 10th, 25th,
  50th… play, an artist's 25th, 50th, 100th… play.
- Nowe odkrycie: an artist first played this week, 3+ plays — only once the stats are two weeks
  old (before that every artist is new).
- Powrót: a song played again after 3+ months.
- Utwór tygodnia: the week's most played song, 3+ plays; Na zapętleniu: another song 5+ times
  in one day.
- At most 3 of each kind; a song's card plays it, an artist's opens their songs. Not shared yet
  (stage 4's cards).

## Stage 4: year and season summaries

"Podsumowania" in the stats screen: a tile per calendar year and per season with plays
(`listening_summary.dart`; seasons are meteorological — whole months: spring March–May, summer
June–August, autumn September–November, winter December–February, "Zima 2025/26"). One still
going on is summed up so far ("Trwa"). A tile opens `listening_summary_screen.dart`: full-screen
cards after Spotify Wrapped, over the bottom bar (a tap on the right goes on, on the left back,
swiping too):

- the period; minutes (as days / hours, a daily average, plays) with a month-by-month chart;
  the song no. 1 and the top 5; the artist no. 1 and the top 5; the album no. 1 and the next
  four; "Twoje brzmienie" (the top decade, language, artists' country with its share); the hours
  of the day; new artists (first heard in the stats during the period — only when there are
  plays before it); a last card with the top 5 artists and songs.
- The last card is shared as a PNG (`RepaintBoundary` → a temp file → Android's share sheet via
  `share_plus`).
- Card colours come from the theme (`colorForSeed`, pulled towards the background like the
  full player's tint), so every theme keeps its text readable.

## Consequences

- MusicDatabase keeps `song_id` as sent, not remapped when it merges or deletes a song: the stats
  (stage 2) have to resolve old ids through music.db's `song_id_changes` (`old_song_id` →
  `new_song_id`, NULL = deleted), as `song_details.dart` does.

- Deleting stats (one play, or all) isn't possible yet; when it's wanted it needs deletion
  markers in the contract.
- Stats are per account; a phone used logged out keeps them for itself until someone logs in.
- A crossfade's few seconds of the old song's fade-out aren't counted.
