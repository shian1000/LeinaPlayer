# Phone library, search and playback

Covers `lib/src/data/local_library.dart`, `song_catalog.dart`, `combined_search.dart`,
`text_normalizer.dart` and `lib/src/playback/`.

## Matching phone files to MusicDatabase

- Artist/title of a file come from its **tags first, the file name only when tags lack a title or
  an artist** — the same rule as MusicDatabase's mp3 import. Decided with the user even though it
  means a file named "Atrapa - Do usuniecia.mp3" tagged as Johnny Cash matches Johnny Cash.
  Don't flip it to filename-first.
- The file-name fallback ports the first two stages of MusicDatabase's `split_artist_title()`
  (spaced ` - `/` – `/` — `/` _ `, then bare `-`/`_`/`~`). Names with neither (e.g. double
  spaces) get no artist and show as "Nieznany wykonawca"; that's inherited, not a bug here.
- Matching is `SongCatalog.findExact`: normalized title equal **and** normalized artist equal to
  one of the song's artists, the whole "A feat. B" label, or an artist synonym.
- `text_normalizer.dart` mirrors MusicDatabase's `normalize()`. Dart has no Unicode
  decomposition, so the accent table is generated from Python's `unicodedata`; regenerate rather
  than hand-edit it.
- `tag.db` holds only MusicDatabase's technical markers today ("album_checked", "spellchecked"),
  and the mood columns are empty — that's why neither is a search field.

## `local.db`

- Lives in `<app support>/local/local.db`, separate from the downloaded `database/` folder.
  Table `local_songs`: MusicDatabase's `songs` columns (artist as a name, no artists table), plus
  `file_path` (unique), `main_db_id`, `pending`, `added_at`, `checked_at`. The user said more
  columns will come; bump `version` and add `onUpgrade` when they do.
- A scan drops rows whose files vanished and re-checks every pending row, so pending files flip
  to matched after a newer `music.db` arrives. Without a downloaded `music.db` everything is
  pending.
- Tags are read in `Isolate.run` (the parser is synchronous). All rows are kept in memory so
  search doesn't hit SQLite per keystroke.

## Device access

- Reading files by path needs READ_EXTERNAL_STORAGE (≤ Android 12; plus
  `requestLegacyExternalStorage` for Android 10) or READ_MEDIA_AUDIO (13+). The screen requests
  both and accepts either.
- On the Huawei test phone the user picked the SD card's Music folder
  (`/storage/2023-3514/Music`), not internal `/storage/emulated/0/Music`.

## Search results and playback

- Results combine MusicDatabase songs (with the phone files linked to them) and phone-only
  pending files. `SongAvailability`: **available** = has a phone file (pending or not) or a
  stored `youtube_video_id`; **potentiallyAvailable** = no video id stored (YouTube search may
  find it); **unavailable** = not on the phone and `youtube_video_id` is MusicDatabase's
  `NO_VIDEO_SENTINEL` ("N/A" — confirmed by hand as not on YouTube; an empty string counts as
  nothing stored). Older `music.db` files without the column are read as "nothing stored".
- Which source plays a song is `SourceSettings.playbackOrder` (user-ordered; first source that
  `SearchHit.playableFrom` wins). YouTube is searched (`YouTubeSearch`) only on an explicit
  action — the "Wyszukaj na YouTubie" button or tapping a song no source has — never per
  keystroke. YouTube search, matching and playback: [`youtube.md`](youtube.md).
- Snackbars on the search screen use `clearSnackBars()`, not `hideCurrentSnackBar()`: a
  "Szukam…" snackbar shown while another is still visible sits in the queue, so a fast answer
  would otherwise wait behind it for its whole duration.
- `PlayerController` (over `just_audio`) plays one song; `PlaybackQueue`
  (`lib/src/playback/playback_queue.dart`) decides what comes next and plays each song through
  `TrackPlayer` (`track_player.dart`: the source choice, YouTube search and matching — no UI, so
  it also works with the screen off). On `PlayerController.completions` the queue plays the next
  song that can be played; moving on by itself never opens the YouTube app. "Poprzedni" uses
  `PlayerController.currentPosition` (5 s rule). Entries are `SearchHit`s, resolved only when
  played (YouTube stream URLs expire). `just_audio`'s `play()` future completes only when
  playback stops — never await it.
- Never pause between songs. A finished song stays "playing" (just_audio keeps `playing` true in
  the completed state) until the queue has started the next one, or calls
  `PlayerController.stopAtEnd` at the end of the queue. audio_service holds the foreground service
  and a partial wake lock only while the session says it plays; the old pause-on-completion
  dropped both for the seconds the next YouTube song took to resolve, and with the screen off or
  the app in the background the phone froze it there — music stopped after a few songs (5–15
  min) until the app was opened again. Seen on the Pixel 7a (Android 17) in logcat: `Background
  started FGS: Disallowed … ForegroundServiceStartNotAllowedException` at the next song, network
  cut off (`UnknownHostException`), then `freezing <pid> com.shian1000.music_database_app`. The
  Huawei (Android 10) never showed it — test background playback on Android 12+.
