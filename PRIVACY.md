# Prywatność — Leina Radio

Stan na 21 października 2026. To samo, krócej, jest w aplikacji:
**Ustawienia › Prywatność i połączenia** — tam przy każdej pozycji widać, czy aplikacja teraz
się z nią łączy, i jest przejście do przełącznika, który to wyłącza.

## W skrócie

- **Bez reklam, analityki i raportów o awariach.** Aplikacja nie zawiera żadnych bibliotek, które
  wysyłałyby dane same z siebie (np. Firebase, Crashlytics).
- **Twoje dane zostają na telefonie**: Biblioteka (playlisty, nastroje, foldery, polubione,
  „Na później”), statystyki słuchania, historia i ustawienia — dopóki sam nie zalogujesz się
  na serwer MusicDatabase.
- **Aplikacja łączy się z siecią tylko wtedy, gdy wymaga tego funkcja**, której używasz albo
  którą masz włączoną. Prawie każde automatyczne połączenie da się wyłączyć.
- **Każdy serwis, z którym aplikacja się łączy, widzi adres IP telefonu** — jak przy każdym
  połączeniu w internecie. Nie dostaje nic, co by Cię wskazywało, chyba że napisano niżej inaczej.

## Z czym aplikacja się łączy i dlaczego

| Kto | Po co | Kiedy | Co dostaje | Jak wyłączyć |
|---|---|---|---|---|
| **Serwer MusicDatabase** (jeśli go ustawisz) | baza utworów, pliki muzyczne z biblioteki serwera, zgłoszenia poprawek, synchronizacja konta | raz dziennie i przy zmianach | zgłoszenia poprawek; **tylko po zalogowaniu**: playlisty, nastroje, foldery, okładki, polubione, „Na później”, linki na później (z imieniem osoby, która je przysłała) i każde odtworzenie (co, kiedy, jak długo, skąd) | nie ustawiać serwera albo się nie logować (Ustawienia › Serwer, › Konto) |
| **GitHub** | publiczna kopia bazy utworów (gdy serwer nie odpowiada), sprawdzanie nowej wersji aplikacji | raz dziennie przy otwarciu | nic poza samym zapytaniem | Ustawienia › Serwer › „Pobieraj z GitHuba”; Informacje i pomoc › „Sprawdzaj aktualizacje automatycznie” |
| **YouTube (Google)** | wyszukiwanie filmów, dopasowywanie utworów do filmów, import playlist i odtwarzanie | gdy szukasz, importujesz albo grasz utwór z YouTube | identyfikatory filmów i playlist, wyszukiwany tekst (tytuł, wykonawca) — bez konta i logowania | źródła odtwarzania (Ustawienia › Odtwarzanie), wyszukiwanie (Ustawienia › YouTube) |
| **YouTube Data API (Google)** | oficjalne wyszukiwanie | tylko jeśli wpiszesz własny klucz API | wyszukiwany tekst i Twój klucz | nie wpisywać klucza |
| **Konto Google** | „Utwórz na YouTube” — playlista na Twoim koncie YouTube | tylko gdy sam tego użyjesz | nazwa playlisty i jej filmy; Google wie, które konto się zalogowało. Aplikacja zapamiętuje tylko adres e-mail | Ustawienia › Konto › „Wyloguj” |
| **Spotify** | import playlist, albumów i utworów z linków; wyszukiwanie playlist Spotify | gdy otworzysz link Spotify albo szukasz playlist | identyfikator playlisty / albumu / utworu albo wyszukiwany tekst (i Twój klucz API, jeśli go wpiszesz) | Ustawienia › Spotify |
| **iTunes (Apple), Deezer, miniatury YouTube** | okładki albumów | przy utworach bez okładki w pliku (wynik zostaje w pamięci podręcznej) | wykonawca i album (albo tytuł) lub identyfikator filmu | Ustawienia › Okładki albumów (każde źródło osobno); Oszczędzanie danych › „tylko przez Wi-Fi” |
| **LRCLIB** (projekt społecznościowy) | teksty piosenek | gdy otwarty jest pełny odtwarzacz | tytuł, wykonawca, album i długość utworu | Oszczędzanie danych › „Pobieraj teksty piosenek” |
| **Przeglądarka i „Udostępnij”** | linki (MusicBrainz, Apple Music, Deezer, Spotify, GitHub), paczka zgłoszeń, udostępniane linki i podsumowania | tylko gdy sam stukniesz | to, co wybierzesz | — |

## Kto widzi Twoje dane

- **Właściciel serwera MusicDatabase**, z którym się łączysz: Twoje zgłoszenia poprawek, a jeśli
  się zalogujesz — także Twoją Bibliotekę i historię słuchania. Jeśli nie ustawisz serwera, nikt.
- **Osoba, której wyślesz paczkę zgłoszeń** („Wyślij paczkę…”): zgłoszenia podpisane nazwą, którą
  wpisałeś.
- **Nikt inny.** Imiona osób, które przysłały Ci linki „Na później”, zostają na telefonie (po
  zalogowaniu także na serwerze) — te osoby nic nie dostają.

## Gdzie są dane i jak je usunąć

- Na telefonie: w danych aplikacji. Ustawienia Androida › Aplikacje › Leina Radio › Pamięć ›
  „Wyczyść dane” usuwa wszystko (albo odinstalowanie aplikacji). Samą pamięć podręczną (utwory,
  okładki) czyści się w aplikacji: Oszczędzanie danych › Pamięć podręczna.
- Na serwerze MusicDatabase: u jego właściciela — usunięcie danych konta trzeba z nim ustalić.

## Klucze i hasła

- Hasło do konta MusicDatabase nie jest zapisywane na telefonie — serwer daje w zamian token.
- Klucze API YouTube i Spotify, jeśli je wpiszesz, zostają tylko na telefonie.
- Logowanie do Google obsługują Usługi Google Play; aplikacja nie widzi hasła ani tokenu.

Pytania i zmiany: zgłoszenie w repozytorium tej aplikacji na GitHubie.
