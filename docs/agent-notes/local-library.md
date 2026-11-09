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
- "Pobierz" into a folder the user picked (Oszczędzanie danych › Miejsce na pobrane utwory,
  user's choice: any folder, files named "Artist - Title", earlier downloads moved along) writes
  by path, which takes MANAGE_EXTERNAL_STORAGE ("all files access") on Android 11+ and
  WRITE_EXTERNAL_STORAGE on 10 — asked only when a write probe in the picked folder fails. The
  partial file is written in the app's own folder and then moved (copy + delete across storage),
  so the user's folder never shows a half-done song; `MediaScannerConnection` (`scanMedia` on
  the links channel) tells other music apps. The scan skips that folder (the songs would be
  there twice, the YouTube ones untagged). A download whose folder is gone (SD card out) keeps
  its row and comes back when the folder does — only a missing file in a present folder drops it.
- "Pobieraj jako MP3" (Oszczędzanie danych, on by default — user's decision, 2026-11-03):
  after "Pobierz" finishes, a song that isn't MP3 (YouTube's webm/opus or m4a, a server FLAC —
  lossless lost too, user's choice) is re-encoded as CBR 256 kbps MP3 with an ID3v2.3 tag
  of music.db's values (title, artist, album, year, the main genre) and the album cover as the
  app shows it, unfiltered (`AlbumCovers.coverBytes`), and replaces the original under the same name
  (`TrackPlayer.download` → `ServerDownloads` / `YouTubeLibrary.convertToMp3`,
  `mp3_conversion.dart`). Only "Pobierz": the YouTube cache keeps what it played, and songs
  downloaded before the switch stay as they are (user's choice). Natively `Mp3Encoder.kt`
  (`toMp3` on the downloads channel, one song at a time on a background thread): MediaCodec
  decodes, jump3r (`de.sciss:jump3r`, LAME in Java, LGPL — Android has no MP3 encoder, and
  ffmpeg-kit was retired) encodes; jump3r's `lowlevel.LameEncoder` needs javax.sound, so the
  encoder is wired from its `mp3` package the way that class does it. A failed conversion only
  logs and keeps the original; the recording keys (server file id, video id) don't change, so
  the measured loudness still applies. Speed: on the Huawei (Android 10) a song encodes at about
  twice its playing speed (6.5 min ≈ 3 min with the download) — fine under the download's
  foreground service; native LAME through the NDK would be several times faster if it ever matters.
- On the Huawei test phone the user picked the SD card's Music folder
  (`/storage/2023-3514/Music`), not internal `/storage/emulated/0/Music`.

## Search results and playback

- Results combine MusicDatabase songs (with the phone files linked to them) and phone-only
  pending files. `SongAvailability`: **available** = has a phone file (pending or not) or a
  stored `youtube_video_id`; **potentiallyAvailable** = no video id stored (YouTube search may
  find it); **unavailable** = not on the phone and `youtube_video_id` is MusicDatabase's
  `NO_VIDEO_SENTINEL` ("N/A" — confirmed by hand as not on YouTube; an empty string counts as
  nothing stored). Older `music.db` files without the column are read as "nothing stored".
- Which source plays a song is `SourceSettings.activePlaybackOrder` (user-ordered, only the
  switched-on sources; first source that `SearchHit.playableFrom` wins). `PlaybackSource.server` streams the song's file from
  MusicDatabase's music library (`files.db` → `CatalogSong.serverFile`, `GET /library/<files.id>`;
  [ADR 0010](../decisions/0010-server-files.md)): `TrackPlayer` sends a `HEAD` first so an
  unreachable address is passed over in seconds and "no connection" (queue retries) is told from
  404/503 (queue moves on), and when the server can't play it the next source in the order
  does. A new `PlaybackSource` lands in saved orders right after the value it follows by
  default (`_withAll`), not at the end — otherwise YouTube would keep winning. YouTube is searched (`YouTubeSearch`) only on an explicit
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
  playback stops — never await it. So `PlayerController.playing` turns true only a while after
  `play()` returns (when just_audio reports it): don't check it right after starting a song (test
  fakes report it at once and hide this).
