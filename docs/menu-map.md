# Menu map

The app's navigation and menus are modelled on the Spotify Android app (layout and naming only — no
Spotify branding, logo or artwork). There are no dummies any more (the `Atrapa: <ID>` snackbar and
`dummy.dart` were removed on 2026-10-16): an element is built or left out, and a button whose
feature is missing only in some setups (no scope in a test, a song with no album) is left out
too.

## How IDs work

An ID is the path to the element, segments joined with ` › `, as this file names it (the last
segment is usually the visible label; the prefix lives in a `_id` constant or `idPrefix:`
argument in the screen file — kept for naming menus, nothing shows it now). Labels that occur
twice on the same screen get a suffix in parentheses, e.g. `(ikona)` vs `(przycisk)`.

Legend: **→** opens another screen/sheet; **implemented** marks what does something itself.

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

## First start (`first_run_screen.dart`)

A fresh install (no catalog downloaded, "Pobieraj z GitHuba" never set) opens over `AppShell` a
full screen "Witaj w Leina Radio" — "Pobierać bazę danych muzyki z GitHuba?", without a way back:
- **Tak, pobieraj z GitHuba** — the switch stays on, the catalog downloads at once.
- **Nie, bez GitHuba** — Ustawienia › Serwer › "Pobieraj z GitHuba" is switched off.

## Player (`lib/src/screens/now_playing.dart`, `lib/src/playback/player_controller.dart`)

- Media notification (and lock screen): title, artist, progress, previous / pause-play / next —
  the system's media controls (`MediaSession`, an `audio_service` handler); previous/next go to
  the queue like the full player's buttons. Headset and car buttons work too.
