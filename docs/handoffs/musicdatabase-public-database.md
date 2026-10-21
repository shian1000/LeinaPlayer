# Handoff for the MusicDatabase agent: a public catalog on GitHub and request packages

**Status (2026-10-21):** MusicDatabase's side built and first published the same day; its answer
(the final contract): `../MusicDatabase/docs/handoffs/public-database-for-musicdatabaseapp.md`.
The phone's side (checklist 3.4–3.5) not built yet ([ADR 0014](../decisions/0014-github-database-and-request-packages.md)).

Written by the MusicDatabaseApp agent (2026-10-21) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md` first (database safety, Machine settings / `.env`, Git
policy — both repos are public, nothing private in git), its ADR-0004 (per-user data), and
`docs/handoffs/inbox-for-musicdatabaseapp.md` (the inbox you built). Their rules win over anything
here. The sharing server and timers partly live outside the repo: record changes in
`~/system-docs/README.md` too. Once built, answer with a hand-off of your own in `docs/handoffs/`
(like `saved-songs-for-musicdatabaseapp.md`): what was built, the final contract, anything you
changed from this one.

## Why

Leina Radio is going to two friends who can't reach the owner's server (Tailscale only, the home
router forwards no ports — owner's rule; a public server would be a rented one, later). They
still need the catalog, and the owner still wants their phones' reports (dead links,
corrections, found videos, song requests). Two **additional** ways, replacing nothing — the
sharing server, the inbox and account sync stay as they are:

1. MusicDatabase publishes a **public copy of `music.db` and `tag.db` as a GitHub Release** of
   its public repo; phones download it when they have no server (or it doesn't answer).
2. A phone without a server **exports its outbox as a `.zip`** and sends it to the owner by hand;
   MusicDatabase **imports** it into the inbox.

Sizes today (2026-10-21): `music.db` 1.0 MB, `tag.db` 0.3 MB.

## Decisions (the owner's)

- Publishing: **automatic, once a day after the daily backup, only when the catalog changed —
  on by default, switchable off in MusicDatabase's settings** — plus **on demand from the menu**
  ("Opublikuj bazę na GitHubie" / your English menu wording).
- Phones: a fresh install has `shian1000/LeinaMusicDatabase` filled in; server first, GitHub
  second.
- Packages: files exported count as sent on the phone; the owner reviews imported requests as
  today.

## 1. The public export

A new step that builds `music.db` and `tag.db` for the public, in a temporary folder, from the
current databases (never touching the originals; follow Database safety).

- **Allow-list, not deny-list.** The export keeps only tables (and columns, where needed) on an
  explicit allow-list; anything new in the schema stays out until someone adds it on purpose.
  Today's shared copies hold (2026-10-21):
  - `music.db`: `songs`, `artists`, `albums`, `additional_song_artists`, `song_id_changes`,
    `bad_youtube_videos`, `rejected_song_requests`, `album_covers` (empty; has a `path` column —
    drop the column or the table if it can ever hold a local path), `schema_version`.
  - `tag.db`: `tags` (only `kind = 'marker'` rows today: `album_checked`, `spellchecked`),
    `song_tags`, `applied_song_changes`, `schema_version`.
- **Never published:** anything from `user.db` (accounts, password hashes, tokens, permissions,
  playlists, users' own moods, folders, covers, listens, saved songs), the inbox and its
  decisions, `files.db` (the owner's library layout; the phone needs it only with the server),
  local paths, and data whose licence forbids republishing (song lyrics from Genius — the shared
  `music.db` has no lyrics column today; keep it that way in the export).
  `tag.db`: only global moods (and, if you see no harm, the internal markers — your call; say
  which in your answer).
- **Ask the owner** about `songs.nostalgic`, `songs.melancholic`, `songs.party`: if these are the
  owner's personal ratings rather than catalog data, they may not belong in a public file.
- **Same schema as the server's copies**: the phone reads both with the same code, so the
  public files must keep every table and column the phone reads (see the app's
  `lib/src/data/song_catalog.dart`, `moods.dart`, `song_details.dart`) — empty rather than
  missing where something is withheld, if the phone would break otherwise. List anything you had
  to empty in your answer.
- **Self-check before upload:** after building, open both files and fail (publish nothing, log
  why) if any table isn't on the allow-list, any user-data table exists, any value looks like a
  local path (`/home/`, `/media/`, `smb://`, a drive letter), or the SQLite integrity check
  fails. Tests for this check matter more than for the rest.

