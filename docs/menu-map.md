# Menu map

The app's navigation and menus are modelled on the Spotify Android app (layout and naming only — no
Spotify branding, logo or artwork). All leaf elements are **dummies**: tapping one shows a snackbar
`Atrapa: <ID>`. Implementing a feature means replacing that dummy with real behaviour.

## How IDs work

An ID is the path to the element, segments joined with ` › `. It is exactly the text shown in the
snackbar, so it can be grepped in `lib/` (the last segment is usually the visible label; the
prefix lives in a `_id` constant or `idPrefix:` argument in the screen file). Labels that occur
twice on the same screen get a suffix in parentheses, e.g. `(ikona)` vs `(przycisk)`.

Legend: **→** opens another screen/sheet (implemented), everything else is a dummy.

## From outside the app (Android)

The app is called **Leina Radio** on the phone (`lib/src/app_name.dart`; package id unchanged).

- "Udostępnij" → Leina Radio, or a YouTube link opened with the app (`incoming_links.dart`,
  handled in `AppShell._onLink`): a playlist link (`playlist?list=`) is imported like Playlista ›
  Importuj playlistę (or updated, if imported before) and opened in Biblioteka; a video link
  (`watch?v=`, `youtu.be/`, `shorts/`, also with `&list=`) is recognised as a MusicDatabase song
  where possible (`video_link.dart`: music.db's link, a phone match, then the video's title) and
  played from the first source in "Kolejność odtwarzania", in the full player. A Spotify playlist
  link (`open.spotify.com/playlist/…`, `spotify.link/…`) is imported and opened the same way; other
  Spotify links (tracks, albums) and anything else → a message. Only YouTube links can be *opened*
  with the app; Spotify ones arrive through "Udostępnij". On Android 12+ YouTube links reach the app only after the user allows it (see
  Informacje i pomoc).

## Player (`lib/src/screens/now_playing.dart`, `lib/src/playback/player_controller.dart`)

- Media notification (and lock screen): title, artist, progress, previous / pause-play / next —
  the system's media controls (`MediaSession`, an `audio_service` handler); previous/next go to
  the queue like the full player's buttons. Headset and car buttons work too.
- Mini player — appears above the bottom bar once something plays: cover, title, artist,
  play/pause, thin progress line. After the app restarts it shows the last song paused where it
  was (like the reference app); play carries on from there, with the same queue
  (`QueueSession`). Tapping it **→ full player** (slides up, covers the bottom bar):
  - Header: ⌄ (collapse), "Odtwarzanie z wyników wyszukiwania / „<query>” w wyszukiwarce",
    `Odtwarzacz › Menu (⋮)`.
  - Big cover, title, artist, Otwórz w YouTube (**implemented**: YouTube icon left of (+); opens
    the song in the YouTube app — inside its YouTube playlist when it plays from an imported
    one, so YouTube then has the whole playlist; pauses this player; disabled when no video is
    known), `Odtwarzacz › Dodaj (+)`.
  - Seek bar with elapsed/total time (**implemented**).
  - Losowo (**implemented**: toggles shuffle, green while on — see the queue below), Poprzedni (**implemented**: within the first 5 s the previous song
    in the queue, otherwise — or with nothing before it — the song from the start), play/pause
    (**implemented**), Następny (**implemented**: the next song in the queue; disabled at its
    end), `Odtwarzacz › Wyłącznik czasowy`.
  - Play queue (`PlaybackQueue`): tapping a playlist track queues the whole playlist (the
    "context") at that track; a search result queues just that song. Songs added with "Dodaj do
    kolejki" (⋮ of a search result or playlist track) play next, before the rest of the context,
    and stay queued when a new context starts; with nothing playing the added song starts at
    once. Shuffle on: every other context song follows the current one in random order (also
    those listed before it); off: back to the context's order after the current song. When a
    song ends the next one plays, skipping songs that can't be played (without opening the
    YouTube app). After each song starts, the next N songs in play order are cached (see
    Oszczędzanie danych › Pamięć podręczna › Kolejka).
  - `Odtwarzacz › Urządzenia`, Udostępnij (**→ Udostępnij utwór**, see below; IDs
    `Odtwarzacz › Udostępnij › …`), Kolejka **→ Kolejka**
    (`queue_screen.dart`) — **implemented** (rows show videos found since the queue was filled,
    e.g. by caching ahead): "Teraz odtwarzane", "Następne w kolejce" (added
    songs, with "Wyczyść kolejkę"), "Następne z: <playlist / search>" (the rest in play order),
    each row with "Usuń z kolejki" (⊖); tapping a row plays it (added songs before it are
    dropped, context songs before it count as played). "Losowo: wł./wył." at the bottom.