- Mini player — appears above the bottom bar once something plays: cover, title, artist,
  play/pause, thin progress line. Dragging the song (cover and titles) sideways, like the
  reference app (**implemented**): left — the next song, right — the previous one (always that
  song, not the start of this one, unlike "Poprzedni"); past a quarter of its width it slides
  out and the new one slides in; with nothing that way it only gives a little and springs back.
  After the app restarts it shows the last song paused where it
  was (like the reference app); play carries on from there, with the same queue
  (`QueueSession`). ⊕ before play/pause — Dodaj do playlisty (**implemented**, the same sheet as
  in the song's menu; an accent ✓ when the song is liked). Holding it shows four buttons just above it (`Mini odtwarzacz › Szybkie
  akcje › …`), all **implemented**: Nastrój (**→ Dodaj do nastroju**), Na później / Zapisane
  (toggles "Na później"), Playlista (**→ Dodaj do playlisty**) and Więcej (**→ the song's menu**). Tapping it **→ full player** (slides up, covers the bottom bar):
  - Header: ⌄ (collapse), "Odtwarzanie z wyników wyszukiwania / „<query>” w wyszukiwarce" (the
    menu ⋮ is in the bottom row, by the thumb).
  - Big cover, title, artist, Nastrój (**implemented**: the moon, accent when the song is in a
    mood — tapping it **→ Dodaj do nastroju**; where "Polub" was), Dodaj do playlisty (⊕,
    **implemented**: the song menu's sheet, where the song is also liked — like Spotify's, an
    accent ✓ instead of ⊕ when it is liked).
  - Otwórz w YouTube (**implemented**, first in the bottom row; opens
    the song in the YouTube app from where this player is (`t=` in the link) — inside its
    YouTube playlist when it plays from an imported one, so YouTube then has the whole playlist;
    pauses this player; disabled when no video is known; with a music video as well —
    `music_video_youtube_id` or one the user set — a sheet asks "Utwór na YouTube" /
    "Teledysk na YouTube", the music video from its start).
  - Seek bar with elapsed/total time; tapping the total switches it to the time left (`-m:ss`) and back, remembered across restarts (**implemented**).
  - Losowo (**implemented**: toggles shuffle, green while on — see the queue below), Poprzedni (**implemented**: within the first 5 s the previous song
    in the queue, otherwise — or with nothing before it — the song from the start), play/pause
    (**implemented**), Następny (**implemented**: the next song in the queue; disabled at its
    end), Powtarzaj (**implemented**, `PlaybackQueue.setRepeat`, kept with the saved queue): each tap
    goes off → wszystkie → utwór (green while on). Wszystkie: with nothing left, the queue's main
    songs (or, with none, everything played) go to its end again, in order or shuffled — ahead
    of time, so they crossfade and are cached; switched off, the rounds not started yet are taken
    out. Utwór: the song plays again when it ends (no crossfade), "Następny" still moves on. The
    sleep timer is in the song's menu. "Poprzedni" walks back through the queue (what
    played before), whatever playlist each song was queued from.
  - Play queue (`PlaybackQueue`): one list — what played, the song playing, what comes next.
    Tapping a playlist track (or Odtwórz) replaces the **whole** queue, songs added by hand
    too, with that playlist at that track (its "main" songs); a search result with just that
    song. Each queue entry remembers where it was queued from (`QueueOrigin`: a playlist, with
    its YouTube list, or a search) — so the full player's "Odtwarzanie z…", the history and
    "Otwórz w YouTube" follow the song playing. A whole playlist added from its ⋮ keeps its
    origin; a single song added from its ⋮ has none, even if it's on a playlist (user's
    decision). "Odtwórz jako następny" puts songs right after the current one; "Dodaj do
    kolejki" after the songs added (or moved) before, ahead of the rest of the main songs; with
    nothing playing the first one starts at once. Shuffle on: the main songs not played yet
    (also those listed before the tapped one) take the main songs' places in random order;
    off: back to the playlist order after the main song played last; songs added or moved by
    hand stay where they are. When a song ends the next one plays, skipping songs that can't
    be played (without opening the YouTube app). After each song starts, the next N songs are
    cached (see Oszczędzanie danych › Pamięć podręczna › Kolejka). A queue saved by an older
    version is converted on start. With the mood filter on (**→ Filtr nastrojów**), songs it
    doesn't allow stay in the queue but are hidden and passed over — by the end of a song,
    Następny, Poprzedni and the notification; a song the user taps still plays, and switching
    the filter off shows them again where they were.
  - Informacje o utworze (`SongInfoCard` in `widgets/song_info.dart`, data from
    `data/song_details.dart`) — **implemented**: the card below the lyrics,
    scrolled to like the reference app's cards. For now **everything** known (user's request; to
    be trimmed later): the whole music.db `songs` row (also columns added later, by their raw
    name), former ids (`song_id_changes`), each artist's row with its role, the album's row with
    MusicBrainz / iTunes / Deezer / Spotify links and its `album_covers`, the YouTube / Spotify
    links (music.db's and the phone's or the playlist's when different), moods (global and own,
    from `MoodLibrary`) and the other tag.db tags, the files on the phone and what it plays
    from. Tapping a link opens it (the song's YouTube videos from where the player is, pausing it,
    like Otwórz w YouTube; Spotify can't be told where to start — its app opens a track link as
    the album's page on a free account), a long press copies a value. Songs not in MusicDatabase show
    only what the phone knows. A pencil next to the song's, its artists' and its album's own
    fields (empty ones shown as "—") corrects the value: the correction goes to the outbox for
    MusicDatabase ([ADR 0005](decisions/0005-outbox-for-musicdatabase.md), field corrections)
    and shows under music.db's value until a downloaded music.db changes it. The song's own
    artist's name asks first: "Ten utwór ma innego wykonawcę" (a `songs.artist_id` correction
    with the typed name — only this song changes, hand-off
    [`musicdatabase-song-artist.md`](handoffs/musicdatabase-song-artist.md)) or "Popraw pisownię
    nazwy" (`artists.name`, all the artist's songs); without what the first needs (no song or
    artist id) the name has no pencil — never a rename as its only choice. A new name that
    doesn't resemble the old one (`nameResembles`, lite `title_resembles()`) asks "To nie
    wygląda na poprawkę pisowni…": for the song's own artist "Tak, tylko ten utwór" (sent as
    the `songs.artist_id` correction instead) or "Nie, zmień nazwę we wszystkich utworach"; for
    co-artists and guests a warning with "Anuluj" (MusicDatabase's hand-off
    `artist-rename-guard-for-musicdatabaseapp.md`). Under Linki the
    song's YouTube video and music video ("Teledysk") have a pencil too (link or id); unlike
    the other fields the phone uses the new link at once (see `youtube.md`). Once music.db has
    `songs.kind`, "To jest cały album" is a switch instead of a pencil: a `kind` correction of
    `full_album` or empty (hand-off [`musicdatabase-song-kind.md`](handoffs/musicdatabase-song-kind.md)).
  - Bottom row, five icons spread evenly (user's order): Otwórz w YouTube (above), Filtr
    nastrojów (**implemented**: filter icon, accent while on, **→ Filtr nastrojów**), Udostępnij
    (**→ Udostępnij utwór**, see below; IDs `Odtwarzacz › Udostępnij › …`), Kolejka
    (**implemented**: shows in place of the cover, accent while shown, tapped again — or × —
    brings the cover back; "Następne" — the songs coming up, tapping one plays it — and "Cała
    kolejka" **→ Kolejka**), `Odtwarzacz › Menu (⋮)` (**→ the song's menu**).
  - Scrolled down: **Tekst** (**implemented**, a card right under the player, scrolling inside
    itself): the lyrics from LRCLIB (`data/lyrics.dart`, kept in memory for the run; a lite
    gap-fill while MusicDatabase has none) — time-synced lines follow the song, the current one
    bold and kept in view inside the card, tapping a line jumps there; else the plain text;
    "Szukam tekstu…", "Nie znalazłem tekstu tego utworu.", "Utwór instrumentalny." or no
    connection with "Spróbuj ponownie"; "Teksty: LRCLIB" under it. Not shown at all (and LRCLIB
    never asked) with Oszczędzanie danych › "Pobieraj teksty piosenek" off. Then Informacje o utworze.
  - Kolejka
    (`queue_screen.dart`) — **implemented** (rows show videos found since the queue was filled,
    e.g. by caching ahead): opens at "Teraz odtwarzane"; scrolled up, "Poprzednie" — the last
    5 songs before it in the queue (what "Poprzedni" goes back through, so with a playlist
    started mid-way also the songs listed before the tapped one; more than the reference app,
    which shows none — user's choice; only the view is limited — trimming the queue's history
    would cut "Poprzedni" short and lose songs when shuffle is turned off), dimmed, oldest first; tapping one plays it and puts the
    songs after it, the current one too, back at the front of the queue. Then everything after it with a heading over
    each run of songs queued from the same place: "Następne w kolejce" (single songs added by
    hand), "Z playlisty: <name>" (a playlist added as a whole), "Następne z: <playlist /
    „query” w wyszukiwarce>" (the main songs). "Wyczyść kolejkę" on the first heading of added
    songs drops everything added by hand. A heading of songs from a playlist (**implemented**) has
    "Losowo w tej grupie" (its songs in random order where they are; shuffle leaves them after
    that), "Powtórz tę grupę" (copies of its songs right after it) and "Usuń tę grupę z kolejki";
    dragged left the heading takes the whole group out too ("Usunięto z kolejki: N utw." with
    Cofnij). Each row has a drag handle (≡) to move it anywhere —
    it keeps its origin, and shuffle no longer moves it. Dragging a row left takes it out
    ("Usunięto z kolejki" with Cofnij — the reference app does the same), right makes it play
    next ("Usunięto z kolejki" is the screen's own SnackBar — it goes after 4 s, even with
    Cofnij, and with the screen). Tapping a row plays it (added songs before it are dropped, main songs before it
    count as played). "Losowo: wł./wył." and "Nastroje: wł./wył." (**→ Filtr nastrojów**) at the
    bottom; songs the filter hides aren't listed. The moon in the app bar **→ Nastrój dla
    wszystkich utworów** for every song listed (the shown "Poprzednie" too — user's choice).
    "Zapisz kolejkę jako playlistę" (**implemented**, `Icons.playlist_add` in the app bar): asks
    for a name and saves every song listed, in the screen's order, as a new Biblioteka
    playlist (synced with the account like any other); the note "Zapisano w Bibliotece: …" has
    "Pokaż", which opens it.

## Bottom navigation (`lib/src/screens/app_shell.dart`)

After Juxtopposed's Spotify redesign ([`ideas/`](ideas/spotify-redesign-juxtopposed.md)): no
avatar in the tab headers and no profile drawer — the profile is the "Ja" tab; "Utwórz" is
Biblioteka's "+".

| Tab | Behaviour |
|---|---|
| Home | → Home screen |
| Odkrywaj | → Odkrywaj (`discover_screen.dart`) |
| Wyszukaj | → Search screen |
| Biblioteka | → Library screen |
| Ja | → Ja (`profile_screen.dart`) |

Tapping the current tab again returns it to its root screen. Each tab keeps its own back stack;
system Back closes a sheet, then pops the tab, then goes to Home, then exits.

## Odkrywaj (`discover_screen.dart`) — **implemented**

- Category tabs at the top: "Wszystko" (30 random MusicDatabase songs, no full albums) and every mood (global,
  then own; 30 of its songs shuffled), and 🎲 "Wylosuj inne". Drawn again after a new music.db.
- One card per song, swiped up for the next (vertical `PageView`): cover with ▶ (plays the
  category's songs from this one as a fragment — about a third in; nothing plays by itself),
  title, artist • album, tags (year, language, moods), "Fragment" and "Od początku". Beside it:
  Artysta (**→ the artist's songs**, see the song menu), Na później (**implemented**: bookmark,
  accent when saved — `SavedSongs`), Playlista (**→ Dodaj do playlisty**), Udostępnij (**→
  Udostępnij utwór**), Więcej (**→ the song's menu**).

## Ja (`profile_screen.dart`)

- Profile card: avatar, the logged-in MusicDatabase user ("N playlist • M własnych nastrojów") or
  "Nie zalogowano" — tapping **→ Konto** (`account_screen.dart`); ✏ Edytuj profil (**→ Konto**)
  and Udostępnij profil (**implemented**: the latest year's summary opened on its last card, the
  one shared as a picture — `ListeningSummaryScreen(atShareCard:)`; a note when nothing has
  been played yet).
- Konto MusicDatabase card (synced or phone only) **→ Konto**.
- Statystyki słuchania **→ Statystyki słuchania** (`listening_stats_screen.dart`) —
  **implemented** (ADR 0012): "Ten tydzień" on top — the week's highlights as cards (milestones,
  Nowe odkrycie, Powrót, Utwór tygodnia, Na zapętleniu; a song's card plays it, an artist's opens
  their songs); "Podsumowania" — a tile per year and season with plays, opening their summary
  (`listening_summary_screen.dart`: Wrapped-like cards, the last one shared as a picture); chips 4 tygodnie / 6 miesięcy / Rok / Od początku (rolling, ending
  now); a card with the minutes listened, plays (from 30 s), songs and artists, and since when
  it counts when that's inside the period; Utwory (top 5, "Pokaż więcej" up to 50, "Odtwórz"
  queues them), Wykonawcy and Albumy (top 10, sideways, opening the artist's / album's songs),
  Pory dnia (listened time per hour), Dekady, Języki, Kraje wykonawców, Skąd grało (shares).
  Ustawienia **→ Ustawienia**.
- Ostatnie **→ Ostatnie** (`recents_screen.dart`) — **implemented**, modelled on the reference
  app: 🗑 "Wyczyść historię" in the app bar (confirm dialog), then the history by day ("Dzisiaj", "Wczoraj",
  "5 października", with the year when not this year): the songs played that day, newest first,
  each once per playlist it came from (song rows with the playing animation; ⋮ IDs `Ostatnie ›
  Utwór › Menu (⋮) › <pozycja>`, the same entries as in search). A song played from a playlist
  shows "<artist> • <playlist>" and tapping it opens that playlist scrolled to the song (third
  row); one played on its own (search, "Dodaj do kolejki", a link) — or from a playlist deleted
  since — plays when tapped.
- Na później (with how many are still to listen to) **→ Na później**
  (`later_links_screen.dart`) — **implemented**: links saved from the "Otwórz w…" sheet's
  "Zapisz na później" with who sent them. Chips "Wszyscy" + each person (count; long press:
  Zmień nazwę / Usuń osobę — with their links, asks first), rows newest first (service icon,
  title and artist looked up by the app, else the kind; "od: <osoba>", date; a dot until
  opened). Tap opens it like a link given to the app (plays / imports) and marks it listened;
  ⋮ / long press: Otwórz w Leina Radio, Oznacz jako (nie)odsłuchany, Zmień, od kogo jest (incl.
  Nowa osoba), Otwórz w aplikacji YouTube/Spotify, Kopiuj link, Usuń z „Na później”.
  The links sync with the account (the sender by name; [ADR 0013](decisions/0013-saved-songs-sync.md)).

## Ustawienia (`settings_screen.dart`)

One list under section headers (user's choice): MusicDatabase, Słuchanie, Wyszukiwanie i
import, Wyświetlanie, Dane, Aplikacja.

- Wyszukaj ustawienie (magnifier in the app bar) — **implemented**: a search screen over every
  entry's name, the parts of its subtitle and its `keywords` (the settings on its screen), and
  the screens under it (`deeper`: Pamięć podręczna), ignoring case and Polish letters; a result
  shows the setting and its path and opens its screen. A new setting gets its name added to
  `keywords` in `settings_screen.dart`.

### MusicDatabase

- Konto **→ Konto** (`account_screen.dart`) — **implemented**: logging in with a MusicDatabase
  user ("Nazwa użytkownika", "Hasło", "Zaloguj"; checked by the server, which hands back a
  token), or the logged-in user and "Wyloguj" (asks first)
  ([ADR 0006](decisions/0006-musicdatabase-login.md)). Logged in, one row **"Synchronizuj"**
  covers everything that syncs with the account — playlists, moods (and global-mood changes),
  folders, listening stats, liked and saved songs, links saved for later — showing "Wszystko
  zsynchronizowane (najpóźniej o HH:MM)", "Synchronizowanie…" or which part failed and why, with
  ⟳ "Synchronizuj teraz" syncing all of it; a long press explains what syncs where. Right after
  logging in, phone-only playlists, moods and folders are offered to the account ("Dodać
  playlisty z telefonu do konta?" — Nie teraz / Dodaj), and while any are left rows "Playlisty /
  Nastroje / Foldery tylko na tym telefonie: N" add them when tapped ([ADR 0007](decisions/0007-playlist-sync.md),
  [0008](decisions/0008-moods.md), [0011](decisions/0011-folder-sync.md)); liked and saved songs
  and later links join the account by themselves ([ADR 0013](decisions/0013-saved-songs-sync.md)).
  Below everything, once signed in for "Utwórz na YouTube": "Konto Google (playlisty na
  YouTube)" — the Google account's e-mail with **Wyloguj** (the next playlist asks for an
  account again).
- Serwer **→ Serwer** (`database_source_screen.dart`) — **implemented**:
  - "Adres serwera (połączenie zdalne)" and "Adres serwera (sieć lokalna)" — two addresses of
    MusicDatabase's `music.db` / `tag.db` / `files.db` (the server's music files, ADR 0010),
    validated and saved with "Zapisz adresy i pobierz bazę" (saving downloads
    right away).
  - "Wi-Fi sieci lokalnej" — the saved home Wi-Fi name (× clears it) and "Użyj bieżącego
    połączenia", which asks for location permission (Android's requirement for reading the
    SSID), saves the current Wi-Fi, then scans the phone's /24 subnet for a server answering
    `music.db` (SQLite) on the remote address's port and path, and saves the first hit as the
    local address (`DatabaseSync.discoverLocalServer`).
  - "GitHub (publiczna kopia bazy)" — "Pobieraj z GitHuba" (switch, on by default) and the
    repository `<owner>/<repo>` (default `shian1000/LeinaMusicDatabase`; a pasted repository
    link is accepted, empty brings the default back; saved with "Zapisz adresy i pobierz bazę"). Only `music.db` /
    `tag.db`, never `files.db`.
  - "Ostatnie pobranie" (with which source was used: sieć lokalna / połączenie zdalne / GitHub),
    the last error if any, "Serwer udostępnia pustą bazę" when the server's music.db has no songs
    and the phone kept its own (or GitHub's) — with "Użyj pustej" (after a confirmation) to take
    it anyway, "Pobierz teraz".

  On the saved Wi-Fi the local address is used (falling back to the remote one if it doesn't
  answer), elsewhere the remote one; when no server is set or none answers, GitHub (reads
  `version.json`, downloads only changed files, checks size + SHA-256 before swapping). The
  download also runs automatically once a day on start — see
  [`decisions/0002-database-download.md`](decisions/0002-database-download.md) and
  [`decisions/0014-github-database-and-request-packages.md`](decisions/0014-github-database-and-request-packages.md).
  Leaving the screen also saves the typed addresses when all are valid ("Zapisano adresy
  serwera"), else keeps the old ones ("Nie zapisano adresu serwera: jest nieprawidłowy").
- Zgłoszenia poprawek **→ Zgłoszenia poprawek** (`outbox_settings_screen.dart`) — **implemented**:
  "Wysyłaj zgłoszenia poprawek automatycznie" (switch, on by default), "Czeka na wysłanie"
  (requests in the outbox; tapped, the reported songs with the phone's replacement —
  `outbox_contents_screen.dart`; a waiting artist rename that doesn't look like a spelling fix
  says so, with "Tak, tylko ten utwór" turning it into the `songs.artist_id` correction of the
  song it was made from, when that artist is the song's own; then the songs played that
  music.db doesn't have, asked to be added — `song_requests.dart`), "Ostatnie wysyłanie" (sent / refused / why not, "kolejna próba
  jutro" after the server refused), "Wyślij teraz" (needs a server), "Wyślij paczkę…" (the
  waiting requests as a `.zip` through the share sheet; asks once for "Podpis paczek" when not
  logged in; afterwards they count as sent — closing the sheet without sharing takes it back),
  "Wyeksportuj ponownie ostatnią paczkę" (only after one; rebuilt from `outbox/sent/`), "Podpis
  paczek" (the account's name when logged in, else the typed one, cleaned to MusicDatabase's
  username pattern; empty — unsigned)
  ([ADR 0005](decisions/0005-outbox-for-musicdatabase.md),
  [ADR 0014](decisions/0014-github-database-and-request-packages.md)).

### Słuchanie

- Odtwarzanie **→ Odtwarzanie** (`playback_settings_screen.dart`) — **implemented**, section *Źródła*:
  - Kolejność odtwarzania **→ Kolejność odtwarzania** (`playback_order_screen.dart`) — drag to
    reorder the playback sources (default: 1. Telefon, 2. Serwer, 3. YouTube; Serwer = the song's
    file in MusicDatabase's music library, streamed — [ADR 0010](decisions/0010-server-files.md)),
    and a switch per source (all on by default; a switched-off source is never used, and with
    YouTube off a song no other source has isn't searched there either). When a song is playable
    from several, the first one in this order is used.
  - "Sposoby odtwarzania YouTube" **→ Sposoby odtwarzania YouTube** (`youtube_playback_screen.dart`):
    every `YouTubePlaybackMethod` with a switch and a drag handle; the first switched-on one that
    works plays the video (`YouTubePlayback`). Default order and state: "Pamięć podręczna" (on),
    "Korzystaj z NewPipeExtractor" (on; disabled with "Dostępne tylko na Androidzie"
    elsewhere), "Korzystaj z pakietu youtube_explode" (off — YouTube answers 403), "Korzystaj z
    yt-dlp przez serwer" (off, not implemented), "Otwórz w aplikacji YouTube" (on — the last
    resort: opens the video in the YouTube app — inside its YouTube playlist when the song plays
    from an imported one — or the browser without it, and pauses this app's player). The tile shows the active order ("1. Pamięć podręczna, 2. NewPipe, ...").
  Then a note (the cache of played songs is in Oszczędzanie danych › Pamięć podręczna) and section
  *Przejścia między utworami*:
  "Przenikanie utworów" — slider Wył.–12 s (1 s steps, default off, saved on release): the
  next queue song starts that long before the current one ends, one fading out as the other
  fades in; only when the queue moves on by itself ("Następny" and tapped songs switch at
  once). See [`agent-notes/local-library.md`](agent-notes/local-library.md).
- Muzyka na telefonie **→ Muzyka na telefonie** (`local_music_screen.dart`) — **implemented**:
  - Folders to scan, each with × to remove; "Dodaj folder" asks for read access to music files
    and opens Android's folder picker (`file_picker`).
  - "Ostatnie skanowanie" and "Skanuj teraz": finds audio files in the folders (recursively),
    adds new ones to the phone's `local.db` — artist/title from tags, else from the
    "Artist - Title" file name — and links each to MusicDatabase (`main_db_id`) or marks it
    `pending`; drops files that are gone and re-checks earlier pending ones.
  - "Utwory zapisane na urządzeniu: X" and "Nowe utwory spoza bazy danych: X" — the latter
    **→ list of pending files** (`PendingSongsScreen`).
- Historia odtwarzania **→ Historia odtwarzania** (`history_settings_screen.dart`) —
  **implemented**: "Przechowuj historię" (dialog: 7 / 30 / 90 — default / 180 dni, Rok, Bez
  limitu; older plays are deleted on start and with each new play, `PlayHistory.keepDays`;
  never more than 1000 kept), "Wyczyść historię" (confirm dialog, same as in Ostatnie).

### Wyszukiwanie i import

- YouTube **→ YouTube** (`youtube_source_screen.dart`, state in `SourceSettings`)
  section *Wyszukiwanie*:
  - "Włącz szukanie w serwisie YouTube" (on by default, like Spotify's playlist search — owner's
    choice) — turns on the "Wyszukaj na YouTubie" button and
    looking up songs on YouTube when tapped (see song search below).
  - "Korzystaj z NewPipeExtractor" (on; Android only), "Korzystaj z pakietu youtube_explode"
    (on), "Korzystaj z yt-dlp przez serwer", "Korzystaj z API" — the search methods, tried top
    to bottom, the next one only when the previous fails (`YouTubeSearch`). Only selectable while search is on. **yt-dlp przez
    serwer is not implemented** (MusicDatabase's server has no search endpoint; that needs an
    ADR) — it's skipped with a note in the error message.
  - "Kod YouTube API" — dialog for the Data API key, used by "Korzystaj z API"; the tile shows
    only its last four characters, empty input clears it. Stored in plain
    `shared_preferences`.
  section *Playlisty* (below the search methods — user's choice: it's about playlists, not
  songs): "Wyszukuj playlisty na YouTube" (on) — the online button also searches YouTube
  playlists; only selectable while search is on, and only acts while "Wyszukuj playlisty"
  (search filters) is on (the subtitle says so otherwise).
- Spotify **→ Spotify** (`spotify_source_screen.dart`) — section *Wyszukiwanie*: "Wyszukuj
  playlisty na Spotify" (on; the search button also searches Spotify playlists, while
  "Wyszukuj playlisty" in the search filters is on), **Spotify API** (implemented: dialog for
  the Client ID and Client Secret of the user's own Spotify app — with them playlists are
  searched through the Web API, without them or when it fails the way the web player does;
  blank clears; stored in plain `shared_preferences`; the tile shows the id's last four
  characters) and a note on both ways. Section *Importowanie playlist*: a note on the embed
  page's 100-track limit (the key doesn't lift it yet). Spotify is not a playback source.

### Wyświetlanie

- Wygląd **→ Wygląd** (`appearance_screen.dart`) — **implemented**, everything applies at once
  and is remembered after restart:
  - Motyw jasny **→ list of light themes** (Dummify, Redesign) — used while dark mode is off.
  - Motyw ciemny **→ list of dark themes** (Dummify, Lain — the default, Cyberpunk) — used while dark mode
    is on.
  - "Przełącz na tryb ciemny" — switch; off = light theme, on = dark theme. Greyed out (showing
    the system's current mode) while the next switch is on.
  - "Systemowe przełączanie trybu ciemnego" — switch; when on, light/dark follows the phone's
    dark-mode setting.
  - "Nazwy w alfabecie łacińskim" — switch, on by default: a title, artist or album in another
    alphabet is followed by its Latin form from music.db, "Кино (Kino)" — song rows, the queue,
    menus, the mini/full player and the notification (`latin_names.dart`, `song_names.dart`;
    hand-off [`musicdatabase-latin-names.md`](handoffs/musicdatabase-latin-names.md)).
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
- Okładki albumów **→ Okładki albumów** (`cover_sources_screen.dart`) — **implemented**: the cover
  sources with switches, drag to reorder (Serwer — dummy, always off; Plik na telefonie; iTunes;
  Deezer; Miniatura z YouTube); the cover cache is in Oszczędzanie danych › Pamięć podręczna. See
  [`agent-notes/covers.md`](agent-notes/covers.md).

### Dane

- Oszczędzanie danych i tryb offline **→ Oszczędzanie danych i tryb offline**
  (`data_saver_screen.dart`) — **implemented**: "Zapisuj następne utwory z kolejki tylko przez
  Wi-Fi" (off by default; Wi-Fi = the phone has a Wi-Fi IP address), "Pobieraj okładki tylko
  przez Wi-Fi" (off by default; on cellular only cached covers and covers inside phone files show),
  "Pobieraj teksty piosenek" (on by default; off hides the full player's lyrics card and never
  asks LRCLIB — `SourceSettings.lyrics`),
  Pamięć podręczna **→ Pamięć podręczna** (`cache_settings_screen.dart`; subtitle: MB used in
  total) — every cache setting, nowhere else ("Pamięć podręczna" is the one name used in the UI):
  - "Zajęte razem: X MB" (with the downloaded songs).
  - *Pobrane* — "Pobrane utwory" ("N utworów, X MB": songs kept with "Pobierz") and "Usuń
    wszystkie pobrane" (confirm: server copies deleted, YouTube audio back in the cache). They're
    outside the YouTube limit and "Wyczyść" / "Wyczyść wszystko" leave them.
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
- Kopia zapasowa **→ Kopia zapasowa** (`backup_screen.dart`, `user_backup.dart`; sharing
  checklist 4.1, for people without a MusicDatabase account) — **implemented**:
  "Zrób kopię zapasową…" (a `.zip` of `local.db` without its cache tables, the outbox, picked
  covers, the settings without secrets / this phone's state — `UserBackup.keptKeys` — and the
  links saved for later, through the share sheet; only the newest kept on the phone),
  "Ostatnia kopia" (date), "Przywróć z pliku…" (file picker → "Przywrócić kopię zapasową?" with
  the backup's date → the backup is unpacked to `backup_restore/`, the links go to
  `LaterLinks.kt` at once, and the app closes (`exit(0)`); `main` puts the rest in place on the
  next start before anything opens it; the subtitle then says which backup was restored). A
  backup from a newer `local.db` version is refused. A note lists what's in and what isn't.

### Aplikacja

- Otwieranie linków **→ Otwieranie linków** (`link_settings_screen.dart`) — **implemented**:
  "Linki z YouTube" / "Linki ze Spotify" (dialog: Pytaj za każdym razem — default, Leina Radio,
  Aplikacja YouTube/Spotify, Przeglądarka; the same choice "Zapamiętaj wybór" in the link sheet
  sets; the sheet also has "Zapisz na później" → "Od kogo?", see Ja › Na później), what a link does in the app, how to give the links to the app in the phone settings,
  "Otwieraj linki w Leina Radio" (the phone's "Otwieraj domyślnie" for the app — Android 12+;
  app info on older ones). The sheet itself is native (`LinkChooserActivity.kt`, see
  [`agent-notes/youtube.md`](agent-notes/youtube.md)).
- Prywatność i połączenia **→ Prywatność i połączenia** (`privacy_screen.dart`) — **implemented**:
  no ads / analytics / crash reports; what stays on the phone; then one section per service the
  app talks to (Serwer MusicDatabase, GitHub, YouTube, Konto Google, Spotify, Okładki: iTunes,
  Deezer, miniatury YouTube, LRCLIB, Przeglądarka i „Udostępnij”) — why, when, what it gets, a
  "Teraz: …" line in every section — "łączy się z serwerem / z internetem (what for)" in the accent
  colour (plus "zalogowano jako …" for the server and Google), or "nie łączy się …" in the theme's
  error red — and rows that open the screen with its switch (Serwer, Konto, Kolejność
  odtwarzania, YouTube, Pamięć podręczna, Spotify, Źródła okładek, Oszczędzanie danych,
  Informacje i pomoc) or "Tylko gdy sam tego użyjesz"; last "Synchronizacja danych".
- Informacje i pomoc **→ Informacje i pomoc** (`about_screen.dart`) — **implemented**: the
  version at the top ("Leina Radio — wersja": `version` from `pubspec.yaml`, the build number
  and commit, e.g. "1.0.0 (kompilacja 26, c11e6c4+zmiany)" — see `tool/build_release_apk.sh`); then,
  only in builds with `tool/release.env`, "Aktualizacje" (the newest GitHub release: "Dostępna
  wersja … — stuknij, żeby pobrać" in the accent colour opens the update dialog, otherwise the
  last check; ⟳ "Sprawdź teraz") and "Sprawdzaj aktualizacje automatycznie" (switch, on — once a
  day). A newer release is also offered once at start in "Dostępna nowa wersja …" (notes,
  "Pobierz" → the APK in the browser, "Później") —
  [`agent-notes/releases.md`](agent-notes/releases.md). "Tylko do
  użytku prywatnego" (YouTube terms, never in an app store, may share with friends together with
  the source), licence GPLv3, "Kod źródłowy" (opens the GitHub repo; copy button), "Licencje
  bibliotek" (Flutter's licence page). See [ADR 0004](decisions/0004-license-and-distribution.md).
  Section "Problemy": **Zgłoś problem** (`problem_report_screen.dart`: "Co się stało?" field, a
  note on what the report holds, "Wyślij" → a `.txt` through "Udostępnij", "Podgląd raportu" —
  version, build, commit, small/large APK, phone model, Android, the description, the error log)
  and **Dziennik błędów** (`error_log_screen.dart`: the last 14 days newest first, "Wyczyść" after
  asking; subtitle "Wpisów: N" or "Pusty"). Also "Linki z YouTube i Spotify": a pointer to Ustawienia › Otwieranie linków, and "Rozmiar
  aplikacji" (the APK holds three CPU builds, ~22 MB each in use; the cache takes the
  most while used) with "Pamięć podręczna — Zajęte X MB" → Pamięć podręczna.

## Explanations on a long press (`feature_info.dart`, texts in `feature_infos.dart`)

A long press on these opens a sheet — what it is, what it's for, how it works, libraries, what it
connects to, buttons (Prywatność i połączenia; Wyloguj z Google; Konto): the bottom bar's Home
and Odkrywaj; a song menu's "Przejdź do radia utworu" (`MenuSheetEntry.onLongPress`);
Ustawienia › Konto › the Google account's e-mail and "Synchronizuj"; Ja › Statystyki słuchania;
Ustawienia › Serwer and › Zgłoszenia poprawek; Sposoby odtwarzania YouTube › NewPipeExtractor and
youtube_explode; YouTube › NewPipeExtractor, youtube_explode and "Korzystaj z API"; Spotify ›
Spotify API (both APIs marked "W budowie — jeszcze nie sprawdzone w praktyce").

## Home (`home_screen.dart`)

- Filters (**implemented**, not remembered): Wszystko, Utwory (the rows of songs: Ostatnio
  odtwarzane, Polubione utwory, Na później, Nowe w bazie, Zapomniane), Playlisty (Twoje playlisty, rows added from
  a playlist), Nastroje (Twoje nastroje, rows added from a mood); the artists', albums' and
  genres' rows show only with Wszystko. ⚙ (tune icon)
  "Dostosuj stronę główną" **→ Dostosuj stronę główną**.
- Rows in the user's order (`HomeLayout` in `data/home_layout.dart`, phone only): pinned ones
  first (a pin before the title), hidden ones left out. Every row scrolls sideways with all its
  cards (no "Pokaż wszystko"). From the phone (**implemented**; left out while empty):
  Ostatnio odtwarzane (the history's last 12 songs), Polubione utwory (the 12 last liked), Twoje playlisty, Twoje nastroje, Na później
  (saved songs); rows added from Biblioteka (a playlist's / mood's first 12 songs). Song cards
  play the row from the tapped song; playlist / mood cards open it. Then the recommendations
  (**implemented**, ids `rec:…`, `HomeRecommendations` in `data/home_recommendations.dart` from
  the listening stats over everything and music.db; each left out while it has nothing):
  Twoi najczęściej słuchani wykonawcy (round covers of their most played song **→ the artist's
  songs**), Albumy, do których wracasz (**→ the album's songs**), Nowe w bazie (music.db's 12
  highest ids — MusicDatabase numbers songs as they're added), Twoje gatunki (the genres of
  what was heard, most played first; before any plays the day's genres from Wyszukaj **→ the
  genre's songs**), Zapomniane (songs heard at least twice but not for 60 days). The old sample
  rows' `sample:…` ids left in a saved layout are passed over.
- "⋯" on every row (**implemented**): Przypnij na górze / Odepnij, Przenieś wyżej, Przenieś
  niżej, Ukryj sekcję (an added one: Usuń sekcję), Dostosuj stronę główną.
- **Dostosuj stronę główną** (`CustomizeHomeScreen`): "Rekomendacje" switch (the rows above),
  "Dodaj sekcję z Biblioteki" (a sheet of playlists and moods), then every row with a checkbox
  (shown), a pin and ≡ to drag it into order.

## Wyszukaj (`search_screen.dart`)

- Filter icon (top right, where the reference app has a camera; also in the search screen's app
  bar) **→ sheet "Szukaj w"** (`search_fields_sheet.dart`) — **implemented**: checkboxes for the
  fields song search looks at — Tytuł, Wykonawca (incl. additional artists and the artists'
  other names / `synonyms`), Album, Nastrój (a mood's name lists its songs; these four are the
  default), Rok, Język, Pochodzenie wykonawcy — plus "Przywróć
  domyślne". At least one stays ticked; the choice is remembered. Below them the switch
  "Wyszukuj playlisty" (on): Biblioteka playlists while typing, and with the button YouTube /
  Spotify playlists as their own settings allow; and "Wyszukuj albumy" (on). A dot on the icon
  means the selection differs from the default (playlists or albums off counts).
- "Czego chcesz posłuchać?" field **→ song search** (`song_search_screen.dart`) —
  **implemented**: searches as you type, over the fields chosen in "Szukaj w", in both the
  downloaded `music.db` and the phone's own `local.db` (`combined_search.dart`): MusicDatabase
  songs plus phone files not in MusicDatabase. Accents and case are ignored, like MusicDatabase's
  search. Shows a hint with a link to the "Serwer" settings when there's nothing to search.
  - Each result has one icon on the right (`SourceIcons`, in a slot of cover height and half its
    width): where tapping it plays from first — the first switched-on source in "Kolejność
    odtwarzania" that has the song (phone `smartphone`, server `dns`, YouTube `smart_display`;
    full when MusicDatabase stores the `youtube_video_id` or the phone found a video itself). When
    no source has it, a dimmed YouTube icon if searching YouTube may find it, else no icon: marked
    "N/A" (no video on YouTube) or the phone searched in the last 30 days and found nothing
    (`youtube_not_found`; tapping the song searches again, the queue skips it). Next to it (user's
    design): a "*" in the accent colour at the top when the song isn't in MusicDatabase (later it
    will be offered to be sent there for adding), and an `offline_pin` at the bottom when the song
    plays offline — a file on the phone or its YouTube audio in Pamięć podręczna — whatever the
    main icon is. Icons use the theme's secondary text colour.
  - Results are "Dostępne" (a phone file, pending or not, a file on the server, or a stored
    YouTube video),
    "Potencjalnie dostępne" (dimmed YouTube icon, not on the phone) or "Niedostępne"
    (`SongAvailability`). Tapping a result uses the first source in "Kolejność odtwarzania"
    that has it: phone → plays the file (**implemented**, `just_audio`, row highlighted with a
    green title + `PlayingBars`, bars that bounce while it plays and stop while paused, like the
    reference app's); server → streams the song's `files.db` file (`GET /library/<id>`, ADR 0010; the database icon is then a server icon); YouTube → streams the video's audio (**implemented on Android**
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
  - While YouTube search or Spotify playlist search is on, the list starts with a button —
    "Wyszukaj na YouTubie", "Wyszukaj na YouTubie i Spotify" or "Wyszukaj playlisty na Spotify".
    Nothing online is searched while typing; the results replace the button and are dropped when
    the query changes. All parts are searched at once, each with its own spinner / error with
    retry: "Playlisty na YouTube: N" and "Playlisty na Spotify: N" (rows of covers scrolled
    sideways — picture, name, owner, track count when known; tapping one opens its **preview**,
    see Playlista) and "YouTube: N" (up to 15 videos: artist and title read from the video's
    title like a playlist import's — `parseYouTubeTrack()`, so "Бумбокс - Твiй на 100%" from
    channel "familyboombox" is Бумбокс's song — and duration; a video music.db has, by its link
    or that artist and title, is that song (`hitForSearchedVideo` in `video_link.dart`); tapping
    one streams it like a song with a stored link).
  - "Utwórz kolejkę z wyników" (`Icons.playlist_play`, left of the filter icon in the search
    screen's app bar, while something is typed) — **implemented**: replaces the queue with every
    found song (the "Utwory: N" list, not the online results) in the list's order and plays the
    first, like tapping a song does for one (only the full albums while "Całe albumy" is ticked).
  - "Całe albumy: N" chip right of "Utwory: N" (**implemented**, only when some found song is a
    full album — music.db's `songs.kind`): ticked, the list shows only full albums. Full albums
    are marked "Cały album" with a disc icon in every song row, and in the mini / full player and
    the queue panel.
  - "Playlisty w Bibliotece: N" (while "Wyszukuj playlisty" is on): Biblioteka playlists whose
    name or owner contain every word, as you type, above the songs; tapping one opens it.
  - "Albumy: N" (while "Wyszukuj albumy" is on; `searchAlbums` in `combined_search.dart`): albums
    (music.db and phone files, grouped by album name like "Przejdź do albumu") whose name or its
    Latin form contains every word, best name match first, as a sideways row of covers (album,
    main artist or "Różni wykonawcy", song count) under the playlists; MusicDatabase's
    "Singles" is left out. Tapping one opens its songs (`openAlbumSongs`).
  - Every result (YouTube ones too) has a ⋮ **→ sheet**, IDs `Wyszukaj › Utwór › Menu (⋮) ›
    <pozycja>`: Dodaj do kolejki (**implemented**), Odtwórz jako następny (**implemented**),
    Dodaj do playlisty (**implemented → sheet "Dodaj do playlisty"** below), Dodaj do nastroju
    (**implemented**, MusicDatabase songs only, **→
    sheet "Dodaj do nastroju"** below), Zapisz na później / Usuń z „Na później” (**implemented**),
    Przejdź do albumu (**implemented**: the album's songs in a song list, a full album of it
    first — `openAlbumSongs`; left
    out for songs with no album), Przejdź do wykonawców ›, Przejdź do radia utworu (**implemented**,
    music.db songs: `songRadio` in `song_radio.dart` — the song, then up to 50 songs like it by
    shared artist, genres (`songs.genre`, once music.db has it — hand-off
    [`musicdatabase-genres.md`](handoffs/musicdatabase-genres.md)), moods, language, country and
    decade, at most 8 per artist, no full albums, the same list for the same song; a song list
    with Odtwórz / Losowo. Phone-only logic — MusicDatabase has no radio),
    Udostępnij (**→ Udostępnij utwór**, below), Wyświetl informacje o utworze (**implemented**: the
    full player's "Informacje o utworze" card in a sheet — `showSongInfoSheet` in `song_info.dart`); above them, in a smaller
    block, Pobierz utwór (**implemented**, `downloadEntry`: hidden for a phone file; "Pobieram…"
    while it downloads, "Usuń z pobranych" once done; a note when it's done or failed — see
    Playlista › Pobierz for what's kept), Wyłącznik czasowy (**implemented → sheet**, `sleep_timer_sheet.dart`:
    5–45 min, 1 godz., Koniec utworu, and Wyłącz while on; the entry shows what's left — "Wyłącznik
    czasowy: 12 min". The time fades the music out over 5 s and pauses; Koniec utworu leaves the
    next song waiting in the player, as after a restart; not kept across restarts), Ukryj utwór /
    Przestań ukrywać (**implemented**, `HiddenSongs` in `data/hidden_songs.dart`, phone only:
    the queue passes over a hidden song when it moves on by itself — a tapped one still plays —
    Odkrywaj and a song's radio leave it out, its rows are dimmed; a note with Cofnij; the list
    in Ustawienia › Odtwarzanie › Ukryte utwory, `hidden_songs_screen.dart`).
    The same ⋮ is used in
    Ostatnie (`Ostatnie › Utwór › Menu (⋮)`). Entries with › unfold their options under them in
    the same sheet (`MenuSheetEntry.submenu`): Dodaj do playlisty › (Polub / Usuń z polubionych,
    Nowa playlista, then every playlist made on the phone) and Przejdź do wykonawców › (each artist of the song — **→ its
    songs**: `openArtistSongs`, every song in music.db and on the phone with that artist, a song
    list with Odtwórz / Losowo; `song_list_screen.dart`).
  - **The song menu** (`showSongMenu` in `song_tile.dart`): the same entries as this ⋮ — Dodaj do
    kolejki, Odtwórz jako następny, Dodaj do nastroju (for a song not in MusicDatabase it says
    only database songs can be in a mood), Dodaj do playlisty, the dummies, Udostępnij — open
    with a long press on song rows outside a selection area (YouTube results, Kolejka
    `Kolejka › Utwór › Menu (⋮)`, outbox contents), the full player's ⋮ (`Odtwarzacz › Menu
    (⋮)`) and a long press on the mini player (`Mini odtwarzacz › Menu utworu`).
  - **Ticking songs** (`SongSelectionArea` in `widgets/song_selection.dart`; song search,
    playlists, moods, Ostatnie, Pamięć podręczna, Utwory spoza bazy danych): a **long press on a
    song row** ticks it and starts ticking — taps then tick / untick instead of playing, the ⋮
    and the swipe go away, and a bar under the list shows "Zaznaczono: N", ✕, "Wszystkie" /
    "Odznacz" (playlists and moods) and Do kolejki, Jako następne, Do playlisty
    (→ "Dodaj do playlisty"), Do nastroju (→ "Nastrój dla wszystkich utworów"); songs go in the
    order they were ticked. Back (and ✕) unticks everything first. In search the ticks stay
    while the query changes.
  - Gestures on song rows (search results — YouTube ones too —, playlists, Ostatnie, every
    `SongTile`; `SwipeActions` in `swipe_actions.dart`): dragging a row right adds the song to
    the queue, like the reference app — past a quarter of the row (at most 120 px) the strip
    under it fills with the accent colour and the phone ticks; letting go there adds it, the
    row slides back either way. Dragging left does nothing yet (the reference app adds the
    song to Polubione utwory, which the app doesn't have).
  - Adding to the queue (gesture, ⋮ of a song or playlist) says so in a note right above the
    mini player, like the reference app's (`QueueToast` in `queue_toast.dart`, not a
    SnackBar): just "Dodano do kolejki" / "Zagra jako następny" (a playlist: "następna"),
    no title, short like the reference app (user's wish), with **Otwórz**
    (→ Kolejka). It goes after 3 s, or at once when the mini player or the bottom bar is
    touched, or the full player / Kolejka opens — it never stays over the full player.
    A song added outside the mood filter says instead (for 5 s) "Utwór dodany do kolejki jest
    poza filtrami nastroju: wyłączam filtr" (the default: the filter goes off and is cleared)
    or "…: będzie pominięty" (added hidden) — as set in Filtr nastrojów; with several songs
    "Utwory dodane… są…" / "Część utworów dodanych…". With nothing playing the first added song
    starts anyway and doesn't count.
  - **Udostępnij utwór** (`showSongShareSheet` in `share_sheet.dart`; also from the playlist
    track ⋮ and the full player): a card with the song's cover, title and artist over three round
    buttons — YouTube (**implemented**: the
    song's video link — music.db's, else one the phone found or the playlist's — to the phone's
    share sheet), Spotify (**implemented**: the track link — MusicDatabase's `spotify_url` when
    it's a track page, else the Spotify playlist's track), Plik (**implemented**: the audio file the
    phone has — its own, a server file downloaded with "Pobierz", or YouTube audio in the cache —
    to the phone's share sheet; not "MP3", since YouTube audio is webm/m4a). Each without a link
    or file is dimmed; tapping it says why. ("Leina Radio" was removed — user's decision.)
- Odkryj coś nowego (**implemented**, `discoverGenres`): up to six of music.db's genres
  (`songs.genre`), another draw each day, as `#genre` cards **→ the genre's songs**; left out
  while music.db has no genres.
- "Przeglądaj" grouped under headings (**implemented**, from music.db and the moods; the
  biggest first, at most 12 per group): Nastroje (**→ Nastrój**), Gatunki, Dekady (years to come
  left out; "Lata 80." only for the 1900s, other decades as "1890–1899"), Języki, Kraje
  wykonawców (the first part of `artists.origin`) — each **→ a song list** (Odtwórz, Losowo,
  song rows); full albums aren't counted or listed in them (nor do their genres alone make Odkryj coś
  nowego's or Home's "Twoje gatunki").
