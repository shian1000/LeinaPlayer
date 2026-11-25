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
  ones), `duration_s` (what the source said; often empty for songs added from music.db).
- A playlist's length is worked out when reading (`playlistTrackLength`, MusicDatabase's hand-off
  `video-durations-for-musicdatabaseapp.md`): the track's own `duration_s`, else music.db's
  `youtube_video_durations` for its video (its own, else its song's current link), else the
  song's `files.db` `duration_s`. Never written back to `playlist_tracks` (they sync; a newer
  music.db would disagree). Tracks still without one are `PlaylistSummary.unknownLengths`, and
  the header then says "ponad …". `PlaylistLibrary` reloads when a new music.db is loaded.
- Re-importing the same playlist replaces its tracks instead of adding a duplicate — except
  YouTube tracks whose video YouTube removed (below) and songs the user added by hand ("Made
  on the phone" below). Its name stays as it is on the phone (the
  user may have renamed it, ⋮ › Zmień nazwę); there's no flag telling a renamed one apart, so a
  name changed at the source doesn't come through either.
- `youtube_removed` (v9): such a track's video is gone; `PlaylistTrack.playableVideoId` is then
  null, so `playlistHit` shows it with a dimmed icon and it's searched on YouTube like a Spotify
  track (the found video is remembered by artist + title).

## Made on the phone (the queue saved, "Dodaj do playlisty", folders)