## Bottom navigation (`lib/src/screens/app_shell.dart`)

| Tab | Behaviour |
|---|---|
| Home | → Home screen |
| Wyszukaj | → Search screen |
| Biblioteka | → Library screen |
| Utwórz | → "Utwórz" sheet (not a screen) |

Tapping the current tab again returns it to its root screen. Each tab keeps its own back stack;
system Back closes the drawer/sheet, then pops the tab, then goes to Home, then exits.

## Avatar (top-left on Home/Wyszukaj/Biblioteka) → Menu profilu (`profile_drawer.dart`)

- `Menu profilu › Pokaż profil`
- `Menu profilu › Dodaj konto`
- `Menu profilu › Statystyki słuchania`
- Ostatnie **→ Ostatnie** (`recents_screen.dart`) — **implemented**, modelled on the reference
  app: 🗑 "Wyczyść historię" in the app bar (confirm dialog), `Ostatnie › Filtr: Muzyka` chip
  (dummy), then the history by day ("Dzisiaj", "Wczoraj",
  "5 października", with the year when not this year): the songs played that day, newest first,
  each once per playlist it came from (song rows with the playing animation; ⋮ IDs `Ostatnie ›
  Utwór › Menu (⋮) › <pozycja>`, the same entries as in search). A song played from a playlist
  shows "<artist> • <playlist>" and tapping it opens that playlist scrolled to the song (third
  row); one played on its own (search, "Dodaj do kolejki", a link) — or from a playlist deleted
  since — plays when tapped.
- `Menu profilu › Aktualności`
- Ustawienia **→ Ustawienia**
- `Menu profilu › Aktywność`
- `Menu profilu › Zaproś znajomych`
- `Menu profilu › Wiadomości`
- `Menu profilu › Nowa wiadomość (ikona)` — pencil icon next to "Wiadomości"
- `Menu profilu › Nowa wiadomość (przycisk)` — row at the bottom

## Ustawienia (`settings_screen.dart`)

