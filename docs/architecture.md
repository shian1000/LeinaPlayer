# Architecture

## Current state

A Spotify-style UI where most leaves are still dummies (see [`menu-map.md`](menu-map.md)) around
real search, playback and playlists. `AppShell` (`lib/src/screens/app_shell.dart`)
is the root: a `Scaffold` with the profile drawer, a custom bottom bar, and an `IndexedStack` of one
nested `Navigator` per tab, so pushed screens (playlist, settings) keep the bottom bar visible and
each tab keeps its own back stack. Back is handled centrally in `AppShell` via `PopScope`.
Context menus are modal bottom sheets built by `showMenuSheet()` (`lib/src/widgets/menu_sheet.dart`)
on the root navigator. Unimplemented leaves call `showDummy(context, id)`.

Theming: every colour, corner style and font comes from the active theme (`AppPalette` in
`lib/src/theme.dart`, read via `context.palette`); the chosen light/dark themes and the dark-mode
settings live in a `ThemeController` (`lib/src/theme_controller.dart`) above `MaterialApp`,
persisted in `shared_preferences`. See
[`agent-notes/theming.md`](agent-notes/theming.md).

Phone library: `lib/src/data/local_library.dart` (`LocalLibrary`, via `LocalLibraryScope`) keeps
the folders to scan and the phone's own SQLite `local.db` (`<app support>/local/`, table
`local_songs`: MusicDatabase's `songs` columns with the artist as a name, plus `file_path`,
`main_db_id`, `pending`, `added_at`, `checked_at`). A scan reads tags off the UI thread
(`Isolate.run`, `audio_metadata_reader`), matches files against `SongCatalog.findExact`, and
keeps all rows in memory so `combined_search.dart` can search both databases per keystroke.

Playback: `lib/src/playback/player_controller.dart` (`PlayerController`, via `PlayerScope`) plays
phone files and streams with `just_audio`, behind a small `AudioBackend` interface so tests use a
fake; the backend is created on first play. `MediaSession` (an `audio_service` handler created in
`main()`) adds the media notification with previous/next and the foreground service that keeps
music playing in the background. `PlaybackQueue` (`playback_queue.dart`, via
`PlaybackQueueScope`) holds what plays next (context, shuffle, added songs; shown by
`queue_screen.dart`), plays each song through `TrackPlayer` (`track_player.dart`) and caches the
next few ahead. Which source plays a song is the
user's order
(`SourceSettings.playbackOrder`, `lib/src/data/source_settings.dart`, via `SourceSettingsScope`).

YouTube ([`agent-notes/youtube.md`](agent-notes/youtube.md)): search
(`youtube_search.dart`), the phone's own song→video matching (`youtube_matcher.dart`, a lite
version of MusicDatabase's — [ADR 0003](decisions/0003-app-supports-musicdatabase.md)) and
playback through the user's ordered methods (`lib/src/playback/youtube_playback.dart`: cache →
NewPipeExtractor → … → the YouTube app). NewPipeExtractor is a Java library reached over a method
channel (`android/app/src/main/kotlin/.../NewPipeBridge.kt`, `lib/src/data/newpipe.dart`), so it
exists on Android only. Phone-found matches and the audio cache are tables in `local.db`
(`youtube_library.dart`, `YouTubeLibraryScope`).

Playlists ([`agent-notes/playlists.md`](agent-notes/playlists.md)): `PlaylistLibrary`
(`playlist_library.dart`, `PlaylistLibraryScope`) keeps playlists imported from YouTube or Spotify in
`local.db`; their tracks render with the same `SongTile` (`lib/src/widgets/song_tile.dart`) as
search results. `local.db` schema versions live in `LocalLibrary._open` (v2 YouTube tables, v3
playlists, v4 `play_history`, v5 cover lookups and cache, v6 `youtube_track_matches`, v7 `youtube_not_found`, v8 `spotify_track_id` in `playlist_tracks` and `play_history`, v9 `playlist_tracks.youtube_removed`, v10 `youtube_removed_videos`).

History and resuming: `PlayHistory` (`play_history.dart`, `PlayHistoryScope`) records every song
the queue starts (`PlaybackQueue.played`) in `local.db`, shown by `recents_screen.dart`.
`QueueSession` (`lib/src/playback/queue_session.dart`) saves the queue snapshot and the position
in `shared_preferences` and restores them on start. Both keep songs as `TrackRef`s
(`track_ref.dart`: MusicDatabase id / file / video + title), turned back into rows with
`resolveTrack`.

Links from outside (Android): a tapped YouTube/Spotify link opens the native
`LinkChooserActivity.kt` sheet (Leina Radio / the service's app / a browser, or a remembered
choice); links shared to the app and links the sheet hands on reach `MainActivity.kt`'s
`LinksBridge`, which passes them to `IncomingLinks` (`incoming_links.dart`); `AppShell` imports a
playlist or album, or plays a video or Spotify track (`video_link.dart`). Opening outside the app
always names the package (`LinkTargets.kt`) — the system's choice for these links may be this app
itself.

Album covers ([`agent-notes/covers.md`](agent-notes/covers.md)): `AlbumCovers`
(`album_covers.dart`, `AlbumCoversScope`) finds a song's cover from the user's ordered sources
(phone file, iTunes, Deezer, YouTube thumbnail; MusicDatabase's server is a dummy) and keeps
downloads in a size-limited cache in `local.db` (v5). `SongCover` (`widgets/song_cover.dart`) shows
it wherever a song is drawn, decoded at the shown size and through the user's cover filter
(`widgets/cover_filters.dart`); the gradient `CoverArt` is the placeholder until then. The player
tint and the media notification take the cover too.

Data: `lib/src/data/database_sync.dart` downloads MusicDatabase's `music.db` and `tag.db` from a
user-set address once a day ([`decisions/0002-database-download.md`](decisions/0002-database-download.md)).
`DatabaseSync` is a `ChangeNotifier` created in `main.dart` and exposed via `DatabaseSyncScope`, the
same pattern as `ThemeScope`. `lib/src/data/song_catalog.dart` (`SongCatalog`, exposed via
`SongCatalogScope`) reads `music.db` read-only with `sqflite` the first time search is opened —
the whole `songs` table with artists (incl. `additional_song_artists`, their origin and
synonyms), kept in memory and filtered in Dart on every keystroke over the fields chosen in the
"Szukaj w" sheet (`SearchField`, saved in `shared_preferences`) —
and reloads after each successful download. Matching uses `text_normalizer.dart`, a port of
MusicDatabase's `normalize()`; `tag.db` isn't read yet.

## Intended shape (not yet implemented)

- **`lib/main.dart`** — app entry point and top-level `MaterialApp` setup only.
- **`lib/src/screens/`** — one widget tree per screen.
- **`lib/src/widgets/`** — shared widgets reused across screens.
- **`lib/src/data/`** — getting MusicDatabase's data onto the phone (see ADR 0002) and, later,
  reading it and the models it returns.

## Boundary with MusicDatabase

[`MusicDatabase`](../../MusicDatabase) owns business logic (matching, enrichment, the schema)
and its values always win. The app may fill a gap locally — e.g. find a YouTube link a song
doesn't have yet — with deliberately simplified logic whose results stay on the phone until
MusicDatabase has its own ([ADR 0003](decisions/0003-app-supports-musicdatabase.md)). The app must
keep working when MusicDatabase's server is unreachable. Proper fixes still belong in
MusicDatabase; sending phone-found data back to it for review is planned but not designed yet.