- Phone calls: `MediaSession`'s players run with `handleInterruptions: false` and it pauses and
  resumes them itself (`interrupted_players.dart`), comparing the audio outputs at the call's
  start and end: a speaker or headphones gone in between means no resume. just_audio's own flag
  can't be cleared once the player is paused (`pause()` returns early), and Android's "becoming
  noisy" isn't reliable during a call.
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
- "Wyrównywanie głośności" (Ustawienia › Odtwarzanie, `SourceSettings.leveling` (on by default) /
  `levelingPercent`, 10–100 %): `VolumeLeveling` follows both players'
  `androidAudioSessionIdStream` and puts Android's `DynamicsProcessing` on each session
  (`VolumeLeveling.kt`, Android 9+) as one steady input gain for the whole song (cuts and boosts
  both work, unlike `setVolume`), with a limiter at −1 dB only as a safety net. Done in the
  audio framework, so it costs next to nothing and covers every source and both crossfading
  players. `Loudness.gainDb` = strength × (−14 LUFS − the recording's loudness): a cut in full
  (down to −15 dB), a boost only until the measured peak reaches −1 dBFS (`peakCeilingDb`), none
  when the peak isn't known — so the limiter never squashes anything. A song not measured yet
  plays unchanged (0 dB). No compressor (user's decision, 2026-11-03): the first version
  compressed unmeasured songs and let boosts push peaks 6 dB into the limiter, and both were
  heard as the music ducking in songs with a wide dynamic range; the user wants Spotify
  "Normal"-like leveling — the whole song moved by so many dB, its dynamics untouched. The price:
  a first play with no known loudness isn't leveled, and a quiet, very dynamic recording isn't
  lifted all the way. Loudness is kept per recording, never per song —
  each is mastered differently: `local.db`'s `recordings` table (`recordings.dart`) keyed by
  (`source`, `key`) — a server `files.id`, else a YouTube video id (also when it plays from the
  cache or a download), else a phone file's path (`Recordings.keyOf`). It also keeps the
  recording's length (`duration_ms`: from the measurement, or from the player when a song
  loads — `_rememberDuration` in `main.dart`); rows are filled column by column with
  update-then-insert-ignore, as Android 10's SQLite (3.22) has no UPSERT. `loudness_method`:
  null = not looked at, `none` = tags read, nothing there (still to be measured), `replayGain`,
  `analysis`, `failed` (not retried). Sources, in order:
  - the music scan reads ReplayGain tags (ID3 TXXX, Vorbis comments, APE, Opus
    `R128_TRACK_GAIN`; ReplayGain 2.0's −18 LUFS reference; not M4A — audio_metadata_reader
    skips MP4 freeform atoms), each phone file once;
  - `LoudnessMeasurer` measures everything else the phone has whole — the YouTube cache newest
    first (so the queue's songs cached ahead are measured before they play), downloads, scanned
    files — one at a time, only while leveling and "Mierz głośność na telefonie"
    (`SourceSettings.activeLevelingMeasure`, default on) are on, woken by YouTubeLibrary /
    ServerDownloads / LocalLibrary changes. `LoudnessMeter.kt` decodes with MediaCodec on a
    background-priority thread and computes EBU R128 integrated loudness (BS.1770 K-weighting
    re-derived per sample rate as libebur128 does, 400 ms blocks, −70 LUFS and −10 LU gates),
    the sample peak and the length; checked against ffmpeg's `ebur128` within 0.02 LU at 44.1
    and 48 kHz (60 s of pink noise in ~130 ms on the computer). The meter's inner loop keeps
    the filter state in locals and reads samples in bulk — per-sample calls and array/field
    access were 4× slower interpreted (ART runs it interpreted until JIT kicks in). On the
    Huawei (Android 10) a 3–4 min YouTube song (webm/Opus) takes ~25–33 s while music plays,
    the meter only 1–2.5 s of it: the rest is MediaCodec (an IPC round per small Opus packet),
    not helped by feeding / draining the codec without waits. Fine in practice — songs cached
    ahead are measured long before they play — but a first pass over a big cache takes a while.
  A stream played the first time (not cached ahead) has no value yet and plays unchanged;
  it's measured once it's cached. The gain is set by `JustAudioBackend`'s `onLoading` before a
  song loads on its player, so each of two crossfading songs has its own; a value found while a
  song plays waits for its next play (no jump mid-song). Not in the backup (paths are the
  phone's — `_cacheTables`). Planned: YouTube's own `loudnessDb` for first plays (if NewPipe
  exposes it), later MusicDatabase's values per `files.id` / `video_id` (they'd win, ADR 0003);
  the lengths aren't shown anywhere yet (`playlistTrackLength` could fall back to them).
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
  `PlaybackQueue.playCurrent`, and `PlayerController.play` seeks to the saved position between
  opening the song and starting it (seeking after the start once depended on `playing` and
  silently restarted every restored song from 0:00).
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
  `BaseAudioHandler` owning the app's two `AudioPlayer`s) is created by `AudioService.init` in
  `main()`; it pipes just_audio's events into the notification state and sends previous/next
  presses (`MediaSkip`) through `PlayerController.skips` to the queue. `JustAudioBackend.open`
  sets the notification's `MediaItem` (re-sent with the duration once known, for its seek bar,
  and with the cover once found). audio_service 0.18 hands every `setMediaItem` to Android on a
  new thread of its own, so a burst of items can land out of order — an earlier item without
  the cover landing last left the Pixel's media player black for the whole song.
  `MediaSession.show` therefore re-sends the last item alone 0.8 s after the burst; keep that
  (or serialise the sends) when touching it. Covers are downscaled to 512 px
  (`artDownscaleWidth/Height` in `main.dart`), and `AlbumCovers._writeArt` keeps its last three
  files, since Android reads the file only a moment after getting its path.
  `MainActivity` extends `AudioServiceActivity`; the service/receiver/permissions are in
  `AndroidManifest.xml`. If `AudioService.init` fails, music still plays without a
  notification. While music plays, the
  foreground service keeps Android from killing the app (checked: still playing after 2+ minutes
  locked on the Huawei). It stays in the foreground while paused too
  (`androidStopForegroundOnPause: false`, so the notification can't be swiped away then): a
  service that left it can't come back from the background on Android 12+ (`BFGS denied` in
  `dumpsys activity services`), so music resumed or moved on there played outside it and the
  Pixel froze the app within seconds (`am_freeze … active while frozen`) — and the paused,
  non-foreground service was also stopped as idle (`am_stop_idle_service`). For the same reason
  `MediaSession._state` reports just_audio's `idle` (a song that failed to load) as `loading`:
  audio_service stops its service on idle; only `MediaSession.stop` lets idle through. Failures
  sending the state to Android come out in `AudioService.asyncError`, logged by `main`.
  `android/app/src/main/res/raw/keep.xml` must stay: release resource shrinking otherwise
  removes audio_service's button icons and the notification shows no play/pause/stop.
