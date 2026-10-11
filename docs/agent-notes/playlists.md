# Playlists (Biblioteka)

Code: `lib/src/data/playlist_library.dart` (`PlaylistLibrary`, scope `PlaylistLibraryScope`),
`youtube_playlist.dart` (link parsing, video title → artist/title), `newpipe.dart` /
`youtube_search.dart` (`YouTubePlaylists`: fetching), `screens/playlist_import.dart`,
`screens/playlist_screen.dart`.

## Storage (`local.db` v3, created/migrated by `LocalLibrary`)

- `playlists`: id, name, owner, `source`/`source_id` ('youtube' + playlist id), created/updated.
- `playlist_tracks`: (playlist_id, position) key, artist, title, `main_db_id` (MusicDatabase
  `songs.id` when recognised), `youtube_video_id` (always, for imported tracks), `duration_s`.
- Re-importing the same YouTube playlist replaces its tracks instead of adding a duplicate.

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

## Android build

NewPipe pages through playlists with protobuf-lite, which reads message fields by name — the R8
rules in `android/app/proguard-rules.pro` that keep `…youtube.protos.**` and
`GeneratedMessageLite` fields are required ("Field browseId_ … not found" otherwise).

Not done yet: creating playlists by hand, editing, play queue ("Odtwórz playlistę"), playlists
from other sources.
