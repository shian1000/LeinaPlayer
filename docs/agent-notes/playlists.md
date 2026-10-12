# Playlists (Biblioteka)

Code: `lib/src/data/playlist_library.dart` (`PlaylistLibrary`, scope `PlaylistLibraryScope`),
`youtube_playlist.dart` (link parsing, video title → artist/title), `newpipe.dart` /
`youtube_search.dart` (`YouTubePlaylists`: fetching), `spotify_playlist.dart` (Spotify links,
fetching, title cleanup), `screens/playlist_import.dart`, `screens/playlist_screen.dart`,
`widgets/share_sheet.dart`, `playlist_search.dart` (`FoundPlaylist`, Biblioteka search).

## Storage (`local.db` v3, created/migrated by `LocalLibrary`)

- `playlists`: id, name, owner, `source`/`source_id` ('youtube' or 'spotify' + playlist id),
  created/updated. `PlaylistSummary.link` builds the shared link from these.
- `playlist_tracks` also has `spotify_track_id` (v8; for sharing the song as its Spotify track —
  playlists imported before v8 need re-importing to get it; `play_history` got the same column).
- `playlist_tracks`: (playlist_id, position) key, artist, title, `main_db_id` (MusicDatabase
  `songs.id` when recognised), `youtube_video_id` (always for YouTube imports, never for Spotify
  ones), `duration_s`.
- Re-importing the same playlist replaces its tracks instead of adding a duplicate — except
  YouTube tracks whose video YouTube removed (below).
- `youtube_removed` (v9): such a track's video is gone; `PlaylistTrack.playableVideoId` is then
  null, so `playlistHit` shows it with a dimmed icon and it's searched on YouTube like a Spotify
  track (the found video is remembered by artist + title).

## Import

1. Fetch with the search methods switched on: NewPipeExtractor (Android, all pages, at most
   5000 videos), then youtube_explode. youtube_explode was seen returning **zero videos** for a
   playlist it knew had 19 — an empty result counts as that method failing.
2. Each video → artist/title with `parseYouTubeTrack()`, a lite version of MusicDatabase's
   `build_metadata_from_item()` (Topic channel = artist; "Artist - Title"; junk brackets, pipe
   suffix, hashtags dropped; real versions like Remix/Live kept). ADR 0003.
3. Recognising the MusicDatabase song (`PlaylistLibrary.matchSong`): **by the video first** —
   music.db's `youtube_video_id`, then a video the phone matched earlier (`youtube_matches`) —
   then exact title + artist (`SongCatalog.findExact`). A recognised track stores MusicDatabase's
   own spelling.

When shown, `playlistHit()` also re-checks the video against music.db, so a song MusicDatabase
links later shows as recognised without re-importing. `PlaylistScreen` calls
`SongCatalog.ensureLoaded()` itself: music.db is otherwise only read when search opens, and
without it no track looks recognised.

## Videos YouTube removed (user's decision: keep the track)

YouTube hides removed/private videos from a playlist, so a re-import just doesn't list them.
`PlaylistLibrary.importYouTube(videoExists:)` checks each saved track that's missing now with
`YouTubeSearch.videoExists` (NewPipe / youtube_explode video info): the video still exists → the
owner took it out of the playlist, the track goes; doesn't → the track stays at its old place
(after the fetched track it followed), marked `youtube_removed`; can't tell (no connection) → it
stays unchanged. Tracks already marked aren't checked again; one that comes back is an ordinary
track again. "[Deleted video]" / "[Private video]" entries in a fetch are ignored (treated as
missing). The snackbar adds "YouTube usunął N utw. — zostały na liście…". Without `videoExists`
(tests, old callers) the playlist is simply replaced.