- `Ustawienia › Wyszukaj ustawienie` (magnifier in the app bar)
- `Ustawienia › Tryb oszczędzania danych (kafelek)`
- `Ustawienia › Sesja prywatna (kafelek)`
- `Ustawienia › Konto`
- Źródła muzyki **→ Źródła muzyki** (`music_sources_screen.dart`), list of music sources:
  - Muzyka lokalna **→ Muzyka lokalna** (`local_music_screen.dart`) — **implemented**:
    - Folders to scan, each with × to remove; "Dodaj folder" asks for read access to music files
      and opens Android's folder picker (`file_picker`).
    - "Ostatnie skanowanie" and "Skanuj teraz": finds audio files in the folders (recursively),
      adds new ones to the phone's `local.db` — artist/title from tags, else from the
      "Artist - Title" file name — and links each to MusicDatabase (`main_db_id`) or marks it
      `pending`; drops files that are gone and re-checks earlier pending ones.
    - "Utwory zapisane na urządzeniu: X" and "Nowe utwory spoza bazy danych: X" — the latter
      **→ list of pending files** (`PendingSongsScreen`).
  - Baza danych **→ Baza danych** (`database_source_screen.dart`) — **implemented**:
    - "Adres serwera (połączenie zdalne)" and "Adres serwera (sieć lokalna)" — two addresses of
      MusicDatabase's `music.db` / `tag.db`, validated and saved with "Zapisz" (saving downloads
      right away).
    - "Wi-Fi sieci lokalnej" — the saved home Wi-Fi name (× clears it) and "Użyj bieżącego
      połączenia", which asks for location permission (Android's requirement for reading the
      SSID), saves the current Wi-Fi, then scans the phone's /24 subnet for a server answering
      `music.db` (SQLite) on the remote address's port and path, and saves the first hit as the
      local address (`DatabaseSync.discoverLocalServer`).
    - "Ostatnie pobranie" (with which address was used), the last error if any, "Pobierz teraz".

    On the saved Wi-Fi the local address is used (falling back to the remote one if it doesn't
    answer), elsewhere the remote one. The download also runs automatically once a day on start —
    see [`decisions/0002-database-download.md`](decisions/0002-database-download.md).
  - YouTube **→ YouTube** (`youtube_source_screen.dart`, state in `SourceSettings`), three
    sections — *Wyszukiwanie*:
    - "Włącz szukanie w serwisie YouTube" — turns on the "Wyszukaj na YouTubie" button and
      looking up songs on YouTube when tapped (see song search below).
    - "Korzystaj z NewPipeExtractor" (on; Android only), "Korzystaj z pakietu youtube_explode"
      (on), "Korzystaj z yt-dlp przez serwer", "Korzystaj z API" — the search methods, tried top
      to bottom, the next one only when the previous fails (`YouTubeSearch`). Only selectable while search is on. **yt-dlp przez
      serwer is not implemented** (MusicDatabase's server has no search endpoint; that needs an
      ADR) — it's skipped with a note in the error message.
    - "Kod YouTube API" — dialog for the Data API key, used by "Korzystaj z API"; the tile shows
      only its last four characters, empty input clears it. Stored in plain
      `shared_preferences`.

    *Odtwarzanie* — "Sposoby odtwarzania" **→ Sposoby odtwarzania** (`youtube_playback_screen.dart`):
    every `YouTubePlaybackMethod` with a switch and a drag handle; the first switched-on one that
    works plays the video (`YouTubePlayback`). Default order and state: "Pamięć podręczna" (on),
    "Korzystaj z NewPipeExtractor" (on; disabled with "Dostępne tylko na Androidzie"
    elsewhere), "Korzystaj z pakietu youtube_explode" (off — YouTube answers 403), "Korzystaj z
    yt-dlp przez serwer" (off, not implemented), "Otwórz w aplikacji YouTube" (on — the last
    resort: opens the video in the YouTube app — inside its YouTube playlist when the song plays
    from an imported one — or the browser without it, and pauses this app's player). The tile shows the active order ("1. Pamięć podręczna, 2. NewPipe, ...").

    The cache of played songs is in Oszczędzanie danych › Pamięć podręczna.
  - Spotify **→ Spotify** (`spotify_source_screen.dart`) — section *Importowanie playlist*:
    `Ustawienia › Źródła muzyki › Spotify › Spotify API` (dummy — the place for a Spotify app key,
    to read whole playlists instead of the embed page's first 100 tracks), and a note on that
    limit. Spotify is not a playback source.
  - Kolejność odtwarzania **→ Kolejność odtwarzania** (`playback_order_screen.dart`) — drag to
    reorder the playback sources (default: 1. Telefon, 2. YouTube). When a song is playable
    from several, the first one in this order is used.
- Wygląd **→ Wygląd** (`appearance_screen.dart`) — **implemented**, everything applies at once
  and is remembered after restart:
  - Motyw jasny **→ list of light themes** (Dummify) — used while dark mode is off.
  - Motyw ciemny **→ list of dark themes** (Dummify, Lain — the default) — used while dark mode
    is on.
  - "Przełącz na tryb ciemny" — switch; off = light theme, on = dark theme. Greyed out (showing
    the system's current mode) while the next switch is on.
  - "Systemowe przełączanie trybu ciemnego" — switch; when on, light/dark follows the phone's
    dark-mode setting.
  - Filtry do albumów **→ Filtry do albumów** (`cover_filter_screen.dart`) — **implemented**: a
    preview on the playing song's cover, then Brak / Lain / Monochromatic (radio); with a filter
    on, "Intensywność" (slider 0–100 % in 5 % steps, default 100 %, kept per filter; the preview
    follows the drag, it's saved on release); with Monochromatic two rows of round swatches:
    "Kolor punktów" (Fosfor — default, Zielony, Bursztyn, Cyjan, Biały, Róż) and "Kolor tła"
    ("A" = automatic, the dot colour dimmed — default; Czarny, Ciemna zieleń, Jasna zieleń
    (Game Boy), Papier), each followed by the user's saved colours (long press forgets one) and
    "+" (colour picker: saved colours, saturation/brightness square, hue bar, hex field —
    `widgets/color_picker.dart`). A picked colour that isn't a preset is saved (newest first, at
    most 8, shared by both rows). Applies to every `SongCover` and the player tint (see
    [`agent-notes/covers.md`](agent-notes/covers.md)).

  Themes are defined in `lib/src/theme.dart` (see [`agent-notes/theming.md`](agent-notes/theming.md)).
- Źródła okładek **→ Źródła okładek** (`cover_sources_screen.dart`) — **implemented**: the cover
  sources with switches, drag to reorder (Serwer — dummy, always off; Plik na telefonie; iTunes;
  Deezer; Miniatura z YouTube); the cover cache is in Oszczędzanie danych › Pamięć podręczna. See
  [`agent-notes/covers.md`](agent-notes/covers.md).
- `Ustawienia › Odtwarzanie`
- Historia odtwarzania **→ Historia odtwarzania** (`history_settings_screen.dart`) —
  **implemented**: "Przechowuj historię" (dialog: 7 / 30 / 90 — default / 180 dni, Rok, Bez
  limitu; older plays are deleted on start and with each new play, `PlayHistory.keepDays`;
  never more than 1000 kept), "Wyczyść historię" (confirm dialog, same as in Ostatnie).
- `Ustawienia › Powiadomienia`
- Oszczędzanie danych i tryb offline **→ Oszczędzanie danych i tryb offline**
  (`data_saver_screen.dart`) — **implemented**: "Zapisuj następne utwory z kolejki tylko przez
  Wi-Fi" (off by default; Wi-Fi = the phone has a Wi-Fi IP address), "Pobieraj okładki tylko
  przez Wi-Fi" (off by default; on cellular only cached covers and covers inside phone files show),
  Pamięć podręczna **→ Pamięć podręczna** (`cache_settings_screen.dart`; subtitle: MB used in
  total) — every cache setting, nowhere else ("Pamięć podręczna" is the one name used in the UI):
  - "Zajęte razem: X MB".
  - *Utwory z YouTube* — "Liczba utworów" (dialog, default 25; lowering it deletes the excess
    at once; disabled with a note while YouTube's "Pamięć podręczna" playback method is off),
    "Zajęte miejsce" ("N utworów, X MB") **→ Utwory z YouTube** (`cache_contents_screen.dart`:
    the cached songs, most recently played first, as song rows with their size — a MusicDatabase
    song where the video is known, else the title the phone saw in a playlist, the history or a
    match; tapping plays from there on through the list, all from the phone; ⊖ "Usuń z pamięci
    podręcznej"), "Wyczyść utwory z YouTube" (confirm dialog).
  - *Kolejka* — "Zapisuj z wyprzedzeniem następne utwory z kolejki" — switch (on by default);
    its subtitle says when YouTube's "Pamięć podręczna" method is off (then nothing is cached).
    "Ile następnych utworów" — dialog, 1–10 next songs (default 3): after each queue song
    starts, the next N in play order (shuffled order when shuffle is on, songs added with
    "Dodaj do kolejki" first) are downloaded to the YouTube cache one by one. Only songs that
    would play from YouTube; a song without a known video is searched and matched first (the
    match is remembered, so playing it later doesn't search again). The cache then keeps at
    least N + 2 songs, whatever "Liczba utworów" says (`SourceSettings.cacheKeep`).
  - *Dopasowania z YouTube* — "Zapomnij filmy dopasowane przez telefon" ("N utworów — zostaną
    wyszukane od nowa"; `youtube_matches` + `youtube_track_matches`) and "Zapomnij „nie
    znaleziono na YouTube”" (`youtube_not_found`), each with a confirm dialog ("Zapomnij") and
    disabled at 0; links and N/A from the database stay. Meant for when a better search method
    arrives. A note says the phone also forgets on its own what each new `music.db` settles,
    and that "nie znaleziono" expires after 30 days.
  - *Okładki* — "Rozmiar" (dialog: 25 / 50 / 100 — default / 200 / 500 MB), "Wyczyść okładki"
    (MB used and image count; confirm dialog).
  - "Wyczyść wszystko" — YouTube songs and covers (confirm dialog; the downloaded database and
    phone music stay).
- `Ustawienia › Jakość zawartości multimedialnej`
- Informacje i pomoc **→ Informacje i pomoc** (`about_screen.dart`) — **implemented**: "Tylko do
  użytku prywatnego" (YouTube terms, never in an app store, may share with friends together with
  the source), licence GPLv3, "Kod źródłowy" (opens the GitHub repo; copy button), "Licencje
  bibliotek" (Flutter's licence page). See [ADR 0004](decisions/0004-license-and-distribution.md).
  Also "Linki z YouTube": what sharing a link to the app does, how to make YouTube links open in
  it, and "Otwieraj linki w Leina Radio" (opens the phone's "Otwieraj domyślnie" settings for the
  app — Android 12+; app info on older ones).
- `Ustawienia › Wyloguj`

## Home (`home_screen.dart`)

- `Home › Filtr: Wszystko` / `Home › Filtr: Muzyka` / `Home › Filtr: Podcasty`
- Card rows; each card is `Home › <sekcja> › karta <n>` (n = 1…6), sections:
  `Popularne radio`, `Weekend z muzyką`, `Nowe wydania dla Ciebie`, `Popularni wykonawcy`,
  `Popularne albumy i single`, `W otoczeniu jesiennych dźwięków`, `Nowe nuty dla Ciebie`,
  `Odkrywaj swoje gatunki`.

## Wyszukaj (`search_screen.dart`)

- Filter icon (top right, where the reference app has a camera; also in the search screen's app
  bar) **→ sheet "Szukaj w"** (`search_fields_sheet.dart`) — **implemented**: checkboxes for the
  fields song search looks at — Tytuł, Wykonawca (incl. additional artists and the artists'
  other names / `synonyms`), Album (these three are the default), Rok, Język, Pochodzenie
  wykonawcy — plus "Przywróć
  domyślne". At least one stays ticked; the choice is remembered. A dot on the icon means the
  selection differs from the default.
- "Czego chcesz posłuchać?" field **→ song search** (`song_search_screen.dart`) —
  **implemented**: searches as you type, over the fields chosen in "Szukaj w", in both the
  downloaded `music.db` and the phone's own `local.db` (`combined_search.dart`): MusicDatabase
  songs plus phone files not in MusicDatabase. Accents and case are ignored, like MusicDatabase's
  search. Shows a hint with a link to "Baza danych" settings when there's nothing to search.
  - Each result has a column of three icons on the right (cover height, half its width), top to
    bottom: database (song is in MusicDatabase), phone (a file on the phone; with a green "*" when
    it isn't in MusicDatabase yet), and YouTube: full when MusicDatabase stores the song's
    `youtube_video_id` or the phone found a video itself, dimmed when neither (phone-only songs
    too), none when it's
    marked "N/A" (no video on YouTube) or the phone searched YouTube in the last 30 days and found
    nothing (`youtube_not_found`; tapping the song searches again, the queue skips it). All use the theme's secondary text colour. Hidden icons
    keep their slot so the column lines up.
  - Results are "Dostępne" (a phone file, pending or not, or a stored YouTube video),
    "Potencjalnie dostępne" (dimmed YouTube icon, not on the phone) or "Niedostępne"
    (`SongAvailability`). Tapping a result uses the first source in "Kolejność odtwarzania"
    that has it: phone → plays the file (**implemented**, `just_audio`, row highlighted with a
    green title + `PlayingBars`, bars that bounce while it plays and stop while paused, like the
    reference app's); YouTube → streams the video's audio (**implemented on Android**
    through NewPipeExtractor, `youtube_audio.dart` + `NewPipeBridge.kt`; Opus 251, else AAC 140;
    on iOS only from the cache or via youtube_explode).
    With no such source and a dimmed icon it searches YouTube for "main artists + title" (if
    YouTube search is on), picks the best candidate with the lite matcher
    (`youtube_matcher.dart`), remembers it on the phone (`youtube_matches`; the icon turns full,
    tooltip "Na YouTube (znalezione przez telefon)") and plays it, telling which video it is
    ("Z YouTube: …"); nothing convincing → "Nie znaleziono na YouTube pewnego dopasowania".
    YouTube videos play with the methods from "Sposoby odtwarzania" (see the YouTube settings
    above): from the cache, streamed (and downloaded to the cache meanwhile) or in the YouTube
    app ("Otwarto w aplikacji YouTube.").
    Otherwise "Ten utwór jest niedostępny".
  - While YouTube search is on, the list starts with a "Wyszukaj na YouTubie" button. YouTube is
    searched only when it's tapped (never while typing); the results (up to 15: title, channel,
    duration) replace the button and are dropped when the query changes. Tapping one streams it
    like a song with a stored link.
  - Every result (YouTube ones too) has a ⋮ **→ sheet**, IDs `Wyszukaj › Utwór › Menu (⋮) ›
    <pozycja>`: Dodaj do kolejki (**implemented**), `Dodaj do playlisty`, `Przejdź do albumu`,
    `Przejdź do wykonawców`, Udostępnij (**→ Udostępnij utwór**, below). The same ⋮ is used in
    Ostatnie (`Ostatnie › Utwór › Menu (⋮)`).
  - **Udostępnij utwór** (`showSongShareSheet` in `share_sheet.dart`; also from the playlist
    track ⋮ and the full player): a card with the song's cover, title and artist over four round
    buttons — `<prefix> › Udostępnij › Leina Radio` (dummy), YouTube (**implemented**: the
    song's video link — music.db's, else one the phone found or the playlist's — to the phone's
    share sheet), Spotify (**implemented**: the track link — MusicDatabase's `spotify_url` when
    it's a track page, else the Spotify playlist's track), `<prefix> › Udostępnij › MP3` (dummy).
    YouTube/Spotify without a link are dimmed; tapping one says why.
- `Wyszukaj › Odkryj coś nowego › <#tag>` (`#polskie indie`, `#mod rock`, `#dance rock`)
- `Wyszukaj › Kategoria: <nazwa>` — grid "Przeglądaj wszystko"; full list in
  `searchCategories` in `lib/src/sample_content.dart`.

## Biblioteka (`library_screen.dart`)

- `Biblioteka › Wyszukaj w Bibliotece`
- Utwórz (+) **→ sheet "Utwórz"** with prefix `Biblioteka › Utwórz (+)` (see below)
- `Biblioteka › Filtr: Playlisty` / `Filtr: Albumy` / `Filtr: Wykonawcy`
- Sort button (shows current order) **→ sheet "Sortuj wg"**:
  - `Biblioteka › Sortuj wg › Ostatnie`
  - `Biblioteka › Sortuj wg › Ostatnio dodane`
  - `Biblioteka › Sortuj wg › Alfabetycznie`
  - `Biblioteka › Sortuj wg › Twórca`
- `Biblioteka › Widok siatki`
- Library items: the user's playlists (`PlaylistLibrary`, newest first; cover, name,
  "Playlista • <owner>") **→ Playlista**. No sample items any more; with no playlists the list
  shows "Brak playlist" and how to add one. Albums/artists don't exist yet.

## Playlista (`playlist_screen.dart`) — **implemented** for imported playlists

- Transparent app bar over the header; once the header scrolls away it turns solid and shows
  the playlist name (as in the reference app). Back arrow pops.
- Szukaj w playliście (search icon next to ⋮, **implemented**): the app bar turns into a search
  field and only the tracks whose title, artist or album contain every word of the query are
  listed (normalised like song search; "Brak wyników dla „…”" otherwise). Tapping one plays on
  through the whole playlist from it. Back (arrow or system) closes the search first — it's a
  local history entry of the route — and returns to the playlist where it was.
- Header: 2×2 mosaic of the first four tracks' covers (one cover with fewer tracks), name, owner
  avatar + name (the YouTube channel / Spotify user; "YouTube"/"Spotify" when unknown), source icon
  (YouTube / Spotify) + "N utworów • X godz. Y min" (sum of the known lengths).
- Menu (⋮) **→ sheet**, IDs `Playlista › Menu (⋮) › <pozycja>`: **Udostępnij** (implemented, the
  same sheet as the icon below), **`Usuń z
  Biblioteki`** (implemented: confirm dialog, deletes the playlist — not the songs), `Dodaj do tej
  playlisty`, `Edytuj playlistę`, **Wyświetl utwory, których nie ma w bazie danych**
  (implemented **→ Utwory spoza bazy danych**, `missing_tracks_screen.dart`: the playlist's
  tracks not recognised as MusicDatabase songs, "Poza bazą danych: N z M", rows like the
  playlist's — tapping plays on through the playlist from there; a note instead when music.db
  isn't downloaded; later the place to ask MusicDatabase to add them), `Dodaj do innej playlisty`, `Przenieś do folderu`, `Pokaż kod
  playlisty`.
- `Playlista › Pobierz (ikona)`, Udostępnij (ikona, **implemented → Udostępnij sheet**,
  `share_sheet.dart`: a card with the playlist's mosaic, name and "Playlista • <owner>" over three
  round buttons — Kopiuj link, Otwórz w YouTube/Spotify, Więcej (the phone's share sheet). The
  link is the playlist's page where it was imported from: `youtube.com/playlist?list=…` or
  `open.spotify.com/playlist/…`), Odtwarzanie losowe
  (**implemented**: queues the playlist shuffled, from a random track), Odtwórz playlistę
  (**implemented**: queues the playlist from its first track, shuffle off),
  `Playlista › Dodaj (do tej playlisty)` / `Edytuj (playlistę)` / `Sortuj (playlistę)`.
- Tracks: the same rows as song search (`SongTile`: cover, title highlighted while playing,
  source icons) but with just the artist under the title, plus a ⋮. Tapping queues the whole
  playlist at that track and plays it like in search (phone file / YouTube in the user's order);
  the full player says "Odtwarzanie z playlisty <name>". A recognised track is its MusicDatabase song (database icon, phone icon if the file is
  on the phone); every YouTube-imported track has its video, so the YouTube icon is full; an
  unrecognised Spotify track has none (empty icon) and is searched on YouTube when played; the
  video found is remembered (full icon from then on). Opening the
  playlist that's playing jumps to the song playing, third row under the app bar (as far as the
  list can scroll; `PlaybackQueue.currentContextIndex`).
- Track ⋮ **→ sheet**, IDs `Playlista › Utwór › Menu (⋮) › <pozycja>`: Udostępnij (**→
  Udostępnij utwór**, see search), `Dodaj do
  Polubionych utworów`, `Dodaj do playlisty`, `Usuń z tej playlisty`, Dodaj do kolejki
  (**implemented**, see the play queue under Player), `Przejdź do albumu`, `Przejdź do wykonawców`, `Przejdź do radia utworu`.

## Utwórz sheet (`create_sheet.dart`)

Opened from the bottom-nav tab (prefix `Utwórz`) or the Library "+" (prefix
`Biblioteka › Utwórz (+)`):

- Playlista **→ sheet** (`playlist_import.dart`):
  - `… › Playlista › Utwórz nową playlistę` (dummy)
  - Importuj playlistę **→ dialog** for a YouTube playlist link (or bare id) or a Spotify one
    (`open.spotify.com/playlist/…`, `spotify:playlist:…`, `spotify.link/…`; anything else is
    refused in the dialog), then "Importuję playlistę…" and a snackbar
    "Zaimportowano/Zaktualizowano „<name>”: N utw., w bazie danych M." The playlist appears in
    Biblioteka. Importing the same playlist again replaces its tracks; YouTube tracks whose
    video YouTube removed stay (dimmed YouTube icon, searched again when played), and the
    snackbar adds "YouTube usunął N utw. — zostały na liście i zostaną wyszukane od nowa." Spotify: at most 100
    tracks; the snackbar then adds "Spotify pokazuje bez logowania tylko pierwsze 100 z N."
- `… › Współtworzone playlisty`
- `… › Blend`

## Deliberately left out

- Spotify-branded entries ("Spotify Singles", "Netflix" category, "Pokaż kod Spotify" — renamed to
  "Pokaż kod playlisty/utworu").
- Removed at the user's request: settings entries "Reklama", "Kontrola rodzicielska",
  "Prywatność i funkcje społecznościowe", "Wyświetlane treści", "Aplikacje i urządzenia", the
  "Darmowe konto" header with its Premium button, the camera icon on Wyszukaj and the whole
  Premium tab. Never built: ads and the reaction (emoji) button on tracks.
- Deeper levels below the first settings screen; apart from "Wygląd", "Źródła muzyki", "Historia
  odtwarzania", "Oszczędzanie danych i tryb offline" and "Informacje i pomoc", each settings
  entry is a single dummy.
