# AGENTS.md

## Project

MusicDatabaseApp — named **Leina Radio** on the phone (`lib/src/app_name.dart`; the package id
stays `music_database_app`) — is the mobile frontend for [MusicDatabase](../MusicDatabase) — a personal music
library / metadata enrichment tool. MusicDatabase today is a Python terminal app with a local
SQLite database and enrichment from MusicBrainz, Wikipedia, iTunes, and Genius.

This app is a Flutter client, targeting Android first, with iOS support kept buildable. It is
for private use only and is never published in an app store; the app is GPLv3
([ADR 0004](docs/decisions/0004-license-and-distribution.md)). It uses MusicDatabase's data and
supports MusicDatabase: when something is missing there (so far: YouTube links), the phone may
work it out itself with simplified local logic, kept only on the phone until MusicDatabase has
its own value ([ADR 0003](docs/decisions/0003-app-supports-musicdatabase.md)). The app must keep
working without the server.

Current state: navigation and menus are modelled on the Spotify Android app. Most leaf elements
are still dummies that show `Atrapa: <ID>`, and Home shows static placeholder data;
[`docs/menu-map.md`](docs/menu-map.md) lists every element and marks what's implemented. Real so
far: themes (Ustawienia › Wygląd), downloading MusicDatabase's `music.db` / `tag.db` from a remote
or home-network address ([ADR 0002](docs/decisions/0002-database-download.md)), scanning music
folders on the phone into the phone's own `local.db`, song search over both databases, and
playing phone files with a mini/full player, a play queue (playlists, "Dodaj do kolejki" /
"Odtwórz jako następny" for songs and whole playlists, each entry remembering the playlist it
was queued from, shuffle, the queue screen with reordering and swipe-to-remove, caching the next
songs ahead; remembered across restarts), dragging a song row right to queue it and a
media notification with previous/next (keeps playing in the background); scrolled down, the full
player shows everything music.db / tag.db / the phone know about the song (all of it for now,
to be trimmed later — user's request), and its own fields can be corrected there (the pencil),
going to the outbox for MusicDatabase while the phone keeps showing music.db's value; play history in
"Ostatnie" (profile menu). Album covers from the phone file, iTunes, Deezer or the YouTube
thumbnail, cached on the phone, with optional cover filters (Wygląd › Filtry do albumów);
playlists and moods show a collage of their songs' covers or a picture the user picked
(synced with the account) ([`covers.md`](docs/agent-notes/covers.md)). Every cache setting is in one screen, Oszczędzanie
danych i tryb offline › Pamięć podręczna. YouTube: searching it on request, showing which songs
MusicDatabase links to a video, matching songs without a link on the phone, and streaming the
audio on Android through NewPipeExtractor, with a cache of played songs — see
[`youtube.md`](docs/agent-notes/youtube.md). Biblioteka: playlists imported from YouTube or Spotify links
(Spotify: first 100 tracks; tracks whose video YouTube removed stay, to be searched again), with
a share sheet; song search also finds Biblioteka playlists, and its online button YouTube and
Spotify playlists, opened as a preview before saving; songs can be shared as their YouTube or Spotify link
([`playlists.md`](docs/agent-notes/playlists.md)). A logged-in user's playlists sync with their
MusicDatabase account, both ways ([ADR 0007](docs/decisions/0007-playlist-sync.md)).
Nastroje (moods): global ones from `tag.db` and the user's own (synced the same way; phone-only
while logged out), playing shuffled, songs added from any song's menu, found by name in song search; users with MusicDatabase's `edit_global_moods`
permission also edit global moods ([ADR 0008](docs/decisions/0008-moods.md)); a whole playlist,
mood or the queue can be put into a mood at once (after "Czy na pewno?"). A mood filter makes
the queue hide and pass over songs outside the ticked moods (or with a mood, for "Utwory bez
nastroju"); while it's on the full player shows a "Nastrój" button for the current song.
YouTube and Spotify links shared to the app or opened with it import the playlist / album or play
the video / track; a tapped link first shows a native sheet asking where to open it (Leina Radio,
the service's app, a browser; a choice can be remembered — Ustawienia › Otwieranie linków), or
saves it for later with the person who sent it (Menu profilu › Wiadomości › Na później,
`later_links.dart`; kept natively in `LaterLinks.kt`).

## Read order

1. This file.
2. [`docs/index.md`](docs/index.md) — documentation map.
3. [`docs/menu-map.md`](docs/menu-map.md) — every screen/menu element and its ID.
4. [`docs/architecture.md`](docs/architecture.md) — intended app structure as it grows.
5. `../MusicDatabase/AGENTS.md` — the backend this app will eventually talk to.

## Sources of truth

- Business logic, data model, and enrichment rules live in `MusicDatabase`; its values always
  win. This repo may only add deliberately simplified ("lite") logic to fill gaps locally, per
  [ADR 0003](docs/decisions/0003-app-supports-musicdatabase.md) — name the MusicDatabase
  counterpart where you do, and don't turn it into a full port kept in sync. On the phone this
  means: a value music.db has (a YouTube link, "N/A") always beats what the phone found itself;
  the phone's own findings only fill gaps and are dropped once music.db settles them — never
  the other way round (user agreed; see [`youtube.md`](docs/agent-notes/youtube.md)).
- The app gets MusicDatabase's data by downloading its SQLite files over HTTP
  ([ADR 0002](docs/decisions/0002-database-download.md)). What goes back is a request file in the
  phone's outbox ([ADR 0005](docs/decisions/0005-outbox-for-musicdatabase.md), `outbox.dart`; so
  far dead music.db YouTube links and the user's corrections of song / artist / album fields, each
  kind in files of its own), sent to MusicDatabase's inbox (`PUT /inbox/<name>` on the
  sharing server — the request format is a contract, see the
  [hand-off](docs/handoffs/musicdatabase-outbox.md)). The phone logs in with a MusicDatabase user
  (Ustawienia › Konto, `account.dart`; `POST /login` gives a token sent with the requests —
  [ADR 0006](docs/decisions/0006-musicdatabase-login.md); the server side is in a
  [hand-off](docs/handoffs/musicdatabase-login.md)). The account's playlists are exchanged as JSON