A video that disappears between imports is found out when it's played or cached ahead:
NewPipe answers `ContentNotAvailableException` / `PrivateContentException` /
`AccountTerminatedException` (youtube_explode: `VideoUnavailableException`) — `isVideoGone()` in
`youtube_audio.dart`; age/region/payment limits don't count, the video exists. Then
`YouTubeLibrary.markVideoRemoved` records it in `youtube_removed_videos` (v10), sets
`youtube_removed` on every playlist row with it and drops phone matches to it, and
`TrackPlayer.play` searches another video right away (the dead one is filtered out of search
results); the YouTube app isn't opened for a gone video. MusicDatabase's own link is never
overridden — that play fails with "popraw link w MusicDatabase" (server values win). A re-import
that lists the video again clears it (`clearVideosRemoved`).

## Spotify import

- Read from the public embed page `open.spotify.com/embed/playlist/<id>` — its `__NEXT_DATA__`
  JSON has the name, the owner (`subtitle`) and `trackList` (title, artists joined by ", ",
  duration, `spotify:track:` uri). No account, no Web API app — the same choice as MusicDatabase's
  `spotify_fetcher.py`, which scrapes the public web player. Unofficial: it may break.
- **At most 100 tracks**: the embed lists no more. When it's full, the playlist's own page is
  fetched for `<meta name="music:song_count">` and the snackbar says how many were left out.
  Reading the rest would need Spotify's API with a token; not done yet. The user's own app key
  ("Spotify API", below) is meant for it, but so far it's only used for search.
- `spotify.link/…` short links are followed (redirects; `parseSpotifyLink` takes the first
  playlist/album/track address in the final address + page).
- **Albums** (`open.spotify.com/album/<id>`, from a link only): the embed page `embed/album/<id>`
  has the same `trackList`, with the artist as `subtitle`; imported as a playlist with
  `PlaylistSource.spotifyAlbum` (`source` 'spotifyAlbum'; shown as "Album • artist", link to the
  album page). No song count check — albums stay under 100 tracks.
