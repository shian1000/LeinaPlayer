# YouTube: search, matching, playback

Settings: Ustawienia › Źródła muzyki › YouTube (`SourceSettings`). Decisions: the phone may find
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
never counts against a candidate. Returns `null` rather than a doubtful pick.

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
- After many requests for the same video from one IP, YouTube can answer 403 for that video only
  for a while (seen with `X2XWBcd5jn0` during testing). Test with varied videos.

## What the phone remembers (`youtube_library.dart`, tables in `local.db` v2)

- `youtube_matches` (`main_db_id` → `video_id`): videos the phone matched itself. Kept after the
  file leaves the cache; `SearchHit.youtubeVideoId` prefers music.db's own link. Never sent back
  to MusicDatabase (ADR 0003).
- `youtube_cache` + files in `<support dir>/youtube_cache/<id>.webm|m4a`: up to
  `SourceSettings.cacheLimit` (default 25), least recently played deleted first. `.part` files
  left by interrupted downloads are deleted on start.

Playback (`lib/src/playback/youtube_playback.dart`, `YouTubePlayback`): the switched-on
`YouTubePlaybackMethod`s in the user's order (Ustawienia › … › YouTube › Sposoby odtwarzania;
default cache → NewPipe → youtube_explode → yt-dlp server → YouTube app), first that works wins.
The YouTube app method opens `https://www.youtube.com/watch?v=<id>` with url_launcher
(non-browser app first, then any), pauses our player and ends — it can't report whether the video
then plays. A streamed song is cached by `YouTubeLibrary.download()` **next to** playback, with
1 MB `Range` requests. Don't switch to just_audio's `LockCachingAudioSource`: it fetches with one
long request, which YouTube throttles to about playback speed, so the file was only complete at
the end of the song (and never when skipped) — tried on the Huawei, nothing got cached. The cost
of the separate download is fetching each new song twice (~4 MB).

NewPipe also offers a YouTube Music songs filter (`YoutubeSearchQueryHandlerFactory.MUSIC_SONGS`)
with cleaner artist/title results; not used, because the matcher and its benchmark are tuned on
plain video search.

Not done yet: PO tokens (not needed so far), iOS streaming without youtube_explode, yt-dlp via
the server.
