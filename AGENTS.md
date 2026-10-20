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

Current state: navigation and menus are modelled on the Spotify Android app. No element is a
dummy (the old `Atrapa: <ID>` snackbar) any more — what couldn't be built was removed (user's
decision, 2026-10-16); [`docs/menu-map.md`](docs/menu-map.md) lists every element. Home's
recommendation rows come from the listening stats and music.db (`home_recommendations.dart`). Real so
far: themes (Ustawienia › Wygląd), downloading MusicDatabase's `music.db` / `tag.db` from a remote
or home-network address ([ADR 0002](docs/decisions/0002-database-download.md)), scanning music
folders on the phone into the phone's own `local.db`, song search over both databases, and
ticking several songs with a long press for a shared action (queue, playlist, mood),
playing phone files with a mini/full player, streaming a song's file from MusicDatabase's
music library on the server when its `files.db` knows one (source "Serwer";
[ADR 0010](docs/decisions/0010-server-files.md)), a play queue (playlists, "Dodaj do kolejki" /
"Odtwórz jako następny" for songs and whole playlists, each entry remembering the playlist it
was queued from, shuffle, the queue screen with reordering and swipe-to-remove, caching the next
songs ahead; remembered across restarts), crossfading into the next song (Ustawienia ›
Odtwarzanie, 0–12 s), dragging a song row right to queue it and a
media notification with previous/next (keeps playing in the background); scrolled down, the full
player shows everything music.db / tag.db / the phone know about the song (all of it for now,
to be trimmed later — user's request), and its own fields can be corrected there (the pencil),
going to the outbox for MusicDatabase while the phone keeps showing music.db's value — except
its YouTube link and music video link, which the phone uses at once; with a music video the
player's YouTube button asks song or music video; play history in
"Ostatnie" (the "Ja" tab). Listening stats like Spotify's (Ja › Statystyki słuchania,
[ADR 0012](docs/decisions/0012-listening-stats.md)): every play with how long it was really
heard, counted from that version on and synced with the account; top songs / artists / albums
and shares over 4 weeks – everything, the week's highlights, and Wrapped-like cards for each
year and season (meteorological), the last one shared as a picture. Album covers from the phone file, iTunes, Deezer or the YouTube
thumbnail, cached on the phone, with optional cover filters (Wygląd › Filtry do albumów);
playlists and moods show a collage of their songs' covers or a picture the user picked
(synced with the account) ([`covers.md`](docs/agent-notes/covers.md)). Names in another
alphabet are shown with their Latin form, "Кино (Kino)" (Wygląd › "Nazwy w alfabecie
łacińskim"): only music.db's `title_latin` / `name_latin` columns or an artist's Latin synonym,
never transliterated on the phone (user's decision); the forms are sent as field corrections
([hand-off](docs/handoffs/musicdatabase-latin-names.md)). Every cache setting is in one screen, Oszczędzanie
danych i tryb offline › Pamięć podręczna. YouTube: searching it on request, showing which songs
MusicDatabase links to a video, matching songs without a link on the phone, and streaming the
audio on Android through NewPipeExtractor, with a cache of played songs — see
[`youtube.md`](docs/agent-notes/youtube.md). Biblioteka: playlists imported from YouTube or Spotify links or saved from the queue
(Spotify: first 100 tracks; tracks whose video YouTube removed stay, to be searched again), with
a share sheet; playlists made on the phone (empty, or from songs via "Dodaj do playlisty"); songs removed from
any saved playlist ("Usuń z tej playlisty"; an imported one's next import leaves them out, synced);
folders for playlists and moods (synced with the account like playlists —
[ADR 0011](docs/decisions/0011-folder-sync.md)) and a working
"Sortuj wg" (phone only); song search also finds Biblioteka playlists and albums (grouped by name, as "Przejdź do albumu" does), and its online button YouTube and
Spotify playlists, opened as a preview before saving; songs can be shared as their YouTube or Spotify link
([`playlists.md`](docs/agent-notes/playlists.md)). A logged-in user's playlists sync with their
MusicDatabase account, both ways ([ADR 0007](docs/decisions/0007-playlist-sync.md)).
The layout follows Juxtopposed's Spotify redesign
([`ideas/`](docs/ideas/spotify-redesign-juxtopposed.md)): tabs Home, Odkrywaj, Wyszukaj,
Biblioteka, Ja (the profile, no avatar or drawer); Home's rows arranged by the user (pin, move,
hide, rows from Biblioteka — `home_layout.dart`); Odkrywaj — one song at a time from all of
MusicDatabase or a mood; Biblioteka as categories, with "Polubione utwory" (liked in the
"Dodaj do playlisty" sheet / submenu — the full player's ⊕ turns into an accent ✓, Spotify-like),
songs saved "Na później" (both `saved_songs.dart`, synced with the account —
[ADR 0013](docs/decisions/0013-saved-songs-sync.md)) and dynamic playlists — a saved search filter
(`smart_playlists.dart`, phone only); the queue opens in place of the full player's cover, and lyrics (looked
up by the phone on LRCLIB, `lyrics.dart`, in memory only) are a card under the player, above
"Informacje o utworze" (user's layout: bottom row YouTube, mood filter, share, queue, ⋮; a mood
button where "Polub" was); song menus unfold "Dodaj do playlisty ›" / "Przejdź do
wykonawców ›" in place; Wyszukaj's "Przeglądaj" is grouped (moods, genres, decades, languages,
countries).
Full albums — music.db rows that are a whole album in one recording (`songs.kind`,
`SongKind`) — are marked "Cały album", can be filtered in search, are left out of the radio,
Odkrywaj and Przeglądaj's lists, are looked for on YouTube only as long "full album" videos,
and are marked from Informacje o utworze ([hand-off](docs/handoffs/musicdatabase-song-kind.md)).
Changing a song's artist there is a proposal of another artist for that song (`songs.artist_id`
with a name), never a rename of the shared artist row — that's the separate "Popraw pisownię
nazwy" ([hand-off](docs/handoffs/musicdatabase-song-artist.md)), which asks first when the new
name doesn't resemble the old one (`nameResembles`).
Playback extras: Powtarzaj (off / wszystkie / utwór, `PlaybackQueue.setRepeat`), Wyłącznik
czasowy (song menu), a song's radio (phone-side alikeness by artist, genre — music.db's
`songs.genre`, [hand-off](docs/handoffs/musicdatabase-genres.md) — moods, language, country,
decade; `song_radio.dart`), "Pobierz" for a song or playlist (kept offline for good; a queue in
`local.db` that resumes, under a foreground service — `playback/downloads.dart`), "Ukryj utwór"
(phone only). Playlists made on the phone: Dodaj / Edytuj; every saved playlist: Sortuj.
Ustawienia has a search; Biblioteka a grid view; Home's recommendation rows come from the stats.
Nastroje (moods): global ones from `tag.db` and the user's own (synced the same way; phone-only
while logged out), playing shuffled, songs added from any song's menu, found by name in song search; users with MusicDatabase's `edit_global_moods`
permission also edit global moods ([ADR 0008](docs/decisions/0008-moods.md)); a whole playlist,
mood or the queue can be put into a mood at once (after "Czy na pewno?"). A mood filter makes
the queue hide and pass over songs outside the ticked moods (or with a mood, for "Utwory bez
nastroju"); while it's on the full player shows a "Nastrój" button for the current song.
YouTube and Spotify links shared to the app or opened with it import the playlist / album or play
the video / track; a playlist with no link (made on the phone, a MusicDatabase folder) can be
made on YouTube from its share sheet — the phone signs in to Google and uses the YouTube Data API
itself, without MusicDatabase (unlisted, a one-off copy; [`youtube.md`](docs/agent-notes/youtube.md));
a tapped link first shows a native sheet asking where to open it (Leina Radio,
the service's app, a browser; a choice can be remembered — Ustawienia › Otwieranie linków), or
saves it for later with the person who sent it (Ja › Na później,
`later_links.dart`; kept natively in `LaterLinks.kt`, synced with the account from Dart — ADR 0013).

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
  far dead music.db YouTube links, videos the phone found for songs music.db has no link for,
  the user's corrections of song / artist / album fields — incl. YouTube links set by hand — and
  songs played that music.db doesn't have, asked to be added (`song_requests.dart`; ones
  MusicDatabase's owner rejected come back in music.db's `rejected_song_requests` and aren't
  asked for again); each kind in files of its own), sent to MusicDatabase's inbox (`PUT /inbox/<name>` on the
  sharing server — the request format is a contract, see the
  [hand-off](docs/handoffs/musicdatabase-outbox.md)). The phone logs in with a MusicDatabase user
  (Ustawienia › Konto, `account.dart`; `POST /login` gives a token sent with the requests —
  [ADR 0006](docs/decisions/0006-musicdatabase-login.md); the server side is in a
  [hand-off](docs/handoffs/musicdatabase-login.md)). The account's playlists are exchanged as JSON