- **Tracks** (a link shared/opened, user's decision: play at once): `embed/track/<id>` gives
  `name`, `artists[].name`, `duration` (`fetchTrack`); `hitForSpotifyTrack` (`video_link.dart`)
  recognises it like a playlist track, else it plays through a YouTube search.
- Recognising (`PlaylistLibrary.matchSpotifyTrack`): no video, so exact title + artist only —
  the title as is, then without Spotify's version suffix (`cleanSpotifyTitle`: "- 2011
  Remaster", "- Radio Edit", "- From …"; Live/Remix/Acoustic stay), with all artists joined or
  any single one. Unrecognised tracks are stored with the cleaned title and play through a
  YouTube search (`SearchHit.youTubeOnly` with no video → "potentially available"). The video
  found is remembered in `youtube_track_matches` (`local.db` v6, `YouTubeLibrary.saveTrackMatch`)
  under the normalised artist + title — not on the playlist row, so it survives re-importing
  and serves the same track in other playlists, the queue and "Ostatnie" (`playlistHit`,
  `resolveTrack`, `TrackPlayer._withRememberedVideo`). Phone-only songs never take one: they
  play from their file. Once the track is recognised as a MusicDatabase song, the song's own
  link / `youtube_matches` is used instead. Many Spotify tracks aren't on YouTube at all:
  finding nothing is remembered too (`youtube_not_found`, see [`youtube.md`](youtube.md)).
  Downloading audio from Spotify is not supported (user's decision).
- The Spotify fetcher sits in `YouTubeScope` (`spotifyOf`, optional `spotify:` for tests) — the
  scope holding the online sources, rather than one more scope.

## Searching playlists (song search)

Biblioteka playlists are matched while typing (`searchSavedPlaylists`). YouTube and Spotify
playlists only with the online button, all parts at once (`_searchOnline` in
`song_search_screen.dart`); switches in `SourceSettings`: `playlistSearch` (search filters,
master), `youTubePlaylistSearch` (also needs YouTube search on), `spotifyPlaylistSearch`.

- **YouTube** (`YouTubeSearch.searchPlaylists`): the same methods and order as video search
  (`_firstWorking`): NewPipe's `PLAYLISTS` search filter (`searchPlaylists` on the method
  channel), youtube_explode `searchContent(filter: TypeFilters.playlist)` (no channel name; video
  count capped at 50, so 50 is treated as unknown), Data API `type=playlist`.
- **Spotify** (`SpotifyPlaylists.search`) — user's decision: the user's own app key first, the
  anonymous way as the fallback.
  - Key: client-credentials token from `accounts.spotify.com/api/token`, then
    `/v1/search?type=playlist` (its `items` may contain `null`s).
  - Without a key: the public Web API **refuses** the embed page's anonymous token (429
    "QUOTA_EXCEEDED" — it's shared by everyone). The web player's own search accepts it: POST
    `api-partner.spotify.com/pathfinder/v2/query`, operation `searchPlaylists`, a persisted-query
    sha256 hash. The hash changes with web player versions; on 412 "Invalid query hash"
    `findSpotifySearchHash` reads the current one: `open.spotify.com/search` (only a **desktop**
    user agent gets the web player script) → `web-player.<hash>.js` → the chunk number of
    `xpui-routes-search` and its content hash → `xpui-routes-search.<hash>.js` →
    `"searchPlaylists","query","<sha256>"`. `knownSearchHash` is the last one seen. The token is
    read from a Spotify-owned playlist's embed page ("Today's Top Hits"). Unofficial; may break.
  - Web search (DuckDuckGo/Bing `site:open.spotify.com/playlist`) was tried and returns nothing
    to a script.
- Tapping a found playlist opens `PlaylistScreen.preview` (user's decision: preview, not an
  instant import): fetched like an import, tracks recognised with `PlaylistLibrary.previewYouTube`
  / `previewSpotify` (same matching, nothing saved; `id` -1 — the screen passes `_savedId`, null,
  to the queue and history). "Zapisz w Bibliotece" imports the already-fetched data
  (`importYouTube` / `importSpotify`), then the screen shows the saved playlist.

## Sharing

A song's "Udostępnij" (search/Ostatnie ⋮, playlist track ⋮, full player) opens
`showSongShareSheet`: Leina Radio and MP3 are dummies (user's decision, for now); YouTube and
Spotify share the song's link through the phone's share sheet. `SearchHit.spotifyUri` prefers
MusicDatabase's `spotify_url` (`CatalogSong.spotifyTrackId`, only when it's a track page — it may
be an album page) over the Spotify playlist's track. `SearchHit` copies go through
`SearchHit._copy`, so a new field survives `withPhoneYouTube`.

The playlist's share icon and ⋮ › Udostępnij open `showShareSheet` (modelled on the reference
app's sheet: preview card + round buttons): Kopiuj link (clipboard), Otwórz w YouTube / Spotify
(`openInYouTube` / url_launcher), Więcej (`share_plus` → the phone's share sheet). The link is
the source playlist's page; a playlist made on the phone (none yet) has no link and says so.

## Android build

NewPipe pages through playlists with protobuf-lite, which reads message fields by name — the R8
rules in `android/app/proguard-rules.pro` that keep `…youtube.protos.**` and
`GeneratedMessageLite` fields are required ("Field browseId_ … not found" otherwise).

A playlist link (YouTube or Spotify) shared to the app ("Udostępnij") or opened with it goes
through the same import
(`runPlaylistImport` in `playlist_import.dart`) and then opens the playlist in Biblioteka.

Playing: a track tap (or "Odtwórz playlistę" / "Odtwarzanie losowe") fills the `PlaybackQueue`
with the playlist; see [`local-library.md`](local-library.md) for the queue.

Tracks not recognised as MusicDatabase songs are listed by the playlist ⋮ › "Wyświetl utwory,
których nie ma w bazie danych" (`missing_tracks_screen.dart`). Only a list so far: sending them
to MusicDatabase as add requests is the user's intended next step, but how the phone talks back
to MusicDatabase isn't decided — that needs an ADR first (see `AGENTS.md`, Sources of truth).

Not done yet: creating playlists by hand, editing, Spotify playlists over 100 tracks, other
sources, asking MusicDatabase to add the missing tracks.
