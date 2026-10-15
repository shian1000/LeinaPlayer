# Pomysły z redesignu Spotify (Juxtopposed)

Źródło: film „I Redesigned the ENTIRE Spotify UI from Scratch” (Juxtopposed,
https://www.youtube.com/watch?v=suhEIUapSJQ) i jej projekt w Figmie („Spotify Redesign”,
strona „Redesign”, sekcja *Mobile*). Brane pod uwagę tylko ekrany telefonu.

## Co autorka poprawiła w UI Spotify (telefon)

1. **Typ elementu widać po kształcie okładki**, nie tylko po obrazku: album — kwadrat z jedną
   „krawędzią okładki płyty” u góry, playlista — kilka nałożonych krawędzi (stos), wykonawca —
   koło, podcast — kolorowy pasek przy tytule, audiobook — pionowa „książka”. Przy playliście i
   albumie liczba utworów obok tytułu.
2. **Dolny pasek: Home, Discover, Search, Library, Me.** Zniknęła zakładka Premium (na iPhonie i
   tak bezużyteczna), a profil, ustawienia i abonament przeszły z awatara w lewym górnym rogu
   (poza zasięgiem kciuka) do zakładki „Me” na dole.
3. **Zakładka „Me” (profil)**: karta profilu (nazwa, obserwujący, ID do skopiowania, ołówek,
   udostępnij), lista znajomych z tym, czego teraz słuchają, i „dodaj znajomego” (wyszukiwanie po
   nazwie, bez Facebooka), karta obecnego planu, potem „Historia słuchania”, „Ustawienia i
   prywatność”, „Co nowego”.
4. **Home**: bez filmików/klipów, które same się odtwarzają po wybraniu filtra; chipy
   Music/Podcasts/Audiobooks + ikona „dostosuj” obok nich; każda sekcja ma „⋯” — przypnij na
   górę, ukryj, przenieś; można dodać własną sekcję z Biblioteki i wyłączyć dynamiczne
   rekomendacje. Przypięta sekcja ma ikonę pinezki. Wszystkie elementy rzędu w jednym przewijaniu
   w bok (bez „Pokaż wszystko”).
5. **Nowa zakładka „Discover”**: pionowe karty-klipy z podglądem utworu (fragment z falą),
   kategorie przesuwane w bok (Podcast, Music, EDM, Indie, Pop…), z boku: wykonawca (+obserwuj),
   **„Zapisz na później”** (zakładka z liczbą zapisów — osobno od polubionych, żeby nie mieszać
   z ulubionymi), dodaj do playlisty, udostępnij; tagi gatunków pod spodem.
6. **Wyszukiwarka**: „Przeglądaj wszystko” pogrupowane pod nagłówkami (Discover, Genres, Mood &
   Activity…) zamiast jednej sałatki kafelków; filtry wyników wyglądają inaczej niż zwykłe
   przyciski/tagi.
7. **Wyszukiwarka na każdej stronie** (Biblioteka, playlista: „Search playlist” + sortowanie u
   góry).
8. **Strona playlisty/albumu**: okładka średniej wielkości, tytuł o stałym rozmiarze (nie
   skacze zależnie od długości), „Twórca • N utworów • czas”, rząd akcji: dodaj, dodaj do
   kolejki, pobierz, ⋯ — a po prawej losowo + odtwórz. Na albumie: tagi gatunków i lista
   wszystkich wykonawców. Na liście utworów: zaznaczanie wielu i akcje na wszystkich.
9. **Strona wykonawcy** (głównie desktop, ale idea ogólna): zakładki (Główna, Albumy, Single i
   EP, Kompilacje, O wykonawcy) zamiast jednej długiej strony; na głównej „Najczęściej przez
   Ciebie słuchane” obok popularnych; albumy zwinięte, rozwijane, siatka lub lista.
10. **Mini odtwarzacz**: zamiast ikony urządzeń — „dodaj do playlisty”; **przytrzymanie**
    pokazuje nad nim trzy szybkie akcje: ukryj utwór, urządzenia, polub. Zaokrąglona,
    „pływająca” karta.
