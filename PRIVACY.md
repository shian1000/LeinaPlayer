# Privacy — Leina Radio

As of 21 October 2026. The same, shorter, is in the app: **Ustawienia › Prywatność i
połączenia** — there each entry shows whether the app connects to it right now, with a way to
the switch that turns it off. (The app's interface is in Polish; screen names below are quoted
as they appear in it.)

## In short

- **No ads, no analytics, no crash reporting.** The app contains no library that sends data on
  its own (such as Firebase or Crashlytics).
- **Your data stays on the phone**: your library (playlists, moods, folders, liked songs, songs
  saved for later), listening stats, history and settings — unless you log in to a MusicDatabase
  server yourself.
- **The app only connects when a feature needs it** — one you use or one you have switched on.
  Almost every automatic connection can be switched off.
- **Every service the app connects to sees the phone's IP address** — as with any connection on
  the internet. It gets nothing that identifies you unless stated otherwise below.

## What the app connects to, and why

| Who | What for | When | What it gets | How to turn it off |
|---|---|---|---|---|
| **MusicDatabase server** (if you set one) | the song catalog, music files from the server's library, correction reports, account sync | once a day and on changes | correction reports; **only when logged in**: playlists, moods, folders, covers, liked songs, songs and links saved for later (with the name of whoever sent the link) and every play (what, when, for how long, from where) | don't set a server, or don't log in (Ustawienia › Serwer, › Konto) |
| **GitHub** | the public copy of the song catalog (when no server answers); checking for a new version of the app | once a day when the app opens | nothing beyond the request itself | Ustawienia › Serwer › "Pobieraj z GitHuba"; Informacje i pomoc › "Sprawdzaj aktualizacje automatycznie" |
| **YouTube (Google)** | searching videos, matching songs to videos, importing playlists and playback | when you search, import or play a song from YouTube | video and playlist ids, the text you search for (title, artist) — no account, no login | playback sources (Ustawienia › Odtwarzanie), search (Ustawienia › YouTube) |
| **YouTube Data API (Google)** | official search | only if you enter your own API key | the text you search for and your key | don't enter a key |
| **Google account** | "Utwórz na YouTube" — a playlist on your YouTube account | only when you use it | the playlist's name and its videos; Google knows which account signed in. The app keeps only the e-mail address | Ustawienia › Konto › "Wyloguj" |
| **Spotify** | importing playlists, albums and tracks from links; searching Spotify playlists | when you open a Spotify link or search for playlists | the playlist / album / track id or the text you search for (and your API key, if you enter one) | Ustawienia › Spotify |
| **iTunes (Apple), Deezer, YouTube thumbnails** | album covers | for songs without a cover in the file (the result is cached) | artist and album (or title), or a video id | Ustawienia › Okładki albumów (each source separately); Oszczędzanie danych › Wi-Fi only |
| **LRCLIB** (a community project) | song lyrics | while the full player is open | title, artist, album and length of the song | Oszczędzanie danych › "Pobieraj teksty piosenek" |
| **Browser and "Udostępnij" (share)** | links (MusicBrainz, Apple Music, Deezer, Spotify, GitHub), the correction-report package, a problem report ("Zgłoś problem": app version, phone model, Android version, your description and the error log), shared links and summaries | only when you tap them | whatever you choose | — |

## Who sees your data

- **The owner of the MusicDatabase server** you connect to: your correction reports and, if you
  log in, your library and listening history. If you don't set a server, nobody.
- **Whoever you send a correction-report package to** ("Wyślij paczkę…"): the reports, signed
  with the name you typed.
- **Wherever you put a backup** (Ustawienia › Kopia zapasowa — a `.zip` you share yourself:
  Google Drive, e-mail, a computer): your playlists, moods, listening stats and history, liked
  and saved songs, links saved for later with their senders' names, and settings. Never the
  login, Google account or API keys.
- **Nobody else.** The names of people who sent you links saved for later stay on the phone (and,
  when logged in, on the server) — those people receive nothing.

## Where the data is and how to delete it

- On the phone, in the app's data: Android Settings › Apps › Leina Radio › Storage › "Clear
  data" deletes everything (as does uninstalling). The cache alone (songs, covers) is cleared in
  the app: Oszczędzanie danych › Pamięć podręczna.
- The error log ("Dziennik błędów") — what went wrong in the app over the last 14 days, for
  problem reports — is kept only on the phone, with tokens, passwords, server addresses (IP
  addresses, Tailscale and home-network names), your account name and YouTube's stream
  addresses cut out, and phone files named without their folders; it still names songs you
  played or searched for when something went wrong with them. It leaves the
  phone only in a report you send yourself. Informacje i pomoc › Dziennik błędów shows and clears
  it.
- On a MusicDatabase server: with its owner — deleting an account's data is arranged with them.

## Keys and passwords

- The MusicDatabase account password is not stored on the phone — the server returns a token
  instead.
- YouTube and Spotify API keys, if you enter them, stay on the phone only.
- Google sign-in is handled by Google Play services; the app never sees the password or token.

Questions and changes: open an issue in this app's GitHub repository.
