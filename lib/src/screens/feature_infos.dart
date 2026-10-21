import 'package:flutter/material.dart';

import '../data/youtube_account.dart';
import '../widgets/feature_info.dart';
import 'account_screen.dart';
import 'privacy_screen.dart';

// The long-press explanations (sharing checklist 5.2), reviewed by the owner before going in.
// Keep them true to the code: a change to how one of these works updates its text here.

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

final _privacy = FeatureInfoAction(
  Icons.privacy_tip_outlined,
  'Prywatność i połączenia',
  (context) => _push(context, const PrivacyScreen()),
);

final _account = FeatureInfoAction(
  Icons.account_circle_outlined,
  'Konto',
  (context) => _push(context, const AccountScreen()),
);

final _signOutGoogle = FeatureInfoAction(
  Icons.logout,
  'Wyloguj z Google',
  (context) => YouTubeAccountScope.maybeOf(context)?.signOut(),
);

/// Every element with a long-press explanation, by what it explains.
abstract final class FeatureInfos {
  static final googleAccount = FeatureInfo(
    title: 'Konto Google',
    what: 'Konto Google, na którym aplikacja tworzy playlisty na YouTube.',
    why: 'Użytkownik jest zalogowany, gdy użył opcji „Utwórz na YouTube” w udostępnianiu playlisty. Logowanie zostaje, żeby kolejne playlisty nie wymagały wybierania konta od nowa.',
    how: 'Logowanie odbywa się w oknie Google (Usługi Google Play), z uprawnieniem tylko do zarządzania Twoim YouTube. Aplikacja zapamiętuje wyłącznie adres e-mail — hasła i tokenu nie widzi. Połączenie jest używane tylko przy tworzeniu playlisty: playlista powstaje jako niepubliczna kopia.',
    libraries: 'google_sign_in (Usługi Google Play), YouTube Data API v3',
    connects: 'accounts.google.com i googleapis.com — tylko w chwili tworzenia playlisty.',
    actions: [_signOutGoogle, _privacy],
  );

  static final listeningStats = FeatureInfo(
    title: 'Statystyki słuchania',
    what: 'Podsumowanie tego, czego słuchasz.',
    why: 'Najczęściej słuchane utwory, wykonawcy i albumy, udziały w czasie słuchania, najciekawsze momenty tygodnia i karty podsumowania roku i pór roku.',
    how: 'Każde odtworzenie jest zapisywane z tym, jak długo naprawdę go słuchałeś. Wszystko jest liczone na telefonie, w lokalnej bazie.',
    libraries: 'sqflite (lokalna baza), własne wykresy',
    connects: 'W przypadku połączenia z serwerem MusicDatabase, odtworzenia synchronizują się z kontem.',
    actions: [_account, _privacy],
  );

  static final server = FeatureInfo(
    title: 'Serwer MusicDatabase',
    what: 'Adres Twojego serwera MusicDatabase — programu, który prowadzi bazę utworów i Twoją bibliotekę muzyki.',
    why: 'Jeśli jest to skonfigurowane, to z serwera telefon pobiera bazę utworów (raz dziennie), odtwarza pliki z Twojej biblioteki (źródło „Serwer”), wysyła zgłoszenia poprawek i — po zalogowaniu — synchronizuje Bibliotekę i statystyki. Bez serwera aplikacja wciąż działa: bazę pobiera z GitHuba, a reszta zostaje na telefonie.',
    how: 'Można wpisać dwa adresy: zdalny (np. przez Tailscale) i domowy, z nazwą domowej sieci Wi-Fi — w domu telefon próbuje najpierw adresu domowego. Rozpoznanie sieci Wi-Fi wymaga zgody na lokalizację (zasada Androida). „Użyj bieżącego połączenia” sam szuka serwera w sieci. Gdy żaden serwer nie odpowiada, baza przychodzi z GitHuba.',
    libraries: 'HttpClient (Dart), network_info_plus, permission_handler',
    connects: 'Wpisane adresy serwera; GitHub, gdy serwer nie odpowiada (wyłączalne).',
    actions: [_privacy],
  );

  static final outbox = FeatureInfo(
    title: 'Zgłoszenia poprawek',
    what: 'Skrzynka z rzeczami, które telefon zgłasza do MusicDatabase.',
    why: 'Telefon zauważa brakujące lub niepoprawne informacje: martwe linki YouTube (z filmem zastępczym), Twoje poprawki pól (ołówek w „Informacjach o utworze”), filmy znalezione dla utworów bez linku i odtworzone utwory, których nie ma w bazie. Serwer je przegląda i poprawia bazę — poprawki wracają z następną aktualizacją bazy.',
    how: 'Zgłoszenia czekają na telefonie w małych plikach. Gdy serwer jest ustawiony, wysyłają się same (albo „Wyślij teraz”). Bez serwera: „Wyślij paczkę…” pakuje je w plik .zip, który wysyłasz poprzez opcje „Udostępnij” (np. komunikatorem), podpisany Twoją nazwą. Do czasu decyzji serwera, telefon pokazuje wartość z bazy, nie Twoją.',
    libraries: 'sqflite (pliki zgłoszeń), archive (paczka .zip), share_plus („Udostępnij”)',
    connects: 'Serwer MusicDatabase (PUT /inbox) — gdy jest ustawiony. Paczka: nic, idzie przez aplikację wybraną w „Udostępnij”.',
    actions: [_privacy],
  );

