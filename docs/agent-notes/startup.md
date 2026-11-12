# App start

What a cold start does and why it's ordered so. Measured on the Huawei (Kirin 710, Android 10);
the Pixel is faster but has the same shape.

## Where the time goes

Times from Dart's `main` (the process starts ~0.6–0.7 s earlier: Android, the Flutter engine,
plugins — not looked into yet):

| | |
|---|---|
| first frame, the saved song already in the mini player | ~0.3 s |
| `SongCatalog` ready (music.db + files.db) | ~1.0 s |
| queue restored (heart, the queue's real hits) | ~1.3 s |
| playlists read | ~2.2 s |

Before this work the mini player came at ~4.9 s. Each step below was found by measuring, not
guessed — measure again before moving things.

## Why it's slow at all: one queue, one thread

- **sqflite on Android has one worker thread for every database** (`SqflitePlugin.THREAD_COUNT
  = 1`): music.db, files.db, tag.db and local.db reads all wait in one queue. Every result row
  also crosses the platform channel as a map with its column names and is decoded on Dart's
  main isolate. Many loads started at once in `initState` make each other late.
- **Dart work on the main isolate blocks everything else**, the frames and the delivery of other
  queries' results alike. Building the catalog's 6.6k songs used to take ~1.9 s that way; reading
  every playlist's tracks ~1.2 s.

## What's done about it (keep it)

- **The saved song shows before anything is read** (`QueueSession.showSaved`): the session keeps
  what the player showed (`shown` in `playback.session`: names, Latin forms, version, cover
  request) and `restore` puts the real queue in later. "Odtwórz" tapped meanwhile waits for it.
- **`CatalogSong`'s search texts are lazy** (`_normalizedTitle`, `_normalizedArtists`,
  `_fieldTexts`): `normalizeForSearch` ran ~12 times per song with three regexes each while
  loading. Each is separately lazy — `_byTitle` (name matching) needs only the title.
- **music.db is opened once** for all its tables; one `sqlite_master` query tells which exist.
- **Playlists are read once, after the queue is back** (`_sessionRestored` in `main.dart`): read
  before the catalog they cost as much as again after it (`_catalogChanged`) and held the queue up.
  `PlaylistLibrary.sync` reads them again only when it changed something (`_syncChanged`). The
  start-up syncs (playlists, moods, folders, listens, saved songs, later links) also wait for the
  restore.
- **Home keeps its layout while reading**: stores have `loaded`; a row still being read that was
  shown last time (`HomeLayout.lastShown`) keeps its place (`_HomeSection.reading`); an empty row
  is hidden only once read.
- **Home's first cards and the mini player show last start's covers** (`StartupCovers`, in
  `covers.md`), and Home's cards their remembered texts until music.db is read — a card is
  matched by the song's kept key (`TrackRef.key` of the history / saved entry), never by its
  names: those change as music.db loads (a video's title, then music.db's).

Not done: the history isn't read before music.db — it would delay the queue, and its row keeps
its place anyway.

## Ideas not done yet (discussed with the user)

The user wants these later, in this order, and will say when: read SQLite through FFI (`sqlite3`)
in a background isolate, building the catalog there (no platform channel, other cores) — "point
1"; restore the queue from its own songs (`WHERE id IN`) before the whole catalog; move the
playlists' read, recommendations and stats off the main isolate; a profile build with a Perfetto
trace to see the engine's start before Dart.

## Measuring

- The Huawei shows no app logs. Temporary `debugPrint('STARTUP …ms: …')` marks (a top-level
  `Stopwatch` started in `main`) land in the app's own error log; read it with `uiautomator dump`
  (Informacje i pomoc › Dziennik błędów), newest first, so take a run's lines up to its `main`.
  Never commit the marks.
- Useful probes: a 250 ms `Timer.periodic` printing its lateness (main isolate blocked) and the
  time a `SELECT 1` on local.db takes (sqflite queue busy).
- The Huawei has no `screenrecord`. `adb exec-out screencap` (raw, no `-p`) takes a frame every
  ~0.7 s; PNG ones every ~1.2 s. Convert the raw ones with the 12-byte header (width, height,
  format) skipped.
- A measured start: run the app once and press Home (the session and Home's remembered rows and
  covers are saved then), `am force-stop`, then start.
