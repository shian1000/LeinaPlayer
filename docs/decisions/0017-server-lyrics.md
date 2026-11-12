# 0017 - Lyrics from MusicDatabase's server

## Status

Accepted (2026-11-12): MusicDatabase now collects lyrics itself and asked the phone to use them —
its `docs/handoffs/lyrics-for-musicdatabaseapp.md` (the contract), handed over by the owner.
LRCLIB stays as the fallback (the owner's decision). Tests: `lyrics_test.dart`. Not yet tried
against the real server.

## Context

The full player's lyrics card looked every song up on LRCLIB from the phone (a gap filled per
ADR 0003). MusicDatabase now keeps lyrics in its own `lyrics.db` (from the library's mp3 tags,
LRCLIB, Genius and others, checked against the song; synced lines only when their recording's
length fits the song's). The file is ~25 MB, so it isn't downloaded with the catalog.

## Decision

- For a music.db song the card asks `GET /lyrics/<songs.id>` first, on the same addresses as
  the database download (`DatabaseSync.serverAddresses`, home LAN first), through
  `ServerTrust`, no token, short timeouts (3 s to connect, 8 s for the answer).
- 200: its `plain` / `synced` / `instrumental` are shown as they are. Plain text without synced
  lines is often on purpose (they didn't fit the song's video), so LRCLIB isn't asked for synced
  lines then.
- 404 (no lyrics there) sends the song to LRCLIB at once; an error or no answer tries the next
  address, then LRCLIB. A song only on the phone or YouTube goes straight to LRCLIB.
- Songs whose `songs.language` is `Instrumental` aren't looked up anywhere ("Utwór
  instrumentalny.").
- The card credits the source: "Teksty: MusicDatabase (Genius)" from the server's `source`
  (unknown values: just "MusicDatabase"), "Teksty: LRCLIB" otherwise.
- Still in memory for the run only; "Pobieraj teksty piosenek" switches both off.

## Consequences

- With a server set, the phone asks it the song's id each time the full player shows a new
  song (Prywatność i połączenia, `PRIVACY.md`).
- An answer is kept for the run even when it came from LRCLIB because the server was out of
  reach; the next start asks the server again.