  static final newPipePlayback = FeatureInfo(
    title: 'NewPipeExtractor (odtwarzanie)',
    what: 'Główny sposób odtwarzania dźwięku z YouTube.',
    why: 'Pozwala słuchać utworów z YouTube w aplikacji: bez obrazu, reklam i konta, z ekranem wyłączonym i w tle.',
    how: 'NewPipeExtractor to silnik otwartej aplikacji NewPipe. Pyta YouTube o film tak jak przeglądarka, odczytuje listę strumieni (gdy YouTube je zabezpiecza, uruchamia u siebie kod odtwarzacza YouTube, żeby wyliczyć adres) i zwraca adres samego dźwięku — Opus 160 kb/s albo AAC 128 kb/s. Odtwarzacz aplikacji pobiera go wprost z serwerów wideo YouTube; odtworzone utwory trafiają do pamięci podręcznej. Tylko Android.',
    libraries: 'NewPipeExtractor (Java, GPLv3), just_audio (odtwarzacz)',
    connects: 'youtube.com i serwery wideo YouTube (googlevideo.com) — przy odtwarzaniu utworu z YouTube.',
    actions: [_privacy],
  );

  static final explodePlayback = FeatureInfo(
    title: 'youtube_explode (odtwarzanie)',
    what: 'Zapasowy sposób odtwarzania z YouTube — biblioteka napisana w Dart.',
    why: 'Na wypadek, gdyby NewPipe przestał działać albo na urządzeniach bez niego.',
    how: 'Działa podobnie do NewPipe: pyta YouTube jak przeglądarka i szuka adresu dźwięku. Obecnie YouTube odrzuca jego pobieranie (błąd 403).',
    libraries: 'youtube_explode_dart',
    connects: 'youtube.com i serwery wideo YouTube.',
    actions: [_privacy],
  );

  static final newPipeSearch = FeatureInfo(
    title: 'NewPipeExtractor (wyszukiwanie)',
    what: 'Główny sposób wyszukiwania na YouTube.',
    why: 'Wyszukiwanie utworów i playlist na YouTube oraz dopasowywanie utworów z bazy, które nie mają linku do filmu.',
    how: 'Ta sama biblioteka co odtwarzanie: wysyła zapytanie do YouTube jak przeglądarka i odczytuje wyniki (filmy, osobno playlisty). Bez konta i bez klucza. YouTube przeszukuje się tylko na wyraźne polecenie — przyciskiem wyszukiwania w internecie albo gdy stukniesz utwór, którego nie ma w żadnym źródle — nigdy przy każdej literze. Tylko Android.',
    libraries: 'NewPipeExtractor (Java, GPLv3)',
    connects: 'youtube.com — przy wyszukiwaniu.',
    actions: [_privacy],
  );

  static final explodeSearch = FeatureInfo(
    title: 'youtube_explode (wyszukiwanie)',
    what: 'Zapasowy sposób wyszukiwania na YouTube — biblioteka w Dart.',
    why: 'Gdy NewPipe zawiedzie, wyszukiwanie dalej działa (w przeciwieństwie do odtwarzania, wyszukiwanie tą biblioteką działa).',
    how: 'Wysyła zapytanie do YouTube jak przeglądarka i odczytuje wyniki. Bez konta i klucza. Używana tylko wtedy, gdy sposób wyżej na liście zawiedzie.',
    libraries: 'youtube_explode_dart',
    connects: 'youtube.com — przy wyszukiwaniu.',
    actions: [_privacy],
  );

  static final youTubeApi = FeatureInfo(
    title: 'YouTube Data API',
    note: 'W budowie — jeszcze nie sprawdzone w praktyce z prawdziwym kluczem.',
    what: 'Oficjalne wyszukiwanie YouTube od Google, z Twoim kluczem.',
    why: 'Najstabilniejszy sposób wyszukiwania — nie psuje się po zmianach na stronie YouTube. Przydaje się, gdy NewPipe i youtube_explode zawodzą.',
    how: 'Wymaga klucza YouTube Data API (darmowy, z Google Cloud Console — własny projekt z włączonym YouTube Data API v3), wpisanego niżej w „Kod YouTube API”. Klucz zostaje tylko na telefonie. Limit: 10 000 jednostek dziennie na klucz, jedno wyszukiwanie zużywa 100 — około 100 wyszukiwań dziennie. Odtwarzanie dalej idzie przez NewPipe.',
    libraries: 'YouTube Data API v3 (HTTP)',
    connects: 'www.googleapis.com — przy wyszukiwaniu, gdy klucz jest wpisany.',
    actions: [_privacy],
  );