- Inne kategorie (**implemented**, each **→ a song list**): Ostatnio dodane (music.db's 100
  highest ids), Całe albumy (music.db's full albums — only when it has some), Najczęściej
  słuchane (the listening stats over everything, most played first), Bez nastroju (music.db
  songs in no mood), Bez linku YouTube (music.db knows no video), Tylko na telefonie (phone
  files not in MusicDatabase).

## Biblioteka (`library_screen.dart`)

- Wyszukaj w Bibliotece (**implemented**, 🔍 ↔ ×): a field; playlists, moods and folders (also
  those in folders) and dynamic playlists whose name holds every word typed.
- Utwórz (+) **→ sheet "Utwórz"** with prefix `Biblioteka › Utwórz (+)` (see below)
- Categories (rows with counts, each **→ its own list**, `LibraryCategoryScreen` with the sort
  button and "+"): Polubione utwory **→ Polubione utwory** (`SavedSongsScreen.liked`: liked songs
  newest first, "Odtwórz", song rows — like Na później below), Playlisty (not albums), Albumy (Spotify album imports), Nastroje ("Brak
  nastrojów" and how to add one when there are none), Foldery (only folders), Wykonawcy
  (**implemented**, `ArtistsScreen`: every artist in music.db and of the phone's songs not in it,
  with song counts, alphabetically, a field to narrow it — **→ the artist's songs**), Na później **→ Na później** (`saved_songs_screen.dart`: saved songs newest first,
  "Odtwórz", song rows; saved / taken out with the song menu's "Zapisz na później" / "Usuń z „Na
  później”" or Odkrywaj's bookmark — `SavedSongs`, synced with the account, ADR 0013), Dynamiczne playlisty **→
  Dynamiczne playlisty** (`smart_playlist_screen.dart`, below). A category shows its playlists /
  moods outside folders plus the folders holding any of them (inside, only those).
- Below the categories: everything — folders, playlists and moods outside folders, mixed in the
  sort order.
- **Dynamiczne playlisty** (`SmartPlaylists` in `data/smart_playlists.dart`, phone only): a
  saved filter — a song-search field (Tytuł, Wykonawca, Album, Rok, Język, Pochodzenie
  wykonawcy, Nastrój) and a value; its songs are searched in music.db and on the phone each time
  it opens. "Nowa" asks for the field, value and name. A playlist: rule and count, Odtwórz,
  Losowo, song rows; ⋮: Dodaj do kolejki, Dodaj do playlisty, Usuń dynamiczną playlistę.
- Sort button (shows current order) **→ sheet "Sortuj wg"** — **implemented**
  (`LibraryFolders` in `data/library_folders.dart`, remembered on the phone; also in a folder):
  - Ostatnie: last opened (playlist, mood or folder; a folder also by its newest item), else
    last changed; never-opened global moods last
  - Ostatnio dodane: when saved on the phone / made (global moods last)
  - Alfabetycznie: name, case and Polish letters aside, numbers by value ("2." before "10.")
  - Twórca: folders first, then the playlist's owner ("Ty" for ones made here; a mood: "Ty" or
    "MusicDatabase"), then name
- **Folders** — **implemented**, synced with the MusicDatabase account like playlists
  ([ADR 0011](decisions/0011-folder-sync.md); phone-only while logged out; Konto shows "Foldery"
  with ⟳ and offers to add phone-only ones); made from
  Utwórz › Folder or "Nowy folder" in "Przenieś do folderu"; row "Folder • N playlist, M
  nastrojów" **→ Folder** (`FolderScreen`: its items in the same order, sort button, ⋮ = the
  folder menu, "Pusty folder…" when empty). A **long press** on a playlist / mood row (here or in
  a folder) **→ sheet "Przenieś do folderu"** (`folder_sheet.dart`: Nowy folder, Bez folderu,
  every folder by name, the current one ticked); on a folder row **→ folder menu**
  (`Biblioteka › Folder › Menu (⋮)`: Zmień nazwę, Usuń folder — its items go back to
  Biblioteka). Folders don't nest; an item is in one folder at most.
- **Playing playlist / mood** — **implemented**: the row of the playlist or mood the playing
  song was queued from as a whole (its `QueueOrigin`: tapped there, or the whole playlist added
  to the queue; not a single song added from its ⋮) has a green title with `PlayingBars`, like
  the playing song in a list (also inside folders).
- Widok siatki / Widok listy (right of "Sortuj wg", also in categories and folders) —
  **implemented**: three covers per row with the name under them; remembered on the phone
  (`LibraryFolders.grid`), not synced.
- Covers show what a row is (`CollectionFrame`): a playlist has a stack of edges above its cover,
  an album (Spotify album import) one edge, a mood rounder corners and a crescent in the corner.
- Library items: the user's playlists (`PlaylistLibrary`, newest first; cover — the picked one
  or the collage, see Playlista › Header — name,
  "Playlista • <owner>") **→ Playlista** — the logged-in account's (synced with MusicDatabase,
  incl. ones made there, e.g. folder playlists) and the phone-only ones. No sample items any more; with no playlists the list
  shows "Brak playlist" and how to add one. Albums/artists don't exist yet.
