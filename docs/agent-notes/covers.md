# Album covers

`lib/src/data/album_covers.dart` (`AlbumCovers`, `AlbumCoversScope`) and
`lib/src/widgets/song_cover.dart` (`SongCover`, used wherever a song row/player showed the
placeholder `CoverArt`). Lite logic per ADR 0003: MusicDatabase has no covers yet; the hand-off
asking it for an `albums` table and covers is
[`../handoffs/musicdatabase-albums-and-covers.md`](../handoffs/musicdatabase-albums-and-covers.md).
Once it has them, the "Serwer" source (now a dummy) should read them, keyed on `album_id`.

- **Sources**, the user's order (`SourceSettings.coverOrder`/`coverSources`, Ustawienia › Źródła
  okładek): Serwer (dummy), Plik na telefonie (the file's own picture, `audio_metadata_reader`
  in an isolate — files can hold multi-MB images), iTunes Search API, Deezer search API, YouTube
  thumbnail (`mqdefault` for lists; `maxresdefault`, falling back to `mqdefault`, for the full
  player — `hqdefault`/`sddefault` are 4:3 with black bars). The first source with a cover wins.
- **A cover belongs to the album**: `CoverRequest.lookupKey` is artist + album (normalised), or
  artist + title when there's no album. MusicDatabase's "Singles" album is a placeholder
  (`SINGLES_ALBUM`), not an album; album tags holding a YouTube URL are ignored too.
- **Matching** iTunes/Deezer results: the title must equal the album (or start with it + a word:
  "Karma (Remastered)"; " - Single"/" - EP" dropped) and the artist must equal one of the
  result's artists split on &, feat., x, i… ("Hey" ≠ "Hey Violet"). No match = no cover rather
  than a wrong one.
- **Rate limits**: iTunes allows ~20 searches/min, so it's asked at most every 3 s; Deezer every
  150 ms. Queues run newest first and drop requests whose row scrolled away (`wanted`). A source
  that errors (offline, 403, Deezer's quota error object) is skipped for a minute and nothing is
  remembered.
- **Persistence** (`local.db` v5): `cover_lookups` — a source's answer per lookup key ("none" is
  retried after 30 days); `cover_cache` + `<support dir>/cover_cache/` — downloaded images by URL,
  trimmed to `coverCacheLimitMb` (default 100), least recently shown first; "last shown" is
  saved at most hourly. Real sizes: iTunes 250 px ≈ 30 KB, 600 px ≈ 170 KB.
- **RAM**: images are decoded at the size shown (`ResizeImage` by height, so a 16:9 thumbnail
  cropped to a square stays sharp); embedded pictures are kept in memory up to 20 MB.
- **Wi-Fi only** (Oszczędzanie danych): no lookups/downloads on cellular; cached images and file
  covers still show.
- **Player tint** (`now_playing.dart`, `_CoverTint`): `AlbumCovers.colorOf` — the average of a
  24×24 copy weighted towards saturated, mid-light pixels (so a black frame doesn't grey it),
  lightness clamped against the theme's background; the placeholder's colour without a cover.
- **Notification / lock screen**: `JustAudioBackend` shows the song at once, then adds
  `MediaItem.artUri` from `AlbumCovers.artFile` (a `file://` URI; a phone file's own picture is
  written to `<support dir>/now_playing_art/`, one at a time).
- MusicDatabase now has `albums` / `songs.album_id` / `album_covers` (2026-10-12) but doesn't
  serve covers yet; `songs.album` is kept, so the app reads it unchanged. When it does serve them,
  key the lookup on `album_id` (and use the album artist for compilations).
- **Filters** (Wygląd › Filtry do albumów, `ThemeController.coverFilter`/`monochromeColor`;
  `widgets/cover_filters.dart`): `FilteredImage`, an `ImageProvider` that decodes the cover at the
  shown size, runs the pixel work in an isolate and lands in Flutter's image cache (key = source
  key + filter + size + colour + dot + seed). Lain: brightness → night-blue/teal/cyan gradient
  with a little of the cover's blue/green, seeded grain (stable per cover), scan lines, darker
  rim. Monochromatic: 1-bit ordered dither (Bayer 8×8) after a 2–98 % level stretch and gamma
  1.6, each dot `≈1.25 dp` (a dot×dot block of the cover decoded at full size, averaged) with
  an edge halfway to the background, unlit dots the chosen background (default: the dot colour
  at 10 %) — shown with
  `FilterQuality.none`. Intensity (`ThemeController.strengthOf`, per filter) is one mechanism for
  every filter: each pixel mixes the cover and the filtered look (`strength` in the filter
  functions, a percent in the image key); 0 % skips the filter. The player tint follows the filter (teal / the mono colour, mixed with the cover's by the intensity). The
  notification gets the filtered cover as a 512 px PNG (`artFile(filter:)`), made again when the
  filter or its colour changes (`_coverLook` in `main.dart` → `JustAudioBackend`).
- **No placeholder flashes** (each was a visible bug): `AlbumCovers.known()` gives a new
  `SongCover` the last resolved cover synchronously; 404s (e.g. `maxresdefault` of old videos)
  are remembered in `cover_lookups` as source `missing_image`, else every opening of the player
  waited for YouTube to say 404; `_FullCoverReady` around the mini player precaches the full
  player's cover (found, decoded, filtered) when a song starts; `FilteredImage` has `==` and a
  synchronous key when its source's key is synchronous — without them every rebuild (play/pause
  rebuilds all song rows) reloaded each filtered cover with a frame of placeholder; and
  `SongCover`'s `frameBuilder` never goes back to the placeholder once the song's cover was shown.
  `test/widgets/song_cover_test.dart` guards this.

## Playlist and mood covers

- `CollectionCover` (`widgets/collection_cover.dart`): the cover the user picked, else a collage
  of the first four *different* albums (by `CoverRequest.lookupKey`) among the songs, else the
  `CoverArt` placeholder. Biblioteka rows use `PlaylistCover`, which reads only
  `PlaylistLibrary.leadTracks` (first 12 tracks of every playlist, loaded with the list) instead of
  whole playlists. A Spotify album passes only its first track: its songs often look the album up
  separately (no album in music.db), which made a collage of four identical covers.
- Picked covers (`CustomCovers`, `data/custom_covers.dart`): "Dodaj okładkę" in a playlist's or
  mood's ⋮ (`customCoverEntries`, saving through `PlaylistLibrary.setCover` /
  `MoodLibrary.setCover`), any image via `file_picker`, kept as a 660 px middle-square PNG named
  by its SHA-256 (`<app support>/custom_covers/<sha256>.png|.jpg`) — the same id MusicDatabase
  uses, and a new name per picture, so Flutter's image cache never shows an old one. Which
  playlist or mood has which cover is in `local.db`, synced with the account
  ([ADR 0009](../decisions/0009-cover-sync.md)); a global mood's cover is the user's own. Until a
  cover set on another phone is downloaded, the collage shows. User data, not a cache: not in
  Pamięć podręczna.
