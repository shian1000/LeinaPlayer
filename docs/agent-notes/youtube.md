# YouTube: search, matching, playback

Settings: Ustawienia › YouTube (search) and Ustawienia › Odtwarzanie (playback) (`SourceSettings`). Decisions: the phone may find
missing links itself ([ADR 0003](../decisions/0003-app-supports-musicdatabase.md)); GPLv3 /
private use only ([ADR 0004](../decisions/0004-license-and-distribution.md)).

## What MusicDatabase gives us

`songs.youtube_video_id`: a video id (linked), `N/A` (MusicDatabase's `NO_VIDEO_SENTINEL`:
confirmed not on YouTube — never search), NULL/empty (unknown — the phone may search).

## Search (`youtube_search.dart`)

Methods tried in order, the next only when one fails: NewPipeExtractor (Android only, `search` on
the same method channel as playback, videos filter; `newpipe.dart`), `youtube_explode` (pure
Dart, also iOS),
yt-dlp via server (**not implemented** — MusicDatabase's server has no endpoint; needs an ADR),
Data API (needs a key; ~100 searches/day of quota). YouTube is only searched on an explicit action
(the "Wyszukaj na YouTubie" button, or tapping a song no source has), never per keystroke.

## Matching a song to a video (`youtube_matcher.dart`)

`pickYouTubeVideo()` is a lite version of MusicDatabase's `score_result()`: title gate (whole
words, bracketed part optional but worth +3), artist gate (main artist or synonym in the title or
the channel name), rejects (karaoke, reaction, behind the scenes, <45 s or ≥20 min, ...), and
points for Topic channels / "official audio", minus for live, remixes, videos/lyrics. Keyword
lists are normalized (`normalizeForSearch`, no diacritics); a keyword in the song's own title
never counts against a candidate. Returns `null` rather than a doubtful pick. A full album
(`MatchTarget.fullAlbum`, music.db's `songs.kind`) is the other way round: the query gets
"full album", only videos of ≥20 min with a known duration pass, and "full album" in the title
is a plus (hand-off [`musicdatabase-song-kind.md`](../handoffs/musicdatabase-song-kind.md)).

Benchmark against MusicDatabase's own picks (plain Dart, no phone; candidates come from
youtube_explode, whose results look like NewPipe's — both read YouTube's web search):

```bash
dart run tool/youtube_match_benchmark.dart <music.db> 120            # searches, then scores
dart run tool/youtube_match_benchmark.dart <music.db> 120 --offline  # cached results only
```

Search results are cached in `build/youtube_match_benchmark/candidates.json`, 4 s apart — tune
offline instead of re-querying YouTube. On 113 songs (2026-10-11): 56% the same video as
MusicDatabase, 39% another one (mostly as good or better: official audio instead of a fan
re-upload MusicDatabase picked), 5% none; MusicDatabase's video wasn't in the results at all for
17%. Known wrong picks left: an artist name contained in another's ("Aurora" in "Aurora Olivas").

## Playback on Android (`youtube_audio.dart` → `NewPipeBridge.kt`)

- NewPipeExtractor (JitPack, `com.github.teamnewpipe:NewPipeExtractor`) behind the
  `music_database_app/newpipe` method channel; returns the audio streams, Dart prefers itag 251
  (Opus 160k), then 140 (AAC 128k). `just_audio` streams the URL directly — URLs are tied to the
  phone's IP, so they can't be resolved on a server for the phone.
- `youtube_explode` can still search but its stream downloads get 403 (no PO tokens/challenge
  solving) — don't use it for playback.
- NewPipe currently returns `c=VISIONOS` stream URLs, which work with a plain GET from just_audio.
  If YouTube starts rejecting them, NewPipe's own player sends client-specific User-Agents and a
  POST with `rn`/`range` parameters (`YoutubeHttpDataSource` in the NewPipe app).
- Build needs core library desugaring with `desugar_jdk_libs_nio` (minSdk < 33) and R8 rules in
  `android/app/proguard-rules.pro` (Rhino; `-dontwarn` for desktop-JDK classes) — the release
  build fails without them.
- YouTube regularly answers 403 for one video's stream address for a while (seen often, also
  after many requests for the same video from one IP) while a freshly resolved address works:
  `YouTubePlayback` resolves and tries once more before giving up. Test with varied videos.

## What the phone remembers (`youtube_library.dart`, tables in `local.db` v2, v6, v7)