(`/users/<name>/playlists` — [ADR 0007](docs/decisions/0007-playlist-sync.md)), and so are its
moods (`/users/<name>/moods`), changes to global moods (`/global-moods/…`) and its permissions
(`GET /users/<name>`) — [ADR 0008](docs/decisions/0008-moods.md). Covers picked for playlists and moods go with them: the picture as
`/users/<name>/covers/<sha256>`, global moods' own covers as `/users/<name>/global-mood-covers`
([ADR 0009](docs/decisions/0009-cover-sync.md)). Any other way of talking to MusicDatabase is not decided — check with the user
  first, and record the decision as an ADR in `docs/decisions/`.

## Standard commands

```bash
flutter pub get              # install dependencies
flutter run                  # run on a connected device/emulator
flutter analyze              # static analysis — run before considering a change done
flutter test                 # run widget/unit tests
flutter build apk            # build a release Android APK
```

## Project layout

- `lib/main.dart` — app entry point.
- `lib/src/screens/` — one file per screen/sheet; `app_shell.dart` holds the bottom nav, drawer and
  per-tab navigators.
- `lib/src/widgets/` — shared widgets (placeholder cover art, menu bottom sheet, chips, headers,
  `SongTile` — the song row with source icons used by search, playlists, the queue and history;
  `showSongMenu` — a song's menu, opened by ⋮ and by a long press on any song row (new song
  lists get it by using `SongTile`, or call it from their own `onLongPress`);
  `PlayingBars` — the animated "playing" mark; `SwipeActions` — a row dragged sideways (right
  queues a song, left removes from the queue); `QueueToast` — the short note above the mini player after
  adding to the queue; `mood_sheet.dart` — "Dodaj do nastroju", "Nastrój dla wszystkich utworów", the "Filtr nastrojów" sheet and `moodIcon` (the crescent moon used for moods everywhere); `SongInfoCard` — everything about a song under the full player; `SongCover` — a song's album cover, with the cover
  filters from `cover_filters.dart`; `CollectionCover` — a playlist's or mood's cover (picked or
  collage); `color_picker.dart`; `TextInputDialog` in `common.dart`;
  `showShareSheet` in `share_sheet.dart`).
- `lib/src/data/` — data: downloading MusicDatabase's files (`database_sync.dart`), reading
  `music.db` (`song_catalog.dart`), the phone's `local.db` and folder scan (`local_library.dart`),
  search over both (`combined_search.dart`), requests for MusicDatabase waiting to be sent
  (`outbox.dart`), the logged-in MusicDatabase user (`account.dart`), YouTube and Spotify links given to the app
  (`incoming_links.dart`, `video_link.dart`), links saved for later from the link sheet
  (`later_links.dart`), YouTube search / matching / audio
  (`youtube_search.dart`, `youtube_matcher.dart`, `youtube_audio.dart`), phone-found YouTube
  links and the audio cache (`youtube_library.dart`), Spotify playlists, albums and tracks — fetching, and searching playlists
  (`spotify_playlist.dart`), playlists found by search (`playlist_search.dart`), syncing
