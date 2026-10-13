# 0006 - Logging in with a MusicDatabase user

## Status

Accepted (2026-10-13). Live on both sides since 2026-10-13: the sharing server runs with
`--users` (MusicDatabase's `account_auth.py`, `sharing_server.py`; its runbook "Logging in from
the phone"). Asked for in [`../handoffs/musicdatabase-login.md`](../handoffs/musicdatabase-login.md).

## Context

MusicDatabase has users (its ADR-0004: `Users/<username>/account.json` with a salted scrypt
password hash, created in main menu › Users); there is one so far. The phone needed a user name
for its outbox request files ([ADR 0005](0005-outbox-for-musicdatabase.md)), and later per-user
data (playlists, private tags in `user.db`) will need to know who the phone belongs to. The owner
asked for a login with just a username and a password.

## Decision (the owner's)

- **Where:** Ustawienia › Konto (the Spotify-like "Konto" entry, a dummy until now) is the login
  form — "Nazwa użytkownika", "Hasło", "Zaloguj" — and, once logged in, the user and "Wyloguj".
  The profile menu's header shows the user (or "Nie zalogowano" / "Zaloguj się"), "Dodaj konto"
  opens the same screen, the avatar shows the user's initial, and the "Wyloguj" button at the
  bottom of Ustawienia logs out (asking first) or reads "Zaloguj się" when logged out.
- **Checked on the server, with a token:** the phone sends the username and password to the
  sharing server (`POST /login`, same addresses as the database download). The server checks
  them against `account.json` and answers with a token. The phone keeps **the username and the
  token, never the password** (`shared_preferences`; `lib/src/data/account.dart`). Logging in
  needs the server; after that the phone works offline as before.
- The token goes with every request sent to the inbox (`Authorization: Bearer …`), so
  MusicDatabase knows who sent it; the username goes into the request file names
  (`<user>_<date>_<time>_<number>.db`) and `request.user_name`.
- The server answering 401 to the token (revoked, user renamed or deleted) asks the user to log
  in again (Konto shows it, the name stays filled in); waiting requests stay.
- What the server settled (beyond the hand-off): 5 failed logins in 15 minutes from one address
  or for one username lock both out for 5 minutes — `/login` answers 429 with `Retry-After`,
  shown as "spróbuj ponownie za N min". A request file named after a user needs that user's
  token (none or revoked → 401, another user's → 403); an unsigned name goes with or without a
  token. So the phone adds to a waiting request only if it was made by the same user (or, logged
  out, unsigned ones), and a 403 file waits for its own user while the rest are sent.
- "Wyloguj" forgets the login on the phone and asks the server (best effort) to revoke the token
  (`POST /logout`). Requests waiting in the outbox stay and keep the name they were made with.

## Consequences

- The password crosses the network in plain HTTP. Over Tailscale it's encrypted by the tunnel;
  on the home LAN it isn't — accepted for a household server (the same server already serves
  the databases unencrypted). Revisit if the server is ever reachable from elsewhere.
- The token is stored unencrypted on the phone (no secure-storage package); it only grants what
  this user can do on the server, and logging out revokes it.
- MusicDatabase's server (Python `http.server`) needs `Content-Length` on every body — a chunked
  one gets 411 and a closed connection, which the phone first showed as "Brak połączenia". Dart's
  `HttpClient` sends chunked unless `contentLength` is set, and a Dart test server accepts both:
  the tests' servers answer 411 to chunked bodies, like the real one.
- MusicDatabase usernames may contain `_` (`USERNAME_PATTERN`), so request file names may too;
  the inbox has to accept that (in the hand-off).
- Who the phone belongs to is now known; per-user data (`user.db`) can build on this login.
