# 0014 - Database from GitHub and request packages, beside the server

## Status

Accepted (2026-10-21). MusicDatabase's side — the allow-list export with its self-check,
publishing to the release `database` (first publish 2026-10-21) and the package import — is
built; its answer, with the final contract (`version.json` also carries `content_sha256`, to be
ignored; a file may be briefly 404 or newer during a publish; sender names must match
`^[a-z0-9][a-z0-9_-]{1,31}$` or be left out), is
`../MusicDatabase/docs/handoffs/public-database-for-musicdatabaseapp.md`. The phone's side is
built too (2026-10-21): the GitHub source in `DatabaseSync` (Ustawienia › Serwer) and packages in
`Outbox.exportPackage` (Ustawienia › Zgłoszenia poprawek › "Wyślij paczkę…"). Details decided
while building it: after a download from GitHub an existing `files.db` stays (it only comes from
a server and still fits that server's files); requests waiting unsigned get the sender's name
only as they go into a package (a signed name sent over HTTP without that user's token would be
refused); closing the share sheet without sharing puts them back; requests over the inbox's
1 MiB go to `outbox/rejected/`, ones over the package's limits wait for the next package; Cyrillic
in a typed name is transliterated (a sender label, not a shown name).

## Context

The app is going to two friends. Neither has an account on the owner's MusicDatabase server:
it's reached only over the owner's Tailscale network (home router forwards no ports — owner's
rule), and there's no rented public server yet. One friend may run their own MusicDatabase
server; the other will have none. Both should still get MusicDatabase's catalog and be able to
send back what the phone reports (dead links, corrections, found videos, song requests —
[ADR 0005](0005-outbox-for-musicdatabase.md)).

The databases are small (2026-10-21: `music.db` 1.0 MB, `tag.db` 0.3 MB, ~0.65 MB gzipped), so
whole-file downloads stay fine ([ADR 0002](0002-database-download.md)).

## Decision (the owner's)

Two **additional** ways of talking to MusicDatabase. They replace nothing: the HTTP download
(ADR 0002), the inbox (ADR 0005) and the account's sync (ADR 0006–0013) stay as they are.

### 1. The catalog from a GitHub Release

- **MusicDatabase publishes** a public copy of `music.db` and `tag.db` to its public repo
  (`shian1000/LeinaMusicDatabase`), as the assets of one release with a fixed tag (`database`),
  replaced on each publish — a stable address that other releases of the repo can't move:
  `https://github.com/<owner>/<repo>/releases/download/database/<file>`. Not files in the
  repo: git would keep every version forever, and files over 100 MB are refused.
- **What is published:** only what anyone may see — the catalog. No user data at all (accounts,
  password hashes, tokens, permissions, playlists, the users' own moods, folders, covers,
  listens, the inbox); `tag.db` with global moods only; no `files.db` (useless without the
  server, and it maps the owner's library). Data whose licence forbids it (e.g. song lyrics) is
  left out. The export checks its own output for forbidden tables before anything is uploaded,
  and refuses to publish otherwise. Details: MusicDatabase's side, in its hand-off.
- **With them, `version.json`**: when it was published and each file's size and SHA-256. The
  phone reads this small file first and downloads the databases only when they changed, then
  checks the hashes before swapping them in (same `*.part` + SQLite-header rule as ADR 0002).
- **When:** automatically once a day after MusicDatabase's daily backup, when the catalog
  changed since the last publish — **on by default, can be switched off in MusicDatabase's
  settings** — and on demand from MusicDatabase's menu ("Opublikuj bazę na GitHubie"). The
  GitHub token lives in MusicDatabase's `.env` (fine-grained, write access to that one repo
  only), never in git.
- **On the phone: a third source, "GitHub"**, next to the remote and home addresses, holding
  `<owner>/<repo>`. **A fresh install has `shian1000/LeinaMusicDatabase` filled in**; its first
  start asks (a full screen, `first_run_screen.dart`) whether to download the catalog from GitHub
  — "Tak" leaves the switch on and downloads it at once, "Nie" switches it off. Nothing is
  downloaded before the answer; a phone that already downloaded a catalog isn't asked (owner's
  decision, 2026-10-23). The repository can be changed (a friend's fork) or switched off later. This is public, shared data — not the owner's private settings
  (checklist 1.5).
- **Order:** a configured, reachable MusicDatabase server first (always the freshest); GitHub
  when no server is set or none answers. Same once-a-day rhythm and "Pobierz teraz" as ADR 0002;
  the download screen shows which source the current copy came from. A server whose `music.db`
  has no songs (MusicDatabase started "with an empty database") counts as not answering while the
  phone's copy has some: the phone keeps it (or takes GitHub's), and Ustawienia › Serwer says
  "Serwer udostępnia pustą bazę" with "Użyj pustej" to take it after all (sharing checklist
  4.2b, 2026-10-23).

### 2. Request packages

- **The phone exports its waiting outbox files as one `.zip`** through the share sheet
  (Android's "Udostępnij": a messenger, e-mail…), to whoever runs the MusicDatabase it reports
  to. The files inside are the outbox's own SQLite files, unchanged — the inbox contract
  ([hand-off](../handoffs/musicdatabase-outbox.md)) stays the only format.
- **Who sent it:** a logged-in phone already names its files `<user>_<date>_<time>_<n>.db`. A
  phone without an account asks once for a name on the first export (kept in settings,
  changeable) and uses it in the same place, so MusicDatabase can tell people apart. It's a
  label, not an identity — packages come from people the owner knows, by hand.
- **After exporting, the files count as sent** — they move to `outbox/sent/` exactly as after an
  upload to the inbox, and the next package holds only newer ones. "Wyeksportuj ponownie
  ostatnią paczkę" rebuilds the last package from `sent/` in case one got lost.
- **MusicDatabase imports a package** from its menu ("Importuj paczkę"): it checks the zip
  (only `.db` files with valid inbox names, size limits, no paths), puts them into its inbox and
  processes them like any other request — the owner reviews them as today. A package can't
  carry anything the inbox wouldn't accept over HTTP.
- Only outbox requests travel this way. The account's own data (playlists, moods, liked songs,
  stats…) still needs an account on a server; a phone without one keeps it on the phone
  (backups: checklist 4.1).

## Consequences

- MusicDatabase gets: the public export with its self-check, publishing to a GitHub Release
  (a token in `.env`, a setting to turn the daily publish off, a menu entry), and the package
  import. Asked for in a hand-off.
- The phone gets: the GitHub source with its default, `version.json` handling, the source order,
  the package export with the sender's name, and "export again". `files.db` stays server-only,
  so the "Serwer" playback source ([ADR 0010](0010-server-files.md)) needs a server as before.
- Anyone can download the published catalog — it's meant to be public. Nothing private may ever
  reach it; the export's self-check is what guards that, not care at publish time.
- A friend running their own server can point the phone at their server, at a fork's release,
  or at both (server first, GitHub second).