(`/users/<name>/playlists` — [ADR 0007](docs/decisions/0007-playlist-sync.md)), and so are its
moods (`/users/<name>/moods`), changes to global moods (`/global-moods/…`) and its permissions
(`GET /users/<name>`) — [ADR 0008](docs/decisions/0008-moods.md). Covers picked for playlists and moods go with them: the picture as
`/users/<name>/covers/<sha256>`, global moods' own covers as `/users/<name>/global-mood-covers`
([ADR 0009](docs/decisions/0009-cover-sync.md)). The music library's files are streamed from
`GET /library/<files.id>` ([ADR 0010](docs/decisions/0010-server-files.md)). Biblioteka's folders go as JSON too
(`/users/<name>/folders`, [ADR 0011](docs/decisions/0011-folder-sync.md); server side in a
[hand-off](docs/handoffs/musicdatabase-folders.md)); its sort order and "last opened" stay on the
phone (`library_folders.dart`), not synced. Liked songs and songs saved "Na później" go as
`/users/<name>/saved-songs`, links saved "Na później" as `/users/<name>/later-links`, one item at a
time ([ADR 0013](docs/decisions/0013-saved-songs-sync.md); server side in a
[hand-off](docs/handoffs/musicdatabase-saved-songs.md)). Any other way of talking to MusicDatabase is not decided — check with the user
  first, and record the decision as an ADR in `docs/decisions/`.