11. **Pełny odtwarzacz**: obok tytułu osobno ♡ (polub) i ⊕ (dodaj do playlisty) — w Spotify jedno
    (+) najpierw dodaje do polubionych, a playlistę trzeba wybierać drugi raz. Przyciski „⋯”,
    urządzenia, udostępnij, tekst, kolejka — wszystkie w jednym dolnym rzędzie, w zasięgu kciuka
    (⋯ już nie w prawym górnym rogu). Tekst i kolejka otwierają się **w miejscu okładki**, a
    sterowanie zostaje na dole; jednym przyciskiem się je chowa.
12. **Kolejka pogrupowana po playlistach**: nagłówek „Playlist 1/2/3” nad jej utworami; przy
    nagłówku ikony losowo i powtarzaj **dla tej grupy**; przeciągnięcie nagłówka w lewo usuwa
    całą grupę naraz (czerwone „Remove”).
13. **Menu utworu**: rzadsze opcje (Pobierz utwór, Wyłącznik czasowy, Ukryj utwór) w osobnym,
    mniejszym bloku nad głównymi; główne (Dodaj do playlisty ›, Zapisz w polubionych, Dodaj do
    kolejki, Radio utworu, Przejdź do wykonawcy ›, Pokaż autorów, Udostępnij ›) bliżej kciuka;
    spójne ikony (Spotify miało mylące, np. „autorzy utworu” wyglądało jak „usuń”); dodane
    „Pobierz utwór” (Spotify pobiera tylko całe playlisty). Podmenu (›) zamiast kolejnych arkuszy.
14. **Biblioteka**: na górze „Search library” i „+”, pod spodem „Grupuj / Ostatnie / widok
    siatki”, a lista to **kategorie** (Playlisty, Playlisty od Spotify, Albumy, Foldery,
    Wykonawcy) — każda otwiera swoją listę. Pomysł: filtr Biblioteki po wykonawcy / gatunku
    zapisany jako **dynamiczna playlista**.
15. **Tworzenie playlisty z utworu**: „Nowa playlista” pyta o nazwę (Spotify nazywało ją od
    utworu); arkusz „dodaj do playlisty” ma wyszukiwarkę „playlista/folder”, foldery z ›.
16. **DJ** jako część odtwarzacza (przy kontrolkach): pomiń, 👍/👎, wyłącz.
17. **Jasny motyw** (Home w wersji jasnej w Figmie).
18. Własny zestaw ikon (spójny styl) i darmowa czcionka (Satoshi) zamiast płatnej.

## Co z tego jest już w Leina Radio (ta zmiana)

- **Kształty okładek** w Bibliotece (`CollectionFrame` w `collection_cover.dart`): playlista —
  stos krawędzi, album ze Spotify — jedna krawędź, nastrój — zaokrąglone rogi i księżyc w rogu.
- **Pełny odtwarzacz**: obok tytułu YouTube, ♡ „Polub” (atrapa) i ⊕ „Dodaj do playlisty” (działa
  — ten sam arkusz co w menu utworu; wcześniej było atrapą „Dodaj (+)”). Dolny rząd: Urządzenia,
  filtr nastrojów, [Nastrój], Udostępnij, Tekst (atrapa), Kolejka, ⋮ (menu przeniesione z
  nagłówka). Wyłącznik czasowy przeszedł do menu utworu, a na jego miejscu jest „Powtarzaj”
  (atrapa).
- **Mini odtwarzacz**: ⊕ „Dodaj do playlisty” przed odtwórz/pauza; przytrzymanie → szybkie akcje
  nad nim: Ukryj, Urządzenia, Polub (atrapy), Więcej (menu utworu, jak wcześniej przytrzymanie).
- **Menu utworu**: blok rzadszych opcji u góry — Pobierz utwór, Wyłącznik czasowy, Ukryj utwór
  (atrapy; `quickEntries` w `showMenuSheet`).
- **Kolejka**: nagłówek grupy z playlisty ma Losowo i Powtarzaj dla grupy (atrapy) oraz „Usuń tę
  grupę z kolejki” (działa).