- `youtube_matches` (`main_db_id` → `video_id`): videos the phone matched itself. Kept after the
  file leaves the cache; `SearchHit.youtubeVideoId` prefers music.db's own link. Since
  2026-10-14 (owner's request) a video found for a song music.db has **no** link for goes to the
  outbox as `found_youtube_links` — when `TrackPlayer._findVideo` finds it, and after each
  music.db load for older or otherwise-made matches (a shared video recognised as a song,
  `video_link.dart`) — see [ADR 0005](../decisions/0005-outbox-for-musicdatabase.md). The phone
  keeps playing its match until music.db settles the song, as before.
- `youtube_track_matches` (v6): the same for tracks that aren't MusicDatabase songs (Spotify
  playlists), keyed by normalised artist + title — see [`playlists.md`](playlists.md).
- `youtube_not_found` (v7): a search that found no sure match (`TrackPlayer._findVideo`; a failed
  search — offline, errors — doesn't count). Gives `YouTubeLink.notFound`: no YouTube icon, the
  queue and caching ahead skip the song without searching, but a **tap** (`allowExternal`)
  searches again. Expires after `YouTubeLibrary.notFoundFor` (30 days — the video may be
  uploaded later); a found video clears it. Keyed `db:<id>` or `track:<artist>\n<title>`.
- `youtube_removed_videos` (v10): videos YouTube no longer has — see
  [`playlists.md`](playlists.md) ("Videos YouTube removed"). `withPhoneYouTube` drops such a
  video from a row — music.db's own link too (`SearchHit.mainVideoRemoved`), so the song is
  matched on the phone like one without a link. Anything reading a row's `playlistVideoId`
  straight from the queued row (`TrackPlayer.youTubeUri` — "Otwórz w YouTube" inside the
  playlist) checks `isVideoRemoved` itself and falls back to the replacement.
- **Videos MusicDatabase found bad** (music.db's `bad_youtube_videos`, since 2026-10-14 —
  [hand-off](../handoffs/musicdatabase-bad-videos.md)): read by `SongCatalog.badVideos` and handed
  to `YouTubeLibrary.useBadVideos` on every music.db load (`main.dart`, `_forgetSettledMatches`).
  "Every song" rows count as removed (`isVideoRemoved`), "one song" rows only for that song
  (`isWrongFor` — skipped in `TrackPlayer._findVideo`, dropped by `withPhoneYouTube`, not saved
  from a shared link); the phone's matches to them are deleted, so those songs are searched
  again. Held **in memory only**, not in `youtube_removed_videos`: MusicDatabase takes a video off
  the list when the owner picks it, and a stored mark would then hide music.db's own link (and
  report it dead). Also never applied to a video that is some song's music.db link. Shown under
  "Linki" in "Informacje o utworze" (per-song rows, `SongDetails.badVideos`).
- **Links the user set by hand** (2026-10-15): "Informacje o utworze" › Linki has a pencil on
  "YouTube (music.db)" and "Teledysk (music.db)" (a link or a bare id; empty = none; "N/A" for
  the song). They're field corrections in the outbox, and the only corrections the phone uses
  at once: `main.dart` `_useUserYouTubeLinks` reads the corrections still against music.db's
  current value (`Outbox.correctionOf`) into `YouTubeLibrary.useUserLinks` (in memory — the
  outbox is the store), and `withPhoneYouTube` puts them into the row's song
  (`CatalogSong.withUserLinks`; `fromMusicDb` gives music.db's own). They beat music.db's link
  and phone matches, aren't subject to `isWrongFor`, and aren't reported as dead music.db links
  (`TrackPlayer._reportIfMainLink` checks `fromMusicDb`) nor as `found_youtube_links`. A
  downloaded music.db with another value drops them. [Hand-off](../handoffs/musicdatabase-youtube-links-by-hand.md).
- **Music video** (`songs.music_video_youtube_id`, `CatalogSong.musicVideoId`): only opened —
  the full player's YouTube button asks "Utwór na YouTube" (from the player's position) /
  "Teledysk na YouTube" (from its start) when a song has both; never played or matched.
- **Server values win, phone values fill gaps** (user agreed): a music.db link or "N/A" always
  beats anything the phone found. So after each new `music.db` is loaded,
  `YouTubeLibrary.forgetSettled` (called from `main.dart`, `_forgetSettledMatches`, once per
  download) deletes `youtube_matches` / `db:` not-found rows of songs music.db now settles — or no
  longer has. A music.db link in `youtube_removed_videos` settles nothing: the phone's replacement
  stays until MusicDatabase puts a different link there (or "N/A"). Name-keyed track entries (Spotify) aren't touched: they have no song id.
  Pamięć podręczna › *Dopasowania z YouTube* forgets all phone matches or all not-founds by hand
  (`forgetPhoneMatches`, `forgetNotFound`), to re-search with a better method. Cached audio
  isn't deleted with them. Expired not-found rows are deleted on load.