playlists with MusicDatabase (`playlist_sync.dart`, used by `PlaylistLibrary.sync`), moods
  (`moods.dart`: global ones from tag.db, the user's own synced like playlists), the queue's
  mood filter (`mood_filter.dart`),
  a song's whole music.db / tag.db record (`song_details.dart`), covers the user picked for
  playlists and moods (`custom_covers.dart`),
  album covers and their cache
  (`album_covers.dart`), play history (`play_history.dart`,
  songs kept as `TrackRef`s from `track_ref.dart`), music source settings, playback order and
  queue caching (`source_settings.dart`), telling "no connection" from other failures
  (`network_errors.dart`), and the port of MusicDatabase's `normalize()` (`text_normalizer.dart`).
- `lib/src/playback/` — `PlayerController` (`just_audio`, one song), `PlaybackQueue` (what plays
  next), `TrackPlayer` (plays one song from the user's preferred source, no UI), `QueueSession`
  (the queue and position saved across restarts) and `YouTubePlayback` (the user's ordered ways
  of playing a YouTube video). Never pause between songs — see
  [`local-library.md`](docs/agent-notes/local-library.md) (Android 12+ freezes the app).
- `lib/src/theme.dart`, `lib/src/theme_controller.dart` — themes and the appearance settings.
- `lib/src/dummy.dart` — `showDummy()`, used by every not-yet-implemented element.
- `lib/src/sample_content.dart` — static placeholder content.
- `test/` — widget/unit tests, mirrors `lib/`; `test/support/` holds shared test helpers.
- `tool/` — scripts run on the computer: `youtube_match_benchmark.dart`, `generate_icons.py`
  (draws the app icon and writes every Android/iOS size — rerun it instead of editing the PNGs).
- `android/`, `ios/` — platform projects generated by `flutter create`. Avoid hand-editing
  generated platform files unless a specific platform integration requires it. Hand-written:
  `android/app/src/main/kotlin/.../NewPipeBridge.kt` (NewPipeExtractor behind a method channel),
  `MainActivity.kt` (extends `AudioServiceActivity` for background playback; `LinksBridge`:
  incoming YouTube/Spotify links and opening the YouTube app by package),
  `LinkChooserActivity.kt` (the "Otwórz w…" sheet for tapped links), `LinkTargets.kt`,
  `LaterLinks.kt` (links saved for later),
  `android/app/proguard-rules.pro` and `android/app/src/main/res/raw/keep.xml`.
- `docs/` — documentation for humans and AI agents (see [`docs/index.md`](docs/index.md)).

## Coding conventions

- Follow standard Dart/Flutter style; keep `flutter analyze` clean (the default
  `analysis_options.yaml` from `flutter create` is the baseline — do not weaken its rules without
  discussion).
- Prefer `StatelessWidget`/`StatefulWidget` composition over premature abstraction. Do not
  introduce a state-management package (Provider, Riverpod, Bloc, etc.) or a networking layer
  until there is an actual feature that needs it.
- App-wide state is a `ChangeNotifier` created in `main.dart` and exposed through an
  `InheritedNotifier` scope (`ThemeScope`, `DatabaseSyncScope`, `SongCatalogScope`,
  `LocalLibraryScope`, `YouTubeLibraryScope`, `OutboxScope`, `AccountScope`, `PlaylistLibraryScope`, `MoodLibraryScope`, `MoodFilterScope`, `PlayHistoryScope`, `LaterLinksScope`,
  `AlbumCoversScope`, `CustomCoversScope`,
  `PlayerScope`,
  `PlaybackQueueScope`, `SourceSettingsScope`; plus
  `YouTubeScope`, an `InheritedWidget` so tests can swap YouTube search, audio and playlist
  fetching); no
  state-management package. Settings persist via `shared_preferences`.
- Screens never hard-code colours or font sizes: `context.palette` and `AppFontSize`
  ([`theming.md`](docs/agent-notes/theming.md), [`ui-sizing.md`](docs/agent-notes/ui-sizing.md)).
- System Back in `AppShell` pops tab routes directly (bypassing their `PopScope`), so a pushed
  sub-screen can't hand a result back through `pop` — pass a callback instead. Keep Flutter's
  `PredictiveBackPageTransitionsBuilder` out of the theme: on Android 16+ it lets a hidden tab
  route take the back gesture from whatever covers it (full player, root sheets, drawer).
- Anything new the phone stores to work offline (a cache) gets its settings in the
  `cache_settings_screen.dart` ("Pamięć podręczna" — the only name for it in the UI, not
  "cache"), not on the screen of the feature that fills it (user's decision).
- A `SnackBar` with an `action` stays until closed by hand in this Flutter version (`persist`
  defaults to true) and floats over whatever is pushed on top — pass `persist: false`. Notes about
  the queue use `QueueToast` above the mini player instead (Spotify-like, user's choice).
- No comments explaining *what* code does; only *why*, when non-obvious.

## Testing & verification

- Run `flutter analyze` and `flutter test` before considering a change complete.
- Tests waiting for real background work (files, SQLite, isolates, a local HTTP server) wait
  for the condition with `waitUntil` / `pumpUntil` from `test/support/waiting.dart` — never a
  fixed number of short sleeps: with the whole suite in parallel on this machine those timed out
  at random (a different test failing each full run).
- For UI changes, actually run the app and look at it — a green test suite does not confirm the
  screen looks right. Use the `run-on-physical-phone` skill (release build on the USB Huawei, with
  the Gradle memory precautions) or `share-build-tailscale` for the user's Pixel 7a; check screens
  with `adb exec-out screencap`. To check a gesture mid-way, hold it with
  `input motionevent DOWN/MOVE … ` and screenshot before `UP` (each adb call takes ~0.2 s, so
  apps with long-press menus — Spotify — read it as a long press). `uiautomator dump` hangs on screens with running animations
  (e.g. while music plays) — use screenshots there. The Huawei runs Android 10, so background
  restrictions of Android 12+ (foreground-service starts, app freezing) only show on the Pixel;
  it can be reached remotely over Tailscale with wireless debugging (the user pairs; the pairing
  and connect ports are random — scan 30000–49999 with `nc -z` if they aren't given). The
  Huawei has only a swipe lock: wake it (`input keyevent KEYCODE_WAKEUP`) and unlock it with
  `input swipe 540 1800 540 600 300` rather than waiting for the user. It also shows no app logs
  (`logcat -s flutter` stays empty) — diagnose there from the screen.
- The user's MusicDatabase `sharing_server.py` (systemd service) listens on port 8002 on both the
  Tailscale and LAN addresses. Run test servers on another port and stop them by their own PID —
  never by "whatever listens on the port".

## Git policy

- This is a separate git repository from `MusicDatabase`; do not assume shared history or try to
  reference `MusicDatabase` commits from here.
- Only commit when explicitly asked. Do not push to any remote — the user pushes via their own
  IDE (VS Code or Android Studio).

## Topic notes (`docs/agent-notes/`)

- [`theming.md`](docs/agent-notes/theming.md) — themes (Dummify, Lain), `context.palette`, how to add
  one.
- [`local-library.md`](docs/agent-notes/local-library.md) — phone music scan, matching files to
  MusicDatabase (tags first — user's decision), `local.db`, search availability (incl. YouTube
  links), playback order, playback limits.
- [`youtube.md`](docs/agent-notes/youtube.md) — YouTube search methods, the lite matcher and its
  benchmark, NewPipe playback (build requirements, 403s), remembered matches, "not found" and
  removed videos, server-wins rule, the audio cache (why it downloads in 1 MB ranges), links
  given to the app and the native "Otwórz w…" sheet (incl. "Zapisz na później"), what's not done.
- [`playlists.md`](docs/agent-notes/playlists.md) — Biblioteka playlists: `local.db` tables,
  YouTube import (fetching, title parsing, recognising songs by video first), Spotify import (the
  embed page, 100-track limit, albums, track links), searching playlists (Spotify key / anonymous web-player search
  and its changing hash), previews, sharing, R8 rules.
- [`covers.md`](docs/agent-notes/covers.md) — album covers: sources and their order, matching,
  rate limits, the cover cache, the MusicDatabase hand-off, playlist/mood collages and picked
  covers.
- [`ui-sizing.md`](docs/agent-notes/ui-sizing.md) — font sizes/spacing are calibrated against the
  reference app; why there's no screen-size scaling.

As the app grows other non-obvious subsystems (networking layer, caching, auth), add a short note
per topic there rather than growing this file indefinitely.
