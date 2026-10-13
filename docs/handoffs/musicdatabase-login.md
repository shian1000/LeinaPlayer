# Handoff for the MusicDatabase agent: logging in from the phone

**Status (2026-10-13):** done in MusicDatabase (`account_auth.py`, `sharing_server.py --users`;
tokens as SHA-256 in `Users/<name>/tokens.json`; 429 lockout after 5 failed logins; a named
request needs its user's token — 401 / 403; `_` accepted in file names). The phone handles all of
it ([ADR 0006](../decisions/0006-musicdatabase-login.md)).

Written by the MusicDatabaseApp agent (2026-10-13) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md` and ADR-0004 (per-user data)
first — their rules win over anything here. The sharing server is a contract with the app and
lives partly outside the repo: record changes in `~/system-docs/README.md` too. The app side is
decided in the app's [ADR 0006](../decisions/0006-musicdatabase-login.md).

## Why

The owner wants Leina Radio to log in with a MusicDatabase user (main menu › Users; one exists:
`owner`) — username and password only. The phone signs its inbox requests with that user, and
later per-user data (`user.db`) will build on it. Decided with the owner: the password is checked
**on the server**, which hands the phone a **token**; the phone keeps the token, never the
password.

## What the phone does (built)

All on the sharing server (port 8002, the same addresses as the database download), plain HTTP.

### `POST /login`

Request: `Content-Type: application/json`, body `{"username": "...", "password": "..."}` — the
username as typed (trimmed; may differ in case).

The phone understands:

| Answer | Meaning |
|---|---|
| 200, JSON `{"username": "<normalized>", "token": "<opaque>"}` | logged in; the phone keeps both and shows `username` |
| 401 | wrong username or password (don't say which) |
| 503 | the drive with `Users/` isn't mounted |
| 404 | (today) no login on this server |
| anything else / no answer | shown as an error; the next address is tried |

### `POST /logout`

Header `Authorization: Bearer <token>`, no body. The phone ignores the answer (best effort; it
forgets the login either way). Suggested: 204, also for an unknown token.

### `PUT /inbox/<file name>` — now with a token

When logged in, the phone adds `Authorization: Bearer <token>` to each upload. Without a login
it sends none (as today). The phone handles **401** as "log in again": it keeps the file and asks
the user to log in.

File names get the user part: `<username>_YYYY-MM-DD_HH-MM-SS_NNN.db`, with the username exactly as
`/login` returned it. **MusicDatabase usernames may contain `_`** (`USERNAME_PATTERN`), but the
inbox accepts only `A-Z a-z 0-9 -` there today — please accept `USERNAME_PATTERN` in the user
part (the date after it has a fixed shape, so a `_` in the name stays unambiguous, e.g.
`^(?:([a-z0-9][a-z0-9_-]{1,31})_)?\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_\d{3,9}\.db$`).
`request.user_name` inside the file holds the same name.

## What you decide, with the owner

1. **Tokens:** how they're made and kept — e.g. 32 random bytes, stored only as a hash next to
   `account.json` (not in `user.db`, which may be sent to the phone one day); no expiry, revoked
   by `/logout`, and when the password is changed, the user renamed or deleted (main menu ›
   Users).
2. **The inbox and tokens:** whether an upload *without* a token is still accepted (today's
   phones and any request made before logging in have none), whether a valid token's user must
   match the file name's user part, and recording who sent each request (for "Resolve new
   requests").
3. **Abuse limits:** e.g. slow down repeated failed logins.
4. Whether `/login` should also be possible when the user's folder is on an unmounted drive
   (today the phone treats 503 as "drive not mounted").

Tell the app's agent (via the owner) when it's live and anything that differs from the above.