- Rows are made once (a queue keeps its songs as they were, a playlist screen builds them on
  load), so `withPhoneYouTube()` (`combined_search.dart`) re-applies all of the above wherever a
  row is shown or played: `playlistHit`, `resolveTrack`, `searchEverywhere`, the Kolejka screen
  and `TrackPlayer`. Showing a stored row without it gives stale icons (the Kolejka bug: videos
  found by caching ahead didn't show there).
- `youtube_cache` + files in `<support dir>/youtube_cache/<id>.webm|m4a`: up to
  `SourceSettings.cacheLimit` (default 25), least recently played deleted first. `.part` files
  left by interrupted downloads are deleted on start. A video downloaded with "Pobierz" stays in
  the same table with `pinned` = 1 (local.db v18): outside the limit, left by "Wyczyść", and
  `YouTubePlayback` plays it from the phone whatever the playback methods are (cache method off
  included). `download(pin: true)` pins also a video already cached or being downloaded by
  caching ahead — a second `download` of a video waits for the first one's future.

Playback (`lib/src/playback/youtube_playback.dart`, `YouTubePlayback`): the switched-on
`YouTubePlaybackMethod`s in the user's order (Ustawienia › Odtwarzanie › Sposoby odtwarzania YouTube;
default cache → NewPipe → youtube_explode → yt-dlp server → YouTube app), first that works wins.
The YouTube app method opens `https://www.youtube.com/watch?v=<id>` — on Android by naming the
YouTube app's package (`openInYouTubeApp` → `MainActivity.kt`, then a browser that isn't this
app), never through url_launcher's "whatever handles the link": the app handles YouTube links
itself now, so that would open Leina Radio again. Elsewhere url_launcher (`openInYouTube`) — for a song played from an imported YouTube
playlist, `watch?v=<that playlist's video>&list=<playlist id>` instead (`TrackPlayer.youTubeUri`;
the playlist's video may differ from music.db's, and only it opens at the song's place in the
playlist). It pauses our player and ends — it can't report whether the video
then plays. A streamed song is cached by `YouTubeLibrary.download()` **next to** playback, with
1 MB `Range` requests. Don't switch to just_audio's `LockCachingAudioSource`: it fetches with one
long request, which YouTube throttles to about playback speed, so the file was only complete at
the end of the song (and never when skipped) — tried on the Huawei, nothing got cached. The cost
of the separate download is fetching each new song twice (~4 MB).

NewPipe also offers a YouTube Music songs filter (`YoutubeSearchQueryHandlerFactory.MUSIC_SONGS`)
with cleaner artist/title results; not used, because the matcher and its benchmark are tuned on
plain video search.

## Links given to the app (`incoming_links.dart`, `video_link.dart`, `MainActivity.kt`, `LinkChooserActivity.kt`, `LinkTargets.kt`, `LaterLinks.kt`)