- Moods (`MoodLibrary`, [ADR 0008](decisions/0008-moods.md)): the user's own ("Nastrój • Twój"),
  then the global ones ("Nastrój • globalny"), each by name **→ Nastrój**.

## Nastrój (`mood_screen.dart`) — **implemented**

- 🔍 in the app bar: a field in place of the name; the songs whose title or artist hold every
  word typed (× closes it).
- App bar with the name and ⋮ **→ sheet**, IDs `Nastrój › Menu (⋮) › <pozycja>`: Dodaj do
  kolejki / Odtwórz jako następny (the whole mood), **Nastrój dla wszystkich utworów**, Dodaj do
  playlisty (every song), Przenieś do folderu (see Biblioteka), and for
  the user's own mood Zmień nazwę
  (dialog) and Usuń nastrój (asks first; deleted on every device of the account, MusicDatabase
  archives it). For every mood, global ones too: **Dodaj okładkę** / **Zmień okładkę** (an
  image from the phone, synced with the account — a global mood's cover is the user's own) and **Usuń okładkę** (back to the collage).
- Header: cover (the picked one, else a collage like a playlist's — `MoodCover`), name, "Twój nastrój" / "Nastrój globalny" • "N utworów".
- **Odtwórz losowo**: the whole mood shuffled into the queue. A note when some of its songs
  aren't in the phone's music.db yet.
- Songs by title (tapping one plays on through the mood); ⋮ **→ sheet**, IDs `Nastrój › Utwór ›
  Menu (⋮) › <pozycja>`: Dodaj do kolejki, Odtwórz jako następny, Dodaj do nastroju, Usuń z tego
  nastroju (own mood, or a global one with the `edit_global_moods` permission), Udostępnij.

## Sheet "Dodaj do playlisty" (`playlist_picker.dart`)

- Header with the song (or "N utworów"); "Polubione utwory" (heart cover, song count; ⊕, or an
  accent ✓ when all these songs are liked — tapping likes them, or unlikes them when all are
  liked; `LikedSongs`, synced with the account — the only place a song is liked, user's decision); "Nowa
  playlista" (name dialog; a new playlist of these songs); then every playlist made on the phone (not imported — re-importing would replace the
  added songs; a note says so when there are imported ones) — tapping one puts the songs at its
  end, synced like any change.

## Sheet "Dodaj do nastroju" (`mood_sheet.dart`)

- Header with the song; "Nowy nastrój" (name dialog; the new mood gets the song); "Twoje
  nastroje" with a checkbox each (ticking adds / removes right away); "Globalne" the same, only
  with the `edit_global_moods` permission. Moods show a crescent moon (`moodIcon`) everywhere.

## Sheet "Nastrój dla wszystkich utworów" (`showMoodPickerForAll` in `mood_sheet.dart`)

From the playlist ⋮, the mood ⋮ and Kolejka (moon icon). The same lists as "Dodaj do nastroju",
each mood ticked when all the songs are in it, a dash and "N z M" when some are. Tapping one asks
"Czy na pewno? Dodać N utworów do nastroju „…”?" (the missing ones) — or, when all are in,
"Usunąć N utworów z…" — and changes them at once. "Nowy nastrój" makes one with all of them.
Songs not in MusicDatabase are left out (the sheet says how many).

## Sheet "Filtr nastrojów" (`showMoodFilterSheet` in `mood_sheet.dart`)

From the full player (filter icon) and Kolejka ("Nastroje: wł./wył."); kept across restarts.
A switch, "Utwory bez nastroju" (also songs not in MusicDatabase), then every mood (own and
global) with a checkbox; ticking anything switches the filter on, the ticks stay while it's
off. The queue plays songs in any ticked mood, plus — with "Utwory bez nastroju" — songs in no
mood; a ticked mood that's gone doesn't count. "Utwór dodany spoza filtra": **Wyłącz filtr**
(default — switches off and clears the ticks) or **Pomiń utwór** (added hidden).

## Playlista (`playlist_screen.dart`) — **implemented** for imported playlists

- **Preview** (`PlaylistScreen.preview`, from a YouTube/Spotify playlist found by search): the
  same screen, fetched from YouTube or Spotify (tracks recognised like on import) but not saved —
  playable, shareable. Instead of the Pobierz icon and the Dodaj/Edytuj/Sortuj chips there's one
  chip **"Zapisz w Bibliotece"** ("Zaktualizuj w Bibliotece" when it was imported before): it
  imports the fetched playlist and the screen becomes the saved one. Its ⋮ has only
  Udostępnij, Dodaj do kolejki / Odtwórz jako następną, Nastrój dla wszystkich utworów, the same save entry and "Wyświetl utwory, których nie ma w bazie danych". A failed
  fetch shows the error and "Spróbuj ponownie".

- Transparent app bar over the header; once the header scrolls away it turns solid and shows
  the playlist name (as in the reference app). Back arrow pops.
- Szukaj w playliście (search icon next to ⋮, **implemented**): the app bar turns into a search
  field and only the tracks whose title, artist or album contain every word of the query are
  listed (normalised like song search; "Brak wyników dla „…”" otherwise). Tapping one plays on
  through the whole playlist from it. Back (arrow or system) closes the search first — it's a
  local history entry of the route — and returns to the playlist where it was.
- Header: the cover picked with "Dodaj okładkę", else a 2×2 collage of the covers of the first
  four different albums (the first track's cover with fewer; a Spotify album always just one) —
  `CollectionCover`, also in Biblioteka, search and the menus; name, owner
  avatar + name (the YouTube channel / Spotify user; "YouTube"/"Spotify" when unknown,
  "MusicDatabase" for a folder; made on the phone: the account it syncs with, else "Leina
  Radio"), source icon
  (YouTube / Spotify) + "N utworów • X godz. Y min" (sum of the known lengths — a track's own,
  else music.db's video length, else its library file's; "ponad X godz. Y min" while some are
  unknown).
- Menu (⋮) **→ sheet**, IDs `Playlista › Menu (⋮) › <pozycja>`: **Udostępnij** (implemented, the
  same sheet as the icon below), **Dodaj do kolejki** / **Odtwórz jako następną** (implemented:
  the whole playlist into the queue, remembered as played from it; also in a preview's ⋮),
  **Nastrój dla wszystkich utworów** (also in a preview's ⋮),
  **`Usuń z
  Biblioteki`** (implemented: confirm dialog, deletes the playlist — not the songs), **Zmień
  nazwę** (implemented: synced like any change; importing the playlist again keeps the phone's
  name), **Dodaj do tej playlisty** / **Edytuj playlistę** (implemented, made on the phone only — the
  chips below), **Dodaj okładkę** / **Zmień okładkę** and **Usuń okładkę**
  (implemented, like a mood's), **Wyświetl utwory, których nie ma w bazie danych**
  (implemented **→ Utwory spoza bazy danych**, `missing_tracks_screen.dart`: the playlist's
  tracks not recognised as MusicDatabase songs, "Poza bazą danych: N z M", rows like the
  playlist's — tapping plays on through the playlist from there; a note instead when music.db
  isn't downloaded; later the place to ask MusicDatabase to add them), Dodaj do innej playlisty
  (**implemented**: every track → "Dodaj do playlisty"), Przenieś do folderu (**implemented**, see
  Biblioteka).
- Pobierz (ikona, **implemented**, saved playlists): downloads every song not on the phone yet,
  one at a time (`Downloads` in `playback/downloads.dart`, `TrackPlayer.download`) — from the
  first source in the play order that has it: a file of MusicDatabase's library is copied to
  `<support>/downloads/` (`ServerDownloads`; it then plays from there, the server not asked),
  else the YouTube audio is kept in the cache, `pinned` (local.db v18), outside the limit; with
  the server out of reach YouTube is tried. A note "Pobieram N utworów…", then done / how many
  failed. A spinner while it works; filled and green once every song is offline (a phone file
  counts) — tapped then, "Usunąć pobrane?" takes them off; green outline when only some are.
  Downloaded songs show the offline pin ("Dostępne offline (pobrane)"). The songs waiting are kept in
  `local.db`'s `download_queue` (v19) and the run goes on after the app was frozen or killed:
  on start and on every return to the app (`Downloads.resume`); a song that failed 3 runs is
  given up. While it runs, `DownloadService.kt` (a `dataSync` foreground service, notification
  "Pobieranie utworów: N z M" with a progress bar) keeps Android from freezing the app, so it
  goes on with the screen off. Not done: songs added to a downloaded playlist later aren't
  downloaded by themselves.
- Udostępnij (ikona, **implemented → Udostępnij sheet**,
  `share_sheet.dart`: a card with the playlist's mosaic, name and "Playlista • <owner>" over three
  round buttons — Kopiuj link, Otwórz w YouTube/Spotify, Więcej (the phone's share sheet). The
  link is the playlist's page where it was imported from: `youtube.com/playlist?list=…` or
  `open.spotify.com/playlist/…`. A playlist with no link — made on the phone, or a MusicDatabase
  folder — has Kopiuj link / Więcej dimmed and **Utwórz na YouTube** in the middle
  (`youtube_export_dialog.dart`: "Utworzyć playlistę na YouTube?" → Google sign-in → an unlisted
  YouTube copy, progress with Przerwij, then what was skipped and "Otwórz w YouTube"); after that
  the sheet shows the copy's link, or **Dokończ na YouTube** when it stopped half-way, e.g. at
  YouTube's daily limit — see [`youtube.md`](agent-notes/youtube.md)), Odtwarzanie losowe
  (**implemented**: queues the playlist shuffled, from a random track), Odtwórz playlistę
  (**implemented**: queues the playlist from its first track, shuffle off),
  chips (**implemented**):
  - **Dodaj** and **Edytuj** — only on a playlist made on the phone (`source` NULL): an imported one's
    next import replaces its tracks. Dodaj **→ `playlist_add_screen.dart`**: song search (music.db
    and the phone), ⊕ puts a song at the end at once (`PlaylistLibrary.addSongs`), ✓ when it's
    already there (tapped again: a note). Edytuj **→ `playlist_edit_screen.dart`**: the tracks in
    their own order, dragged by the handle, ⊖ takes one out; nothing changes until "Zapisz"
    (`PlaylistLibrary.rearrange`, synced), Back drops the edit without asking (`AppShell` pops tab
    routes past a `PopScope`).
  - **Sortuj** — every saved playlist: Własna kolejność, Ostatnio dodane (made on the phone only:
    its own order backwards — added songs go at the end, so after an Edytuj it's the edited order
    backwards), Tytuł, Wykonawca. The list and what plays follow it; kept on the phone per playlist
    (`shared_preferences` `playlist.sort.<uid>`), not synced; the chip shows the pick.
- Tracks: the same rows as song search (`SongTile`: cover, title highlighted while playing,
  source icons) but with just the artist under the title, plus a ⋮. Tapping queues the whole
  playlist at that track and plays it like in search (phone file / YouTube in the user's order);
  the full player says "Odtwarzanie z playlisty <name>". A recognised track is its MusicDatabase song (database icon, phone icon if the file is
  on the phone); every YouTube-imported track has its video, so the YouTube icon is full; an
  unrecognised Spotify track has none (empty icon) and is searched on YouTube when played; the
  video found is remembered (full icon from then on). Opening the
  playlist that's playing jumps to the song playing, third row under the app bar (as far as the
  list can scroll; the entry playing, when queued from this playlist, knows its place in it).
- Track ⋮ **→ the song's menu** (the same as search's, `showSongMenu`), IDs `Playlista › Utwór ›
  Menu (⋮) › <pozycja>`, with Usuń z tej playlisty (**implemented**, every saved playlist; synced;
  an imported one's next import leaves the track out) after the queue entries.

## Utwórz sheet (`create_sheet.dart`)

Opened from Biblioteka's "+" (prefix `Biblioteka › Utwórz (+)`), also on a category's screen:

- Playlista **→ sheet** (`playlist_import.dart`):
  - Utwórz nową playlistę (**implemented**): name dialog, then an empty Biblioteka playlist to
    fill with "Dodaj do playlisty".
  - Importuj playlistę **→ dialog** for a YouTube playlist link (or bare id) or a Spotify one
    (`open.spotify.com/playlist/…`, `spotify:playlist:…`, `spotify.link/…`; anything else is
    refused in the dialog), then "Importuję playlistę…" and a snackbar
    "Zaimportowano/Zaktualizowano „<name>”: N utw., w bazie danych M." The playlist appears in
    Biblioteka. Importing the same playlist again replaces its tracks; YouTube tracks whose
    video YouTube removed stay (dimmed YouTube icon, searched again when played), and the
    snackbar adds "YouTube usunął N utw. — zostały na liście i zostaną wyszukane od nowa." Spotify: at most 100
    tracks; the snackbar then adds "Spotify pokazuje bez logowania tylko pierwsze 100 z N."
- Nastrój (**implemented**): name dialog, then a new mood — the logged-in user's, or one only on
  this phone while logged out ([ADR 0008](decisions/0008-moods.md)).
- Folder (**implemented**): name dialog, then an empty Biblioteka folder.

## Deliberately left out

- Spotify-branded entries ("Spotify Singles", "Netflix" category, "Pokaż kod Spotify").
- Removed (user's decision, 2026-10-16): Utwórz › Współtworzone playlisty and Blend (they need
  friends' accounts on MusicDatabase — back to it with those), Pokaż kod playlisty (the link is
  in Udostępnij), Udostępnij › Leina Radio, Home's Podcasty filter and sample rows, Wyszukaj's
  Spotify categories.
- Removed at the user's request: settings entries "Reklama", "Kontrola rodzicielska",
  "Prywatność i funkcje społecznościowe", "Wyświetlane treści", "Aplikacje i urządzenia", the
  "Darmowe konto" header with its Premium button, the camera icon on Wyszukaj and the whole
  Premium tab. Never built: ads and the reaction (emoji) button on tracks.
- Ustawienia: Spotify's quick tiles (Tryb
  oszczędzania danych, Sesja prywatna), Powiadomienia, Jakość zawartości multimedialnej and the
  "Wyloguj" button at the bottom were removed (user's decision; logging out is in Konto).
