# Handoff for the MusicDatabase agent: a fresh setup that works for someone else

**Status (2026-10-21):** asked for; not built yet.

Written by the MusicDatabaseApp agent (2026-10-21) for an agent working in `../MusicDatabase`
(GitHub: `shian1000/LeinaMusicDatabase`, public). Read MusicDatabase's own `AGENTS.md` first
(database safety, Machine settings / `.env`, Git policy — nothing private in git; everything on
GitHub in English) and `docs/runbooks/database.md`. Their rules win over anything here. When done,
answer with a hand-off of your own in `docs/handoffs/` (like `public-database-for-musicdatabaseapp.md`).

## Why

A friend of the owner wants to run his own MusicDatabase server for Leina Radio, starting from the
owner's catalog and extending it. He has **Debian** (version unknown yet: Debian 13 ships Python
3.13, Debian 12 ships 3.11 — the project needs ≥ 3.13). Windows is not needed now (it's a separate,
later item; don't make Linux-only things worse, but don't port either).

A review of the repo from a newcomer's point of view (2026-10-21) found that a fresh clone can't
work today. The owner will test the result on a second Linux machine (Linux Mint) by following
the README literally, then the friend will.

## 1. A fresh clone has no database (blocker)

`docs/runbooks/database.md` › Known gap: `create_music_db()` / `create_tag_db()` exist but are
never called; with no `src/database/*.db` the app has nothing to open.

- On start, when the databases are missing, **ask once**: download the public catalog (the owner's
  `music.db` / `tag.db` from the GitHub release `database` — the same files and `version.json`
  your publishing writes; repository from `GITHUB_DB_REPO`, defaulting to
  `shian1000/LeinaMusicDatabase`) or start with an empty database. Verify the download against
  `version.json` (size, SHA-256) before using it.
- The public copy is an allow-list export (empty `album_covers.path`, only mood tags in
  `tag.db`): make sure the app runs normally on it — migrations apply on top, `files.db` is built by
  the library scan, nothing expects the owner's markers. Say in your answer anything that differs
  from the owner's own database.
- Empty start: the real schema with all migrations, through the code's normal path (no hand-made
  SQL).
- Tests for both paths (the download against a local fake server, never GitHub).

## 2. Sharing without an external drive (blocker)

The sharing server, users, inbox and mood changes only work while `SHARING_DRIVE_MOUNT` is a
mounted drive (`os.path.ismount`). The owner's data lives on an external SSD, but a friend may have
everything on one disk; then the server reports "not mounted" forever.

- Allow `SHARING_DIR` without a separate drive: e.g. an empty `SHARING_DRIVE_MOUNT` means "no
  external drive — just check `SHARING_DIR` exists and is writable". Keep today's behaviour (and
  its protection against writing into an empty mount point) when a mount is set. Update
  `.env.example`, Settings › Server › "Folders and network", the messages and the tests.

## 3. `MusicDatabase.sh` only knows Konsole

It relaunches itself in `konsole` (KDE) when started without a terminal. Debian with GNOME and Linux
Mint don't have it: try `x-terminal-emulator` (Debian's alternatives), then `gnome-terminal`,
`konsole`, `xfce4-terminal`, `xterm` — the first that exists; with none, say so.

## 4. README for a new user on Debian (the owner's checklist 6.2)

Rewrite `README.md` (English) so someone who has never seen the project can set it up by following
it literally:

- what MusicDatabase is, and how it relates to Leina Radio (the phone app,
  `shian1000/LeinaPlayer`);
- **requirements**: Debian/Ubuntu/Mint, Python ≥ 3.13 (Debian 12: how to get it — e.g. `uv` or
  pyenv; Debian 13: the system one), system packages (`git`, `python3-venv`, anything else the
  pinned requirements need to build), optional Google Chrome (which features use it), optional
  Tailscale (reaching the server from outside the home network);
- **install**: `git clone https://github.com/shian1000/LeinaMusicDatabase.git`, then
  `cd LeinaMusicDatabase` (today's README says `cd MusicDatabase` — wrong), venv, requirements,
  `.env` from `.env.example` or the in-app settings;
- **first run**: the database choice from point 1;
- **serving Leina Radio phones**: setting the folders, turning on sharing (the systemd user
  service, Settings › Server), creating a user, the address to type in the phone (Ustawienia ›
  Serwer in the app), port 8002, LAN and Tailscale; no router port forwarding;
- **optional keys and accounts**, each with what needs it and what works without: YouTube Data API
  key, the YouTube OAuth client (`.secrets/`), Genius / others the code uses, the GitHub token for
  publishing the public database;
- updating (`git pull`, migrations), tests, licence.

No private data (addresses, paths, account names). Point to `docs/` for depth rather than copying
it.

## Done when

- A fresh clone in an empty folder, on a machine without the owner's `.env`, starts, offers the
  public catalog, and with `SHARING_DIR` on the system disk serves `music.db` to a phone.
- Tests for points 1–2; the full suite green.
- Your answer hand-off: what changed, anything the phone side should know, and the README's
  requirements (so the owner's test on Linux Mint knows what to install).