YouTube and Spotify links alike (Spotify's side: [`playlists.md`](playlists.md)).

- `SEND text/plain` ("Udostępnij") goes straight to `MainActivity` — sharing to the app is the
  choice already. `VIEW` (a tapped link: youtube.com / m. / music. / youtu.be, open.spotify.com,
  spotify.link, spotify.app.link) goes to `LinkChooserActivity` (user's decision): a native,
  translucent activity with a half-screen sheet "Otwórz w…" — Leina Radio (hidden for paths the
  app can't use, e.g. a channel), the service's app (only if installed), the default browser —
  plus "Zapamiętaj wybór". Native so it shows at once over the app the link was tapped in,
  without starting Flutter. Leina Radio forwards the link to `MainActivity` (NEW_TASK |
  CLEAR_TOP | SINGLE_TOP → `onNewIntent` on a running app).
- Remembered choices (ask / leina / app / browser, per service) live in native
  SharedPreferences `link_chooser`, read and set from Dart over the links channel
  (`readLinkChoices` / `saveLinkChoice`; Ustawienia › Otwieranie linków). The sheet takes the
  app's theme: `main.dart` sends both themes' colours + `themeMode` (`setLinkChooserLook`) on
  every theme change; until the app has run once it uses a plain light/dark look.
- "Zapisz na później" (supported links only) swaps the sheet to "Od kogo?" — people picked most
  recently first, "Nowa osoba" types a name in place (`adjustResize` + IME insets keep it above
  the keyboard). Saved natively in SharedPreferences `later_links` (`LaterLinks.kt`) because
  Flutter isn't running; Dart (`later_links.dart`, `LaterLinks` notifier) reads and changes them
  over the links channel (`laterLinks`, `addLaterPerson`, `updateLaterLink`, …) and re-reads on
  every resume. Shown in Ja › Na później (`later_links_screen.dart`),
  which looks up titles for untitled links once per opening (`describeLaterLink`, the same
  recognition as opening the link) and stores them back. A remembered choice skips the sheet, so
  nothing can be saved then. Phone-only, not synced with MusicDatabase.
- Opening outside the app always names the package (`LinkTargets.openInApp` /
  `openInBrowser`) — the system's choice for these links may be this app, which would loop.
  Both app packages are in `<queries>`.
- Not `autoVerify` — only YouTube/Spotify can verify their domains, so on Android 12+ their apps
  keep the links until the user turns off "Otwieraj obsługiwane linki" for them and allows the
  links for Leina Radio (Otwieranie linków explains it and opens the settings screen). Older
  Android (the Huawei) shows the system chooser first, unless an app was set as "always".
- Delivery: `AudioServiceActivity` keeps one cached engine, so a link can arrive (a) on a cold
  start — `LinksBridge` keeps it and Dart asks with `initialLink` after the first frame, when
  `AppShell` listens — or (b) to a new activity / `onNewIntent` on a running engine — pushed with
  `invokeMethod('link')`, which falls back to `initialLink` if Dart isn't listening yet. Intents
  redelivered when the app is reopened from Recents (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) are
  ignored.
- A video is recognised like a playlist track (music.db's video, a phone match, then title →
  `findExact`); a song found by title gets the video saved as a phone match unless MusicDatabase
  says something about its video (incl. N/A). Reading the title costs one request (NewPipe
  `video`, else youtube_explode `videos.get`); a song known by its video needs none.
- Testing with adb: target the activity (`am start -n com.shian1000.music_database_app/.MainActivity
  -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT <link>`; a tapped
  link: `-n …/.LinkChooserActivity -a android.intent.action.VIEW -d <link>`). Don't
  `am start -a android.intent.action.CHOOSER` with a made-up `EXTRA_INTENT`: on the Huawei it
  started an endless loop of invisible chooser activities that blocked the screen until
  `am force-stop com.android.systemui`.

Not done yet: PO tokens (not needed so far), iOS streaming without youtube_explode, yt-dlp via
the server.

## Making a YouTube playlist (`youtube_account.dart`, `youtube_api.dart`, `youtube_export.dart`)

A Biblioteka playlist with no link (made on the phone, or a MusicDatabase folder) gets "Utwórz na
YouTube" ("Dokończ na YouTube" when stopped half-way) in its share sheet (`youtube_export_dialog.dart`). The phone does it itself
with the YouTube Data API — MusicDatabase isn't involved (user's choice; its own
`create_yt_playlist()` uses the owner's token on the server).

- **Sign-in:** `google_sign_in` (Credential Manager) with the Google account picked on the phone
  — separate from the MusicDatabase login; only its e-mail is kept (Ustawienia › Konto shows it,
  with "Wyloguj"). Google Cloud project with YouTube Data API v3, OAuth consent screen in
  "Testing" (testers listed there), scope `auth/youtube`. Two OAuth clients: **Android**
  (package `com.shian1000.music_database_app` + SHA-1 of the signing key) and **Web**, whose id
  is `serverClientId` in the code. The release is signed with `~/.android/debug.keystore`
  (SHA-1 `F4:39:48:90:36:28:0A:1E:EB:FC:6E:8E:15:02:62:5A:A7:E9:2C:3D`): building on another
  machine or with another key breaks sign-in (often reported as "canceled") until its SHA-1 is
  added to the Android client. Android only; iOS would need its own client.
- **Quota:** 10 000 units a day per project, 50 per playlist and per added video — ~200 songs.
  Videos come from what playback would use, else the phone's own search (no API quota).
  Progress is saved after each song (`playlists.youtube_copy_id` / `youtube_copy_done`,
  `local.db` v15, phone only, not synced), so a run stopped by the limit, a lost connection or
  "Przerwij" is finished from the same sheet ("Dokończ…"); a playlist deleted on YouTube
  meanwhile is made again.
- **Unlisted** (user's choice), and a copy: later changes to the Biblioteka playlist don't reach
  it (user: maybe later). Once finished, the share sheet shows its link like an imported one.