## Wprowadzone w drugiej turze (użytkownik: „wprowadź wszystko”)

- **Dolny pasek**: Home, Odkrywaj, Wyszukaj, Biblioteka, **Ja**. Awatar i szuflada profilu
  zniknęły; „Utwórz” to „+” w Bibliotece.
- **Ja** (`profile_screen.dart`): karta profilu (konto MusicDatabase), Znajomi (atrapa), karta
  konta, Ostatnie, Na później (linki), Statystyki, Wiadomości, Ustawienia, Co nowego.
- **Home** (`home_layout.dart`): „⋯” przy każdej sekcji (przypnij, wyżej, niżej, ukryj), ekran
  „Dostosuj stronę główną” (przełącznik rekomendacji, kolejność przeciąganiem, przypinanie,
  sekcje z Biblioteki). Prawdziwe rzędy: Ostatnio odtwarzane, Twoje playlisty, Twoje nastroje,
  Na później i dodane playlisty/nastroje; przykładowe rzędy to „rekomendacje”.
- **Odkrywaj** (`discover_screen.dart`): karty po jednej, przesuwane w górę; kategorie
  Wszystko + nastroje; obok: wykonawca (atrapa), Na później, playlista, udostępnij, więcej.
  Odtwarza dopiero po ▶ (bez autoodtwarzania fragmentów).
- **Na później dla utworów** (`saved_songs.dart`): zakładka w Odkrywaj, „Zapisz na później” w
  menu utworu, lista w Bibliotece i rząd na Home. Osobno od linków „Na później” w Ja.
- **Tekst i kolejka w miejscu okładki**: sterowanie zostaje na dole; tekst to na razie atrapa
  (MusicDatabase nie ma tekstów), kolejka — następne utwory i „Cała kolejka”.
- **Biblioteka jako kategorie**: Playlisty, Albumy, Nastroje, Foldery, Wykonawcy (atrapa), Na
  później, Dynamiczne playlisty — każda to osobna lista; pod nimi wszystko jak dawniej.
  Wyszukiwanie w Bibliotece działa. Chipy filtrów (i zapamiętany filtr) zniknęły.
- **Dynamiczne playlisty** (`smart_playlists.dart`): zapisany filtr pole + wartość (np.
  „Wykonawca: Kino”), utwory wyszukiwane przy każdym otwarciu.

## Wprowadzone w trzeciej turze

- **Kolejka**: losowo i „powtórz” dla grupy z playlisty działają; nagłówek grupy przeciągnięty
  w lewo usuwa ją (z „Cofnij”).
- **Wyszukiwarka w nastroju** (playlista już ją miała).
- **„Przeglądaj” pogrupowane**: Nastroje, Dekady, Języki, Kraje wykonawców — z music.db.
  Gatunków MusicDatabase nie ma.
- **Podmenu w menu utworu**: „Dodaj do playlisty ›” i „Przejdź do wykonawców ›” rozwijają się w
  tym samym arkuszu; „Przejdź do albumu” i strona wykonawcy to listy utworów (też z Odkrywaj
  i z Biblioteka › Wykonawcy, która jest teraz prawdziwa).
- **Fragmenty w Odkrywaj**: ▶ / „Fragment” zaczyna od ok. 1/3 utworu, „Od początku” od zera.
- **Teksty piosenek** z LRCLIB (darmowe, bez klucza), zsynchronizowane linie z podświetleniem,
  dotknięcie linii przewija utwór; tylko w pamięci (nic nie zapisuje na telefonie).
- **Jasny motyw „Redesign”** (Wygląd › Motyw jasny).

## Nadal nie zrobione (wymaga decyzji albo danych)

- Znajomi i ich aktywność — potrzebny nowy sposób rozmowy z MusicDatabase (decyzja użytkownika,
  ADR); zostaje atrapa w Ja.
- Łączny czas playlisty pod tytułem — music.db nie ma długości utworów.
- Gatunki w „Przeglądaj” — MusicDatabase ich nie ma.
