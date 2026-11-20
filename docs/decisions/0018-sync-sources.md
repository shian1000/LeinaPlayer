# 0018 - Each synced function has its own sources

## Status

Accepted (2026-11-20), the owner's request: Ustawienia › Synchronizacja replaces Ustawienia ›
Serwer and › Zgłoszenia poprawek, and Informacje i pomoc's "Problemy". Tests:
`sync_sources_test.dart`, `database_sync_test.dart` (the order), `widget_test.dart`.

## Context

One server address list (`DatabaseSync.serverAddresses`) served everything: the catalog
download (server first, GitHub second — ADR 0014), the account's sync (ADRs 0007, 0008, 0011,
0013) and the outbox (ADR 0005). The owner wants every main function to choose its sources on
its own, and plans a shared "Leina" server next to the user's private MusicDatabase server.

## Decision

- Four functions (`SyncFeature`): the catalog (Baza danych), the account's library (Biblioteka
  użytkownika), requests for MusicDatabase (Prośby do bazy danych) and problem reports
  (Raportowanie błędów). Each has its sources (`SyncSource`) with a switch and an order,
  kept in `shared_preferences` by `SyncSources` (owned by `DatabaseSync`):
  - the catalog: the private server, GitHub, the Leina server — that order by default, so
    nothing changes for a phone that had a server;
  - the other three: the private server, the Leina server.
- The phone's own data isn't a source: it is always kept, shown apart as "Dane na telefonie"
  without a switch or a place in the order (the owner's decision).
- The Leina server doesn't exist yet, and MusicDatabase has no place for problem reports: those
  rows can't be switched on and show "Work in progress :)" (`SyncSources.works`). No new
  connection is made.
- The catalog tries its switched-on sources top down until one gives it; GitHub's publish older
  than the phone's copy counts as nothing new and the next source is asked (before, GitHub came
  last, so it simply ended the attempt).
- The other functions get the server's addresses through `serverAddressesFor(feature)`: none
  while their private server is off, and their syncs then do nothing. The outbox isn't even
  tried then (no "no server" problem on screen); "Wyślij paczkę…" still works.
- What isn't one of the four keeps `serverAddresses()` regardless of the switches: playing the
  server's files (ADR 0010), lyrics (ADR 0017) and logging in (ADR 0006).
- One private server for all four: its addresses and certificate are on one screen, opened
  from each function's "Prywatny serwer" row.

## Consequences

- The catalog's GitHub switch keeps its key (`database_sync.github_on`), which the first start's
  question also reads; the new keys are `sync_sources.<function>.<source>_on` and
  `sync_sources.<function>.order`, backed up with the rest of `shared_preferences`.
- When the Leina server exists, it gets a row that works and its own connection — a new ADR and
  an entry in Prywatność i połączenia / `PRIVACY.md`.