Kolejka's app-bar button (`queue_screen.dart`) saves every song it lists, in its order: the shown
"Poprzednie" (user's choice), the song playing, what comes next — songs the mood filter hides
stay out with `PlaylistLibrary.create`:
`source` NULL (nothing to re-import or link to), synced like any other. A track keeps
`main_db_id` and a video only when it has no MusicDatabase song (or a playlist video), so
music.db's own link stays music.db's. A phone file not in MusicDatabase has no column of its own
— it's kept by title + artist and `playlistHit` finds it again (`LocalLibrary.pendingFile`); on
another phone, or once renamed, it's searched on YouTube like a Spotify track.

"Dodaj do playlisty" is a toggle (`togglePlaylist`, the owner's decision): it adds only what a
playlist lacks, and a playlist already holding all the songs (✓, `PlaylistLibrary.playlistsWith`,
an index built by `load` — by song, video, Spotify track, or names for tracks without a song) loses
them (`removeSongs`). This can happen from inside the open playlist, so `PlaylistScreen` reloads when
its summary changes: its tracks' positions go to `removeTrack`, and stale ones would remove the
wrong song.

"Utwórz nową playlistę" makes an empty one the same way, and "Dodaj do playlisty"
(`playlist_picker.dart`, also the selection bar's) appends with `PlaylistLibrary.addSongs`, kept
like `create` keeps them — to any saved playlist, imported ones too (the owner called the old
"phone-made only" rule a bug). In an imported one the tracks get `playlist_tracks.added` (v20):
`_save`'s re-import (`_withAddedTracks`) puts them back after the source track they followed
(the first ones at the start; one whose track left the source moves up to the one before), and
`importYouTube` doesn't check their videos as vanished ones. Removing an added track doesn't go
into `excluded_tracks` (it would drop the source's own track with that video). The mark syncs as
the track's `added` ([hand-off](../handoffs/musicdatabase-added-tracks.md)); MusicDatabase
drops the key until that's built, so `_applyRemote` keeps the phone's own marks when the answer
lacks it, matched by title + artist + ids. The playlist screen's Dodaj chip is on every saved
playlist; Edytuj only on `source` NULL ones (an imported one's order and tracks come from the
source). Edytuj saves with `PlaylistLibrary.rearrange` (kept positions in the new order, the rest
deleted, renumbered through negative positions like `removeTrack`). Sortuj works on every
playlist but only reorders what the screen lists and queues — `_tracks` is kept sorted, so the
indexes the screen hands to the queue and to "Usuń z tej playlisty" stay right; `_ownOrder` is
what Edytuj starts from.

"Usuń z tej playlisty" (`PlaylistLibrary.removeTrack`) works in every saved playlist, imported
ones too (user's decision): the tracks after it move up (through negative positions — the
`(playlist_id, position)` key). From an imported playlist the track's video id (YouTube) or
Spotify track id is also added to `playlists.excluded_tracks` (v16, a JSON list), and `_save`
leaves those out of every later import; deleting the playlist clears it. The list syncs as
`excluded_source_tracks` with the playlist, whole, the newer side winning
([hand-off](../handoffs/musicdatabase-excluded-tracks.md); MusicDatabase's answer is its
`docs/handoffs/excluded-tracks-for-musicdatabaseapp.md`). Always send a list, never `null` (a
400); an answer without the key (an older server) keeps the phone's own list.

Biblioteka's folders (`LibraryFolders`, `shared_preferences`) sync with the account like
playlists ([ADR 0011](../decisions/0011-folder-sync.md)): on the phone items are keyed by local
ids (`p<playlists.id>`, `Mood.key`), on the wire by the playlist's / mood's `uid` (a global
mood by its tag.db id) — `updateItems` keeps the mapping, refs not on the phone yet wait in
`pending`. Deleting a playlist or mood also takes it out of its folder, since SQLite may hand
the id to a new one. The sort order (Biblioteka's and each folder's own, `library.folderSorts` by folder id), filter chips and "last opened" times stay phone-only, and so do songs
saved "Na później", dynamic playlists and Home's layout — syncing those would need a new
MusicDatabase endpoint and an ADR, not decided.

## Syncing with MusicDatabase ([ADR 0007](../decisions/0007-playlist-sync.md))

`local.db` v11 adds `uid`, `account`, `revision`, `dirty`, `deleted_at` to `playlists`.
`PlaylistLibrary.load()` and the import lookup see only the logged-in account's rows and
phone-only ones (`_scope`) — never assume `playlists` holds only visible rows. Every change
that should reach MusicDatabase sets `dirty` (and `updated_at` when it's the user's change: that
decides conflicts); a deletion of an account playlist sets `deleted_at` instead of deleting.
`PlaylistLibrary.sync` does the exchange; tests use a fake server in
`test/data/playlist_sync_test.dart` that follows MusicDatabase's rules — keep it in step with
MusicDatabase's `docs/handoffs/playlists-for-musicdatabaseapp.md`.

## Import

1. Fetch with the search methods switched on: NewPipeExtractor (Android, all pages, at most
   5000 videos), then youtube_explode. youtube_explode was seen returning **zero videos** for a
   playlist it knew had 19 — an empty result counts as that method failing.
   **Translated titles:** YouTube serves a video's title translated into the language it's asked
   in whenever the uploader (or YouTube) has a translation — NewPipe's default is en-GB, so
   L.U.C.'s "W związku z tym" was stored as "In relation to" ("Preuzeti (2018.05)"). Nothing in
   the playlist page says which title is the original (checked 2026-11-22: same `lockupViewModel`
   either way; `hl` of zxx/und is refused). So `YouTubePlaylists.fetch` reads a NewPipe playlist
   a second time in Polish (`translationCheckLanguage`; `NewPipeBridge.playlist(language)` →
   `forceLocalization`) and for the few videos whose titles differ takes the video's own title
   from oEmbed (`youtube_titles.dart`; oEmbed and the player endpoint's `videoDetails.title` are
   never translated). Either step failing keeps the first reading. youtube_explode (the fallback)
   asks in English only — its titles may still come translated. Blind spot: a video whose
   title YouTube translates into Polish too reads the same both times and stays translated.
   Kept this way because it's cheap (a few page requests + one oEmbed per differing title);
   the owner wants it reconsidered if it starts missing titles or YouTube changes (e.g. starts
   translating into Polish more often, or a playlist response grows an original-title field):
   then switch to asking for every video's own title (oEmbed / player `videoDetails.title`, one
   request per video — ~115 for a playlist like "Preuzeti") instead of only the differing ones.
2. Each video → artist/title with `parseYouTubeTrack()`, a lite version of MusicDatabase's
   `build_metadata_from_item()` (Topic channel = artist; "Artist - Title"; junk brackets, pipe
   suffix, hashtags dropped — but a title that is only hashtags keeps their words: YouTube lists
   Karaś/Rogucki's "#Życzliwość" so, and the empty title left the track unrequestable (`SongRequest.of`
   skips it) until re-imported; real versions like Remix/Live kept). When the part after " - " is
   junk only ("Glow - Lyric Video (English / French)" by Attic Ocean) the left part is the
   title and the channel (no VEVO) the artist — unless the left part is the channel's own name.
   "Renata Przemyk- ''Aniolek''" (the dash glued to the artist) splits too, and a title in quotes
   loses them. An event's "`<event 2018> | <artist> | <song> | <channel>`" (`_splitEventPipes`,
   MusicDatabase's `split_event_pipes()`) is that artist and song, not the event by the channel.
   A dash inside a bracket never splits ("Summer Paradise (Future Funk - Vaporwave - …)"), " -- "
   splits first (a label's "18.White House Records & Fisz -- Na sznurowadle - KODEX": track
   number, the label's own name and the compilation after " - " go), "Artist: Title" when the
   part before the colon is the channel or a known artist. Trailing credits go: "prod. X"
   (`withoutProducerCredits`; MusicDatabase's `strip_producer_credit()` only cuts bracketed ones),
   ", gitara X", and names listed after a junk bracket ("nipplepeople FRKA (Official video), Kire
   Mitrev, Slavica Maras" — songwriters — is "FRKA" by the channel, whose name in front goes as
   `_stripArtist` cuts it; not after a bracket that is part of the title or a version's); a
   guest ("gość Sarsa", " - feat. X - ") joins the artist as "feat.". Brackets are ASCII,
   【】 and the full-width （） / ［］ ("ゆらゆら（Official Music Video）" by YeYe). "┃Cover by
   Raon Lee" names the performer (the channel when it starts that name), "alt-J (∆) Breezeblocks"
   loses the logo bracket, "SILHOUETTE (シルエット)" the original-alphabet one, "(Bob Dylan's 'Man
   Gave Names…')" the original song's name. With `artistNamed` (what's stored and requested:
   `PlaylistLibrary._youTubeTrack`, `video_link.dart`) a title read by a channel music.db doesn't
   know as an artist takes `channelVideoReadings()`' first reading ("General Woo U mom zivotu" by
   a fan's channel), a title that is only a known artist its first hashtag ("Łona
   #hot16challenge" → "hot16challenge", as written), and "The Cure | Talk Talk | Foghorn - muzyka
   na jesień" names the three artists.
   The same parse names unknown videos everywhere (search, links, song requests). ADR 0003.
   A track's stored title changes only by a re-import, so `SongRequest.of` asks for a YouTube
   track's title through `requestTitleOfVideo()` — the junk brackets and the credits after one
   cut as the parse now does — rather than asking MusicDatabase for "ゆらゆら（Official Music
   Video）" stored before full-width brackets were read.
3. Recognising the MusicDatabase song (`PlaylistLibrary.matchSong`): **by the video first** —
   music.db's `youtube_video_id`, then a video the phone matched earlier (`youtube_matches`) —
   then title + artist (`SongCatalog.findByVideoTitle` → `findByName`: exact, without feat. credits in the title or the artist, swapped; a "(Live)" only a live version — `local-library.md`).
   `findByName` tries every reading with the songs' own titles, then again with `title_latin` and
   `other_titles` ("Shunkan Sentimental" is #3802 "瞬間センチメンタル"; `findExact` stays own-title
   only, for files' tags), and each stored title also as `titlesToMatch()` cuts it: junk brackets
   but the edits ("(Radio Edit)" still keeps a title apart), "(Original)", "(Version II)" (a second
   music video — `readVersion` still reads it as an `other` version, tried first), a doubled
   "((Videoclip))", "prod. X", a bare trailing "lyrics" / "official" (matching only —
   MusicDatabase never cuts a bare "lyrics" from a title). An artist's comma-separated
   `artists.synonyms` count one by one: "Tiësto & KSHMR feat. Vassy" is #1439 by "DJ Tiesto"
   (synonyms "Tiesto, DJ TI¨STO") and KSHMR. An artist's name also matches with "&" / "+" read
   as "and" (`normalizeWithAnd`): "Florence and the Machine" is "Florence + the Machine", "The
   Ball And Chain" "The Ball & Chain" (`normalizeForSearch` turns the signs into spaces but keeps
   "and"). `normalizeForSearch` drops combining marks as MusicDatabase's NFKD does and folds kana
   with a voiced mark to the plain one: YouTube sent LUCKY TAPES' "レイディ・ブルース" with
   "デ" / "ブ" as "テ" / "フ" + U+3099, which turned into spaces and missed #277 (playlist
   "Скачать (2018.06)", 2026-11-25).
   When the parse could only take the artist from the channel and names no song,
   `channelVideoReadings()` tries a title starting with a whole artist name music.db knows
   ("renata przemyk bo jesli tak ma byc" by "thericeburner"; `SongCatalog.artistNamed`, longest
   name first, also past a second known artist joined by "i / x / & / feat." — "Łona i Webber
   Wyślij sobie pocztówkę" by a label's channel) and an artist in the trailing bracket ("Wonderful Life (Smith & Burrows)" by
   "Peaky Blinders") — MusicDatabase's `name-matching-for-musicdatabaseapp.md`, the owner's real
   misses. A recognised track stores MusicDatabase's own spelling.

When shown, `playlistHit()` also re-checks the video against music.db, so a song MusicDatabase
links later shows as recognised without re-importing; failing that, exact title + artist
(`playlistSongByName`; never for a track without an artist). `PlaylistLibrary.load` also writes
a song found by name into `main_db_id` and marks the playlist dirty (not `updated_at`, which
would reorder Biblioteka) so MusicDatabase's copy gets it (owner's choice, 2026-10-31) — once
per run per track, so a server dropping the id can't loop syncs. `PlaylistScreen` calls
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
results); the YouTube app isn't opened for a gone video. Caching ahead that finds a gone video
looks for the replacement at once (`prefetch` recurses), so the queue doesn't stall on it.
MusicDatabase's own link is handled the same way (user's decision, 2026-10-12; first seen with
"… - Topic" videos YouTube answers `UNPLAYABLE` "This video is not available" while oEmbed still
says they exist): `SearchHit.mainVideoRemoved` hides the dead link and the phone's replacement
(`youtube_matches`) plays until MusicDatabase changes the link — see [`youtube.md`](youtube.md)
("Server values win"). The dead link (and the replacement, once found) is reported in the
phone's outbox and sent to MusicDatabase's inbox
([ADR 0005](../decisions/0005-outbox-for-musicdatabase.md)). A re-import that lists the video again clears it (`clearVideosRemoved`).

The detection relies on the bridge reporting the exception's **class name**, so
`proguard-rules.pro` keeps the names of `org.schabi.newpipe.extractor.exceptions.**`. Without it
R8 renamed `ContentNotAvailableException` (to `nf`), release builds saw an ordinary failure and
fell through to the YouTube app — tests (which fake the code) stay green, so check
`build/app/outputs/mapping/release/mapping.txt` after touching R8 rules.

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
`showSongShareSheet`: Leina Player and MP3 are dummies (user's decision, for now); YouTube and
Spotify share the song's link through the phone's share sheet. `SearchHit.spotifyUri` prefers
MusicDatabase's `spotify_url` (`CatalogSong.spotifyTrackId`, only when it's a track page — it may
be an album page) over the Spotify playlist's track. `SearchHit` copies go through
`SearchHit._copy`, so a new field survives `withPhoneYouTube`.

The playlist's share icon and ⋮ › Udostępnij open `showShareSheet` (modelled on the reference
app's sheet: preview card + round buttons): Kopiuj link (clipboard), Otwórz w YouTube / Spotify
(`openInYouTube` / url_launcher), Więcej (`share_plus` → the phone's share sheet). The link is
the source playlist's page; a playlist made on the phone (a saved queue) has no link and says so.

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
których nie ma w bazie danych" (`missing_tracks_screen.dart`). Its "Poproś MusicDatabase o
dodanie" asks for all of them at once through the outbox's song requests — the same
`SongRequest.of` / `Outbox.requestSong` path as playing a song music.db doesn't have, so a song
already asked for or rejected isn't asked again — and sends the outbox right away. Rejected
tracks (`rejected_song_requests`) are kept out of the screen's list and count, behind a line
that unfolds them; the list and the button decide it with one helper (`_requestOf`), so they
agree. A request
carries the playlist video's length (`duration_s`, from `PlaylistTrack.duration` through
`SearchHit.duration`), so MusicDatabase sees a 30-minute mix for what it is.

Not done yet: Spotify playlists over 100 tracks, other
sources.