## Standard commands

```bash
flutter pub get              # install dependencies
flutter run                  # run on a connected device/emulator
flutter analyze              # static analysis — run before considering a change done
flutter test                 # run widget/unit tests
tool/build_release_apk.sh    # build the release APK — always this, not a bare `flutter build apk`
                             # (signed with the release key from android/key.properties — signing.md)
```

The release build is numbered by `tool/build_info.sh`: build number = commit count (Android needs
it to grow), plus the short commit hash with "+zmiany" when `lib/`, `android/` or the pubspec
files differ from it — shown in Informacje i pomoc (`GIT_COMMIT` dart-define). Only the "1.0.0"
part of `version:` in `pubspec.yaml` is bumped by hand; leave its `+1` alone.

## Project layout

- `lib/main.dart` — app entry point.
- `lib/src/screens/` — one file per screen/sheet; `app_shell.dart` holds the bottom nav and
  per-tab navigators.
- `lib/src/widgets/` — shared widgets (placeholder cover art, menu bottom sheet, chips, headers,
  `SongTile` — the song row with its source icon (the first source in the playback order that has it, "*" when not in MusicDatabase, a pin when playable offline) used by search, playlists, the queue and history;
  `showSongMenu` — a song's menu, opened by ⋮ (and a long press outside a selection area);
  `SongSelectionArea` in `song_selection.dart` — wrap a song list's body in it and a long press on
  a `SongTile` starts ticking songs, with a bar of actions for all of them (new song lists should
  use it); `showAddToPlaylistSheet` in `playlist_picker.dart`; `youtube_export_dialog.dart` — "Utwórz na YouTube"; `folder_sheet.dart` — "Przenieś do
  folderu" for Biblioteka;
  `PlayingBars` — the animated "playing" mark; `SwipeActions` — a row dragged sideways (right
  queues a song, left removes from the queue); `QueueToast` — the short note above the mini player after
  adding to the queue; `mood_sheet.dart` — "Dodaj do nastroju", "Nastrój dla wszystkich utworów", the "Filtr nastrojów" sheet and `moodIcon` (the crescent moon used for moods everywhere); `SongInfoCard` — everything about a song under the full player (also from a song's menu, `showSongInfoSheet`); `SongCover` — a song's album cover, with the cover
  filters from `cover_filters.dart`; `CollectionCover` — a playlist's or mood's cover (picked or
  collage); `color_picker.dart`; `TextInputDialog`, `pluralWord` (Polish plurals) and
  `dayMonthLabel` in `common.dart`; `listening_charts.dart` — the stats' hour and month charts;
  `showShareSheet` in `share_sheet.dart`; `sleep_timer_sheet.dart` — "Wyłącznik czasowy"; `song_names.dart` — `shownTitle` / `shownArtist` /
  `shownAlbum`, a song's names as screens show them, with the Latin form when switched on).
- `lib/src/data/` — data: downloading MusicDatabase's files (`database_sync.dart`), reading
  `music.db` and `files.db` (`song_catalog.dart`), the phone's `local.db` and folder scan (`local_library.dart`),
  search over both (`combined_search.dart`), requests for MusicDatabase waiting to be sent
  (`outbox.dart`), the logged-in MusicDatabase user (`account.dart`), YouTube and Spotify links given to the app
  (`incoming_links.dart`, `video_link.dart`), links saved for later from the link sheet
  (`later_links.dart`), YouTube search / matching / audio
  (`youtube_search.dart`, `youtube_matcher.dart`, `youtube_audio.dart`), making a YouTube
  playlist from a Biblioteka one (`youtube_account.dart` — Google sign-in, `youtube_api.dart`,
  `youtube_export.dart`), phone-found YouTube
  links and the audio cache (`youtube_library.dart`), Spotify playlists, albums and tracks — fetching, and searching playlists
  (`spotify_playlist.dart`), playlists found by search (`playlist_search.dart`), Biblioteka's
  folders (synced), sort order and "last opened" (`library_folders.dart`), songs saved for
  later and liked songs (`saved_songs.dart`, synced item by item with `item_sync.dart`'s `ItemSync`
  like the later links), songs hidden with "Ukryj utwór" (`hidden_songs.dart`), dynamic playlists (`smart_playlists.dart`), Home's row layout
  (`home_layout.dart`) — all three phone only, syncing
playlists with MusicDatabase (`playlist_sync.dart`, used by `PlaylistLibrary.sync`), moods
  (`moods.dart`: global ones from tag.db, the user's own synced like playlists), the queue's
  mood filter (`mood_filter.dart`),
  a song's whole music.db / tag.db record (`song_details.dart`), covers the user picked for
  playlists and moods (`custom_covers.dart`),
  album covers and their cache
  (`album_covers.dart`), play history (`play_history.dart`,
  songs kept as `TrackRef`s from `track_ref.dart`), the listening stats — plays with their
  listened time, synced (`listening_log.dart`), and what's computed from them
  (`listening_stats.dart`, `listening_highlights.dart`, `listening_summary.dart`), music source settings, playback order and
  queue caching (`source_settings.dart`), telling "no connection" from other failures
  (`network_errors.dart`), Latin forms of names in other alphabets (`latin_names.dart`), and the
  port of MusicDatabase's `normalize()` (`text_normalizer.dart`), lyrics from LRCLIB (`lyrics.dart`), server files kept with "Pobierz" (`server_downloads.dart`), and a song's radio — songs like it, phone-only (`song_radio.dart`).
- `lib/src/playback/` — `PlayerController` (`just_audio`, one song; two players only while
  crossfading), `PlaybackQueue` (what plays
  next), `TrackPlayer` (plays one song from the user's preferred source, no UI), `QueueSession`
  (the queue and position saved across restarts), `Downloads` ("Pobierz": songs and playlists kept on the phone for good), `YouTubePlayback` (the user's ordered ways
  of playing a YouTube video) and `ListeningTracker` (the listened time of each play, from
  `PlayerController.positionChanges`, for the stats). Never pause between songs — see
  [`local-library.md`](docs/agent-notes/local-library.md) (Android 12+ freezes the app).
- `lib/src/theme.dart`, `lib/src/theme_controller.dart` — themes and the appearance settings.
- `test/` — widget/unit tests, mirrors `lib/`; `test/support/` holds shared test helpers.
- `tool/` — scripts run on the computer: `build_release_apk.sh` and `build_info.sh` (the numbered release build), `youtube_match_benchmark.dart`, `generate_icons.py`
  (draws the app icon and writes every Android/iOS size — rerun it instead of editing the PNGs).
- `android/`, `ios/` — platform projects generated by `flutter create`. Avoid hand-editing
  generated platform files unless a specific platform integration requires it. Hand-written:
  `android/app/src/main/kotlin/.../NewPipeBridge.kt` (NewPipeExtractor behind a method channel),
  `MainActivity.kt` (extends `AudioServiceActivity` for background playback; `LinksBridge`:
  incoming YouTube/Spotify links and opening the YouTube app by package),
  `LinkChooserActivity.kt` (the "Otwórz w…" sheet for tapped links), `LinkTargets.kt`,
  `LaterLinks.kt` (links saved for later), `DownloadService.kt` (the "Pobieranie utworów"
  foreground service while "Pobierz" works — Dart's `download_notification.dart`),
  `android/app/proguard-rules.pro` and `android/app/src/main/res/raw/keep.xml`.
- `third_party/audio_service/` — a patched copy of audio_service 0.18.19 (`dependency_overrides`
  in `pubspec.yaml`): without the patch the notification's and lock screen's buttons die for
  good once Android stops the service while the app's engine lives on (seen on the Pixel after
  days). What and why: `third_party/audio_service/PATCHED.md`; keep it when upgrading the
  package unless the new release fixes it.
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
  `LocalLibraryScope`, `YouTubeLibraryScope`, `OutboxScope`, `AccountScope`, `YouTubeAccountScope`, `PlaylistLibraryScope`, `MoodLibraryScope`, `MoodFilterScope`, `PlayHistoryScope`, `ListeningLogScope`, `LaterLinksScope`, `LibraryFoldersScope`, `DownloadsScope`, `HiddenSongsScope`, `SavedSongsScope`, `LikedSongsScope`, `SavedSongsSyncScope`, `SmartPlaylistsScope`, `HomeLayoutScope`,
  `AlbumCoversScope`, `CustomCoversScope`,
  `PlayerScope`,
  `PlaybackQueueScope`, `SourceSettingsScope`; plus
  `YouTubeScope`, an `InheritedWidget` so tests can swap YouTube search, audio and playlist
  fetching); no
  state-management package. Settings persist via `shared_preferences`.
- A music.db song id kept by the phone or synced (plays, saved data) may be one MusicDatabase
  has since merged or deleted: look it up with `SongCatalog.current` (follows music.db's
  `song_id_changes`), not `byId`. MusicDatabase never remaps ids in what it stores for the phone.
- A new list the phone fills by itself from all of music.db (a radio, random picks, a browse
  category to play through) leaves out full albums (`CatalogSong.isFullAlbum`; `hitsWhere(…,
  fullAlbums: false)`); lists the user built or searched keep them (MusicDatabase's hand-off).
- Screens show a song's title / artist / album through `shownTitle` / `shownArtist` /
  `shownAlbum` (`song_names.dart`), never `hit.title` directly, so the Latin form setting
  reaches them; raw values stay for keys, matching, sharing text and requests to MusicDatabase.
- Lists sorted by a name (playlists, folders, moods, artists, track titles) use `compareNames`
  (`text_normalizer.dart`): numbers by value, so "2. Telefon" comes before "10. Pidvalia" —
  not `normalizeForSearch(a).compareTo(…)` (user's request; numbered names are common there).
- Screens never hard-code colours or font sizes: `context.palette` and `AppFontSize`
  ([`theming.md`](docs/agent-notes/theming.md), [`ui-sizing.md`](docs/agent-notes/ui-sizing.md)).
- System Back in `AppShell` pops tab routes directly (bypassing their `PopScope`), so a pushed
  sub-screen can't hand a result back through `pop` — pass a callback instead. Keep Flutter's
  `PredictiveBackPageTransitionsBuilder` out of the theme: on Android 16+ it lets a hidden tab
  route take the back gesture from whatever covers it (full player, root sheets).
- Anything new the phone stores to work offline (a cache) gets its settings in the
  `cache_settings_screen.dart` ("Pamięć podręczna" — the only name for it in the UI, not
  "cache"), not on the screen of the feature that fills it (user's decision).
- A `SnackBar` with an `action` stays until closed by hand in this Flutter version (`persist`
  defaults to true) and floats over whatever is pushed on top — pass `persist: false`. Notes about
  the queue use `QueueToast` above the mini player instead (Spotify-like, user's choice).
- `Scrollable.ensureVisible` scrolls every scrollable above the widget too — inside a card that
  scrolls on its own within a page (the lyrics under the full player) it drags the whole page
  along; scroll the inner controller to `RenderAbstractViewport.getOffsetToReveal` instead.
- Context menus are `showMenuSheet`: rare options go in `quickEntries` (a small block on top),
  and options with choices of their own unfold in place via `MenuSheetEntry.submenu` rather than
  opening a second sheet (Juxtopposed's redesign, user's choice).
- No dummy elements: a feature is built or its button is left out (user's decision; the old
  `showDummy` / `Atrapa:` snackbar is gone). A `MenuSheetEntry` needs an `onTap` unless it has a
  `submenu`.
- An in-flight map of futures (`_downloads[id] ??= work().whenComplete(...)`) must remove the
  entry in a block, `() { map.remove(id); }`: `() => map.remove(id)` returns that very future,
  which `whenComplete` then waits for — the download hangs forever.
- No comments explaining *what* code does; only *why*, when non-obvious.

## Testing & verification

- Run `flutter analyze` and `flutter test` before considering a change complete.
- Tests waiting for real background work (files, SQLite, isolates, a local HTTP server) wait
  for the condition with `waitUntil` / `pumpUntil` from `test/support/waiting.dart` — never a
  fixed number of short sleeps: with the whole suite in parallel on this machine those timed out
  at random (a different test failing each full run). In a widget test wait for what the screen
  shows, not for a notifier's field: `PlaylistLibrary.load` sets `playlists` before its second
  query and its `notifyListeners`, so waiting on the field let the test check the screen too
  early (and `find.text` also matches an open dialog's `TextField`).
- For UI changes, actually run the app and look at it — a green test suite does not confirm the
  screen looks right. Use the `run-on-physical-phone` skill (release build on the USB Huawei, with
  the Gradle memory precautions) or `share-build-tailscale` for the user's Pixel 7a; check screens
  with `adb exec-out screencap`. To check a gesture mid-way, hold it with
  `input motionevent DOWN/MOVE … ` and screenshot before `UP` (each adb call takes ~0.2 s, so
  apps with long-press menus — Spotify — read it as a long press). `uiautomator dump` hangs on screens with running animations
  (e.g. while music plays) — use screenshots there. The Huawei runs Android 10, so background
  restrictions of Android 12+ (foreground-service starts, app freezing) only show on the Pixel;
  it can be reached remotely over Tailscale with wireless debugging (the user pairs; the pairing
  and connect ports are random — `adb mdns services` lists them, else scan 30000–49999 with `nc -z`).
  Pair and connect with the SDK's `~/Android/Sdk/platform-tools/adb`, not the Debian `/usr/bin/adb`
  (34): with that one the connection stays "offline" (TLS `CERTIFICATE_UNKNOWN`), and a pairing
  made with it isn't accepted by the newer one. The Pixel turns wireless debugging off by itself
  after a while (e.g. during a ~9 min build) — the user switches it back on, no new pairing.
  Notification / lock-screen controls are tested from adb: `cmd media_session dispatch
  pause|play|next` (Android 10 lacks it — `input keyevent KEYCODE_MEDIA_PAUSE`), then
  `dumpsys media_session` for the state. The
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
- Never `git checkout <file>` (or `git restore`) to drop `dart format` noise in a file: it also
  throws away the session's uncommitted edits to it (it once wiped `PlaylistLibrary.rearrange`).
  Format only the files you changed instead.

## Topic notes (`docs/agent-notes/`)

- [`theming.md`](docs/agent-notes/theming.md) — themes (Dummify, Lain), `context.palette`, how to add
  one.
- [`local-library.md`](docs/agent-notes/local-library.md) — phone music scan, matching files to
  MusicDatabase (tags first — user's decision), `local.db`, search availability (incl. YouTube
  links), playback order, crossfade (two players), playback limits.
- [`youtube.md`](docs/agent-notes/youtube.md) — YouTube search methods, the lite matcher and its
  benchmark, NewPipe playback (build requirements, 403s), remembered matches, "not found" and
  removed videos, server-wins rule, the audio cache (why it downloads in 1 MB ranges), links
  given to the app and the native "Otwórz w…" sheet (incl. "Zapisz na później"), making a YouTube
  playlist (Google Cloud clients, signing key SHA-1, daily limit), what's not done.
- [`playlists.md`](docs/agent-notes/playlists.md) — Biblioteka playlists: `local.db` tables,
  YouTube import (fetching, title parsing, recognising songs by video first), Spotify import (the
  embed page, 100-track limit, albums, track links), searching playlists (Spotify key / anonymous web-player search
  and its changing hash), previews, sharing, adding songs (phone-made playlists only), phone-only
  folders, R8 rules.
- [`covers.md`](docs/agent-notes/covers.md) — album covers: sources and their order, matching,
  rate limits, the cover cache, the MusicDatabase hand-off, playlist/mood collages and picked
  covers.
- [`signing.md`](docs/agent-notes/signing.md) — the release key (outside the repo,
  `android/key.properties`), why it must never change, its SHA-1 in Google Cloud.
- [`ui-sizing.md`](docs/agent-notes/ui-sizing.md) — font sizes/spacing are calibrated against the
  reference app; why there's no screen-size scaling.

As the app grows other non-obvious subsystems (networking layer, caching, auth), add a short note
per topic there rather than growing this file indefinitely.