## 2. Publishing to GitHub

- **Where:** the public repo `shian1000/LeinaMusicDatabase` — owner and repo name from `.env`
  (e.g. `GITHUB_DB_REPO=owner/repo`), with the token, never hard-coded; documented in
  `.env.example`.
- **One release with the fixed tag `database`** (create it the first time), whose assets are
  replaced on each publish. Phones download from
  `https://github.com/<owner>/<repo>/releases/download/database/<file>` — stable no matter what
  other releases the repo gets. Not files committed to git.
- **Assets:** `music.db`, `tag.db` (uncompressed is fine at this size; say so if you'd rather
  gzip them — the phone can handle `.gz`) and **`version.json`**, uploaded **last** so it never
  points at files not yet uploaded:

  ```json
  {"format": 1,
   "published_at": "2026-10-21T12:00:00Z",
   "files": {"music.db": {"size": 1032192, "sha256": "…"},
             "tag.db":   {"size": 348160,  "sha256": "…"}}}
  ```

  `published_at` in UTC. The phone reads it daily, downloads the databases only when a hash
  changed, and checks size and hash before swapping its copy.
- **"Only when changed":** compare with the last published `version.json`. Make sure an export
  of unchanged data gives the same bytes (or compare something stable instead) — otherwise the
  daily publish uploads every day for nothing.
- **Token:** a fine-grained GitHub token with *Contents: read and write* on that one repo only,
  in `.env` (`GITHUB_TOKEN` or a clearer name). Never logged, never in git. No token or no
  network → the daily run skips with a clear message and tries the next day; the menu entry
  says what's missing.
- **Settings:** the daily publish on/off (default on) where MusicDatabase keeps its settings
  (the agent before you added Settings › Server › "Folders and network" writing `.env` — a
  similar place fits). Show the last publish time and result.
- Use the GitHub REST API (`requests` is already pinned): get/create the release by tag, delete
  the old asset of the same name, upload the new one to `uploads.github.com`. Test it against a
  fake server, not GitHub.

## 3. Importing a request package

The phone (not built yet) will share a `.zip` holding its waiting outbox files, unchanged — the
same SQLite files the phone `PUT`s to `/inbox/<name>` today, named
`[<user>_]<date>_<time>_<number>.db` ([the outbox contract](musicdatabase-outbox.md)). A phone
without an account puts a **sender name the user typed** where the user part goes.

- **A menu entry "Import a request package"**: pick a `.zip` (a path; a file picker is nice to
  have), check it, put its files into the inbox, then process them as any other request — the
  owner reviews them as today.
- **Accept only what the inbox would accept over HTTP**: top-level `.db` files with valid inbox
  names, the inbox's per-file size limit, SQLite header present; a cap on file count and total
  uncompressed size (zip bombs); no directories, no `..`, no absolute paths, no symlinks.
  Refuse the whole package on anything else, saying why.
- **Same name already in the inbox** (a package imported twice): skip that file and say so —
  don't overwrite or duplicate.
- **Sender names:** the user part may be a name with no MusicDatabase account. Tell the phone in
  your answer which characters and length the name may have (the inbox's `USERNAME_PATTERN`?) so
  the phone can clean what the user types, and how such files show in the review (as from that
  name, marked as imported from a package).
- Auto-processing that already runs on inbox files (e.g. dead links resolved when MusicDatabase's
  own search agrees) may run on imported ones too — your call; say which.

## Done when

- The export + self-check, the publish (daily and from the menu) and the import exist, with
  tests (the self-check, "only when changed", the zip checks, a fake GitHub server).
- One real publish to `shian1000/LeinaMusicDatabase` worked — **ask the owner first**; the owner
  creates the token and puts it in `.env` (give them the exact steps on GitHub).
- Your answer hand-off states: the final asset names and `version.json` format, what the export
  keeps / empties, the sender-name rules, and anything the phone must know.
