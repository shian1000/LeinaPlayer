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
playing phone files with a mini/full player, a play queue (playlists, "Dodaj do kolejki",
shuffle, the queue screen, caching the next songs ahead; remembered across restarts) and a
media notification with previous/next (keeps playing in the background); play history in
"Ostatnie" (profile menu). YouTube: searching it on request, showing which songs
MusicDatabase links to a video, matching songs without a link on the phone, and streaming the
audio on Android through NewPipeExtractor, with a cache of played songs — see
[`youtube.md`](docs/agent-notes/youtube.md). Biblioteka: playlists imported from YouTube links
([`playlists.md`](docs/agent-notes/playlists.md)). YouTube links shared to the app or opened with
it import the playlist / play the video.

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
  counterpart where you do, and don't turn it into a full port kept in sync.
- The app gets MusicDatabase's data by downloading its SQLite files over HTTP
  ([ADR 0002](docs/decisions/0002-database-download.md)). Any other way of talking to it (an API,
  sending phone-found data back for review — the intended direction) is not decided — check with
  the user first, and record the decision as an ADR in `docs/decisions/`.

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
  `PlayingBars` — the animated "playing" mark).
- `lib/src/data/` — data: downloading MusicDatabase's files (`database_sync.dart`), reading
  `music.db` (`song_catalog.dart`), the phone's `local.db` and folder scan (`local_library.dart`),
  search over both (`combined_search.dart`), YouTube links given to the app
  (`incoming_links.dart`, `video_link.dart`), YouTube search / matching / audio
  (`youtube_search.dart`, `youtube_matcher.dart`, `youtube_audio.dart`), phone-found YouTube
  links and the audio cache (`youtube_library.dart`), play history (`play_history.dart`,
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
- `test/` — widget/unit tests, mirrors `lib/`.
- `tool/` — scripts run on the computer: `youtube_match_benchmark.dart`, `generate_icons.py`
  (draws the app icon and writes every Android/iOS size — rerun it instead of editing the PNGs).
- `android/`, `ios/` — platform projects generated by `flutter create`. Avoid hand-editing
  generated platform files unless a specific platform integration requires it. Hand-written:
  `android/app/src/main/kotlin/.../NewPipeBridge.kt` (NewPipeExtractor behind a method channel),
  `MainActivity.kt` (extends `AudioServiceActivity` for background playback; `LinksBridge`:
  incoming YouTube links and opening the YouTube app by package),
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
  `LocalLibraryScope`, `YouTubeLibraryScope`, `PlaylistLibraryScope`, `PlayHistoryScope`,
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
- No comments explaining *what* code does; only *why*, when non-obvious.

## Testing & verification

- Run `flutter analyze` and `flutter test` before considering a change complete.
- For UI changes, actually run the app and look at it — a green test suite does not confirm the
  screen looks right. Use the `run-on-physical-phone` skill (release build on the USB Huawei, with
  the Gradle memory precautions) or `share-build-tailscale` for the user's Pixel 7a; check screens
  with `adb exec-out screencap`. `uiautomator dump` hangs on screens with running animations
  (e.g. while music plays) — use screenshots there. The Huawei runs Android 10, so background
  restrictions of Android 12+ (foreground-service starts, app freezing) only show on the Pixel;
  it can be reached remotely over Tailscale with wireless debugging (the user pairs; the pairing
  and connect ports are random — scan 30000–49999 with `nc -z` if they aren't given).
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
  benchmark, NewPipe playback (build requirements, 403s), remembered matches and the audio cache
  (why it downloads in 1 MB ranges), what's not done.
- [`playlists.md`](docs/agent-notes/playlists.md) — Biblioteka playlists: `local.db` tables,
  YouTube import (fetching, title parsing, recognising songs by video first), R8 rules.
- [`ui-sizing.md`](docs/agent-notes/ui-sizing.md) — font sizes/spacing are calibrated against the
  reference app; why there's no screen-size scaling.

As the app grows other non-obvious subsystems (networking layer, caching, auth), add a short note
per topic there rather than growing this file indefinitely.
