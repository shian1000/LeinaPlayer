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

## Player (`lib/src/screens/now_playing.dart`, `lib/src/playback/player_controller.dart`)

- Mini player — appears above the bottom bar once something plays: cover, title, artist,
  play/pause, thin progress line. Tapping it **→ full player** (slides up, covers the bottom bar):
  - Header: ⌄ (collapse), "Odtwarzanie z wyników wyszukiwania / „<query>” w wyszukiwarce",
    `Odtwarzacz › Menu (⋮)`.
  - Big cover, title, artist, `Odtwarzacz › Dodaj (+)`.
  - Seek bar with elapsed/total time (**implemented**).
  - `Odtwarzacz › Losowo`, previous (**implemented**: restarts the song — no queue yet),
    play/pause (**implemented**), `Odtwarzacz › Następny`, `Odtwarzacz › Wyłącznik czasowy`.
  - `Odtwarzacz › Urządzenia`, `Odtwarzacz › Udostępnij`, `Odtwarzacz › Kolejka`.

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
- `Menu profilu › Ostatnie`
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
- Wygląd **→ Wygląd** (`appearance_screen.dart`) — **implemented**, everything applies at once
  and is remembered after restart:
  - Motyw jasny **→ list of light themes** (Dummify) — used while dark mode is off.
  - Motyw ciemny **→ list of dark themes** (Dummify, Lain) — used while dark mode is on.
  - "Przełącz na tryb ciemny" — switch; off = light theme, on = dark theme. Greyed out (showing
    the system's current mode) while the next switch is on.
  - "Systemowe przełączanie trybu ciemnego" — switch; when on, light/dark follows the phone's
    dark-mode setting.

  Themes are defined in `lib/src/theme.dart` (see [`agent-notes/theming.md`](agent-notes/theming.md)).
- `Ustawienia › Odtwarzanie`
- `Ustawienia › Powiadomienia`
- `Ustawienia › Oszczędzanie danych i tryb offline`
- `Ustawienia › Jakość zawartości multimedialnej`
- `Ustawienia › Informacje i pomoc`
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
    it isn't in MusicDatabase yet), and a YouTube-style play icon (no action yet). Hidden icons
    keep their slot so the column lines up.
  - Results are "Dostępne" (playable — for now: a file on the phone, pending or not),
    "Potencjalnie dostępne" (nothing yet) or "Niedostępne" (`SongAvailability`). Tapping a
    "Dostępne" result plays the phone file (**implemented**, `just_audio`) and highlights the row
    (green title + equalizer icon); tapping any other shows "Ten utwór jest niedostępny".
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
- `Biblioteka › Importuj swoją muzykę`
- Library items: playlists **→ Playlista**; albums and artists are dummies
  `Biblioteka › Element: <tytuł>`.

## Playlista (`playlist_screen.dart`)

- Back arrow — pops the screen.
- Menu (⋮) in the app bar **→ sheet**, IDs `Playlista › Menu (⋮) › <pozycja>`:
  `Udostępnij`, `Usuń z Biblioteki`, `Pobierz`, `Dodaj do tej playlisty`, `Edytuj playlistę`,
  `Dodaj do innej playlisty`, `Rozpocznij Jam`, `Zgłoś`, `Przenieś do folderu`, `Usuń z profilu`,
  `Opuść playlistę`, `Nie uwzględniaj playlisty w profilu gustu`, `Pokaż kod playlisty`.
- `Playlista › Wiadomość`
- `Playlista › Dodano do Biblioteki (✓)`
- `Playlista › Pobierz (ikona)`
- `Playlista › Udostępnij (ikona)`
- `Playlista › Odtwarzanie losowe`
- `Playlista › Odtwórz playlistę`
- `Playlista › Dodaj (do tej playlisty)` / `Edytuj (playlistę)` / `Sortuj (playlistę)`
- Tapping a track: `Playlista › Utwór (odtwórz) <n>`
- Track ⋮ **→ sheet**, IDs `Playlista › Utwór › Menu (⋮) › <pozycja>`:
  `Udostępnij`, `Dodaj do Polubionych utworów`, `Dodaj do playlisty`, `Usuń z tej playlisty`,
  `Dodaj do kolejki`, `Przejdź do kolejki`, `Przejdź do albumu`, `Przejdź do wykonawców`,
  `Rozpocznij Jam`, `Nie uwzględniaj utworu w profilu gustu`, `Przejdź do radia utworu`,
  `Pokaż autorów utworu`, `Pokaż kod utworu`.

## Utwórz sheet (`create_sheet.dart`)

Opened from the bottom-nav tab (prefix `Utwórz`) or the Library "+" (prefix
`Biblioteka › Utwórz (+)`):

- `… › Playlista`
- `… › Współtworzone playlisty`
- `… › Blend`

## Deliberately left out

- Spotify-branded entries ("Spotify Singles", "Netflix" category, "Pokaż kod Spotify" — renamed to
  "Pokaż kod playlisty/utworu").
- Removed at the user's request: settings entries "Reklama", "Kontrola rodzicielska",
  "Prywatność i funkcje społecznościowe", "Wyświetlane treści", "Aplikacje i urządzenia", the
  "Darmowe konto" header with its Premium button, the camera icon on Wyszukaj and the whole
  Premium tab. Never built: ads and the reaction (emoji) button on tracks.
- Deeper levels below the first settings screen; apart from "Wygląd" and "Źródła muzyki", each
  settings entry is a single dummy.