- "Przenikanie utworów" (Ustawienia › Odtwarzanie, 0–12 s, `SourceSettings.crossfadeSeconds`,
  0 = off). The media session owns two `AudioPlayer`s; `JustAudioBackend` forwards only the
  active one's position / duration / state, and `MediaSession.active` follows it, so the
  notification and the "playing" state never see the song fading out. `PlayerController` asks
  `onNearEnd` (the queue) once per song when `crossfade` is left (at most half the song);
  the queue runs its usual `_advance`, and the `play` it ends with becomes
  `crossfadeTo(track, timeLeft)`: the next song loads on the other player, starts at volume 0,
  takes over, and the volumes cross (sin/cos) until the old one is stopped. A YouTube song that
  takes long to resolve fades over what's left, or not at all if the old song already ended
  (its completion is swallowed while the queue is already moving on). Only automatic moves
  fade: every user pick (`_play` with `allowExternal`) calls `cancelFade` and switches at once;
  a pause ends a fade (old song stops). Checked on the Huawei: `dumpsys audio` shows two
  started AudioTracks of the app for the fade, then one.
- No connection while moving on by itself (`PlayOutcome.offline`, from `isNetworkError` in
  `network_errors.dart`): the queue tries the same song again after 5, 15 and 30 s
  (`PlaybackQueue.offlineRetries`) instead of skipping it — it used to race through dozens of
  songs in a second, each "unplayable" — and then stops on it (`PlayerController.park`: shown
  paused, "Odtwórz" tries again). Only real refusals (a video YouTube won't serve, N/A) skip.
- Queue model: the context (`_context`, the playlist / results as listed), `_order` (positions in
  play order — identity or shuffled) with `_pos`, plus `_added` ("Dodaj do kolejki") which always
  plays first. `_generation` is bumped by every user action so an auto-advance started earlier
  gives up; caching ahead has its own run counter (a queue edit restarts it in the new order
  without cancelling playback). A queue holds `SearchHit`s as they were when it was filled, so
  `TrackPlayer` re-checks `YouTubeLibrary.matchFor` before playing — otherwise a video found
  while caching ahead would be searched again.
- Restoring after a restart (`QueueSession`): the snapshot (`PlaybackQueue.snapshot`, songs as
  `TrackRef` JSON) is saved on every queue/player change, every 10 s while playing and when the
  app is hidden; restored once `local.db`, the YouTube matches and music.db are loaded. The
  player only shows the song (`PlayerController.showRestored`) — nothing is loaded until play,
  since a YouTube stream would need the network just to start the app; play goes through
  `PlaybackQueue.playCurrent` and then seeks to the saved position.
- Caching ahead (`TrackPlayer.prefetch`) resolves a stream with the switched-on stream methods
  and downloads it with `YouTubeLibrary.download` (1 MB Range chunks, like the cache while
  streaming). The cache limit used everywhere is `SourceSettings.cacheKeep` (≥ N + 2), so songs
  cached ahead can't push out the playing one before they're played. It starts 5 s after the
  queue last changed (`PlaybackQueue.prefetchDelay`, user's choice): songs added one after
  another ("Odtwórz jako następny" puts each at the front) used to start a download each, most
  pushed out of the songs cached ahead by the next one, and the finished ones pushed recently
  played songs out of the cache. A download under way is finished, not broken off (user's
  choice). Tests pass `prefetchDelay: Duration.zero` — then it starts at once, with no `Timer`
  left pending at the end of a widget test.
- The NewPipe method-channel bridge is created once per Flutter engine (`MainActivity`
  companion), not per activity: the engine outlives the activity while music plays in the
  background, and the queue still needs NewPipe for the next song.
- Background playback and the media notification come from `audio_service` directly, not
  `just_audio_background` (which shows previous/next only for its own playlist sources, while
  the queue resolves songs one by one): `MediaSession` (`player_controller.dart`, a
  `BaseAudioHandler` owning the app's one `AudioPlayer`) is created by `AudioService.init` in
  `main()`; it pipes just_audio's events into the notification state and sends previous/next
  presses (`MediaSkip`) through `PlayerController.skips` to the queue. `JustAudioBackend.open`
  sets the notification's `MediaItem` (re-sent with the duration once known, for its seek bar).
  `MainActivity` extends `AudioServiceActivity`; the service/receiver/permissions are in
  `AndroidManifest.xml`. If `AudioService.init` fails, music still plays without a
  notification. While music plays, the
  foreground service keeps Android from killing the app (checked: still playing after 2+ minutes
  locked on the Huawei); when paused the service leaves the foreground, as Android expects.
  `android/app/src/main/res/raw/keep.xml` must stay: release resource shrinking otherwise
  removes audio_service's button icons and the notification shows no play/pause/stop.
