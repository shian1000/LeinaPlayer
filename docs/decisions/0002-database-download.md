# 0002 - Getting MusicDatabase data: download the SQLite files over HTTP

## Status

Accepted (2026-10-10)

## Context

ADR 0001 deferred how this app talks to MusicDatabase. The first feature needing real data is
searching the user's library on the phone. MusicDatabase keeps everything in two SQLite files,
`music.db` and `tag.db` (in `../MusicDatabase/src/database/`), and has no server or API.

## Decision

- The app downloads `music.db` and `tag.db` as whole files from an address the user types in
  under "Ustawienia › Źródła muzyki › Baza danych" (`lib/src/data/database_sync.dart`). The
  address is the folder the files sit in; the app appends the file names. Nothing about the
  server is hard-coded — e.g. `python3 -m http.server` in that folder, reached over Tailscale.
- Two addresses can be set: a remote one (e.g. over Tailscale) and a local one for the home
  network, plus the home Wi-Fi's name (SSID), picked with "Użyj bieżącego połączenia". When the
  phone is on that Wi-Fi the local address is tried first and the remote one is the fallback;
  elsewhere only the remote one is used. Reading the SSID needs location permission and location
  turned on (Android rule; `network_info_plus` + `permission_handler`) — without it the phone
  can't tell it's at home and just uses the remote address. "Użyj bieżącego połączenia" also scans
  the phone's /24 subnet for a server answering `music.db` on the remote address's port and saves
  the first hit as the local address. The remote address keeps the
  original `shared_preferences` key, so phones set up before this change keep working.
- Plain HTTP and HTTPS are both accepted. Android's `usesCleartextTraffic` is on because the
  expected server is plain HTTP on the tailnet, where Tailscale already encrypts traffic.
- Download happens once per calendar day, the first time the app starts or comes back to the
  foreground that day, plus right after the address is saved and on "Pobierz teraz". Only
  successful downloads count as "done today".
- Both files are downloaded to `*.part`, checked for the SQLite header, and only then renamed
  over the previous copy, so a failed download keeps the last good pair.
- Addresses, Wi-Fi name, last-download time and its source are kept in `shared_preferences`; files live in
  `<application support dir>/database/`.

## Consequences

- `permission_handler` requires compiling against Android API 37, so
  `android/app/build.gradle.kts` sets `compileSdk = maxOf(flutter.compileSdkVersion, 37)`
  (`targetSdk` unchanged). Don't drop it back to Flutter's default while that package is used.
- The local server must listen on the computer's LAN address, not only on its Tailscale address,
  or the local address can't work.
- The phone reads MusicDatabase's schema directly once search is built, so that code depends
  on MusicDatabase's table layout. Keep it read-only and isolated in `lib/src/data/`; schema
  changes there must be mirrored here.
- Reading the files needs an SQLite package: `sqflite` (plus `sqflite_common_ffi` for tests on
  the desktop). Song search (`lib/src/data/song_catalog.dart`) reads `songs`, `artists` and
  `additional_song_artists` from `music.db`; `tag.db` is downloaded but not read yet.
- iOS would also need an App Transport Security exception for plain HTTP; not configured,
  since only Android is released.
- Whole-file download is fine at the current size (well under 1 MB); if the databases grow a
  lot, revisit (conditional requests, compression or an API in MusicDatabase).