  static final spotifyApi = FeatureInfo(
    title: 'Spotify API',
    note: 'W budowie — jeszcze nie sprawdzone w praktyce z prawdziwym kluczem.',
    what: 'Oficjalne wyszukiwanie playlist Spotify, z kluczem Twojej aplikacji Spotify.',
    why: 'Stabilniejsze wyszukiwanie playlist Spotify. Bez klucza wyszukiwanie też działa, ale nieoficjalnie i może przestać.',
    how: 'Klucz to Client ID i Client Secret aplikacji, którą zakładasz za darmo na developer.spotify.com. Telefon wymienia go na krótkotrwały token i szuka przez Web API. Bez klucza (albo gdy API zawiedzie) szuka tak jak odtwarzacz na open.spotify.com bez logowania. Klucz zostaje tylko na telefonie. Import playlist z linków nie używa API — czyta publiczną stronę playlisty (pierwsze 100 utworów).',
    libraries: 'Spotify Web API (HTTP)',
    connects: 'accounts.spotify.com i api.spotify.com z kluczem; bez klucza open.spotify.com i api-partner.spotify.com — przy wyszukiwaniu playlist Spotify.',
    actions: [_privacy],
  );

  static final accountSync = FeatureInfo(
    title: 'Synchronizacja z kontem',
    what: 'Wymiana Twoich danych między telefonem a kontem na serwerze MusicDatabase.',
    why: 'Dzięki niej dane są takie same na wszystkich Twoich telefonach i wracają po reinstalacji albo na nowym telefonie.',
    how: 'Synchronizują się: playlisty (z wybranymi okładkami), nastroje (i zmiany nastrojów globalnych, jeśli masz do tego uprawnienie), foldery Biblioteki, statystyki słuchania (każde odtworzenie), polubione utwory, utwory i linki zapisane „Na później”. Działa samo — przy starcie, przy powrocie do aplikacji i kilka sekund po zmianie — a ⟳ uruchamia ją od razu. Gdy serwer nie odpowiada, zmiany czekają na telefonie. Playlisty, nastroje i foldery utworzone przed zalogowaniem dodaje się do konta wierszami „… tylko na tym telefonie”.',
    connects: 'Serwer MusicDatabase z Ustawienia › Serwer, na koncie, na które jesteś zalogowany.',
    actions: [_privacy],
  );

  static final home = FeatureInfo(
    title: 'Home',
    what: 'Strona główna: rzędy z Twoją muzyką i propozycjami.',
    why: 'Szybki powrót do tego, czego słuchasz, i podpowiedzi, czego posłuchać dalej.',
    how: 'Rzędy z Biblioteki (Ostatnio odtwarzane, Polubione utwory, Twoje playlisty, Twoje nastroje, Na później) i rekomendacje liczone na telefonie z Twoich statystyk słuchania i bazy utworów: najczęściej słuchani wykonawcy, albumy, do których wracasz, nowe w bazie, Twoje gatunki i Zapomniane (utwory słuchane co najmniej dwa razy, ale nie od 60 dni). Kolejność i widoczność rzędów zmienisz w „Dostosuj stronę główną” (przypinanie, przenoszenie, ukrywanie); filtry na górze zawężają widok do utworów, playlist albo nastrojów.',
    actions: [_privacy],
  );

  static final discover = FeatureInfo(
    title: 'Odkrywaj',
    what: 'Przeglądanie muzyki po jednym utworze naraz.',
    why: 'Do odkrywania utworów z bazy, których możesz nie znać.',
    how: 'Na górze wybierasz kategorię: cała baza MusicDatabase albo jeden z nastrojów. Przesunięcie w górę pokazuje następny utwór. Nic nie gra, dopóki sam nie zaczniesz: „Fragment” odtwarza utwór od mniej więcej jednej trzeciej, a „Od początku” — cały. Przy każdym utworze: zapisz na później, dodaj do playlisty, udostępnij. Całe albumy (jedno nagranie) i ukryte utwory są pomijane.',
    actions: [_privacy],
  );

  static final songRadio = FeatureInfo(
    title: 'Radio utworu',
    what: 'Lista utworów podobnych do wybranego, grana jak radio.',
    why: 'Gdy chcesz posłuchać więcej w podobnym klimacie, bez układania playlisty.',
    how: 'Telefon wybiera z bazy do 50 utworów najbardziej podobnych do wybranego — wspólny wykonawca, gatunki (także pokrewne, np. „indie pop” i „pop”), nastroje, język, kraj i dekada — z odrobiną przypadku. Jeden wykonawca zajmuje najwyżej 8 miejsc, żeby radio nie było jego dyskografią. Całe albumy i ukryte utwory są pomijane. MusicDatabase nie ma własnego radia, więc to przybliżenie liczone na telefonie; dla tego samego utworu radio jest zawsze takie samo.',
    actions: [_privacy],
  );
}
