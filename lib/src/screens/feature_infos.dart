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
    why: 'Jesteś zalogowany, bo użyłeś „Utwórz na YouTube” w udostępnianiu playlisty. Logowanie zostaje, żeby kolejne playlisty nie wymagały wybierania konta od nowa.',
    how: 'Logowanie odbywa się w oknie Google (Usługi Google Play), z uprawnieniem tylko do zarządzania Twoim YouTube. Aplikacja zapamiętuje wyłącznie adres e-mail — hasła i tokenu nie widzi. Połączenie jest używane tylko przy tworzeniu playlisty: playlista powstaje jako niepubliczna kopia. „Wyloguj” — następna playlista zapyta o konto.',
    libraries: 'google_sign_in (Usługi Google Play), YouTube Data API v3',
    connects: 'accounts.google.com i googleapis.com — tylko w chwili tworzenia playlisty.',
    actions: [_signOutGoogle, _privacy],
  );

  static final listeningStats = FeatureInfo(
    title: 'Statystyki słuchania',
    what: 'Podsumowanie tego, czego słuchasz — jak w Spotify.',
    why: 'Najczęściej słuchane utwory, wykonawcy i albumy, udziały w czasie słuchania, najciekawsze momenty tygodnia i karty podsumowania roku i pór roku (do udostępnienia jako obrazek).',
    how: 'Każde odtworzenie jest zapisywane z tym, jak długo naprawdę go słuchałeś. Wszystko jest liczone na telefonie, w lokalnej bazie. Statystyki liczą się od wersji, która to wprowadziła — starszej historii nie ma.',
    libraries: 'sqflite (lokalna baza), własne wykresy',
    connects: 'Nic — chyba że jesteś zalogowany na serwer MusicDatabase: wtedy odtworzenia synchronizują się z kontem, żeby sumowały się między telefonami i przetrwały zmianę telefonu.',
    actions: [_account, _privacy],
  );

  static final listeningStatsSync = FeatureInfo(
    title: 'Synchronizacja statystyk',
    what: 'Kiedy statystyki słuchania ostatnio zsynchronizowały się z kontem MusicDatabase.',
    why: 'Dzięki synchronizacji odtworzenia z kilku telefonów sumują się, a statystyki wracają po reinstalacji albo na nowym telefonie.',
    how: 'Telefon wysyła nowe odtworzenia (co, kiedy, jak długo, skąd, z jakiej playlisty) i pobiera te z innych urządzeń. Odtworzenie może się tylko wydłużyć, więc nie ma konfliktów. Działa przy starcie, przy powrocie do aplikacji i po stuknięciu ⟳.',
    libraries: null,
    connects:
        'Serwer MusicDatabase (/users/<nazwa>/listens) — tylko po zalogowaniu.',
    actions: [_privacy],
  );

  static final server = FeatureInfo(
    title: 'Serwer MusicDatabase',
    what: 'Adres Twojego serwera MusicDatabase — programu, który prowadzi bazę utworów i Twoją bibliotekę muzyki.',
    why: 'Z serwera telefon pobiera bazę utworów (raz dziennie), odtwarza pliki z Twojej biblioteki (źródło „Serwer”), wysyła zgłoszenia poprawek i — po zalogowaniu — synchronizuje Bibliotekę i statystyki. Bez serwera aplikacja działa dalej: bazę pobiera z GitHuba, a reszta zostaje na telefonie.',
    how: 'Można wpisać dwa adresy: zdalny (np. przez Tailscale) i domowy, z nazwą domowej sieci Wi-Fi — w domu telefon próbuje najpierw adresu domowego. Rozpoznanie sieci Wi-Fi wymaga zgody na lokalizację (zasada Androida). „Użyj bieżącego połączenia” sam szuka serwera w sieci. Gdy żaden serwer nie odpowiada, baza przychodzi z GitHuba.',
    libraries: 'HttpClient (Dart), network_info_plus, permission_handler',
    connects: 'Wpisane adresy serwera; GitHub, gdy serwer nie odpowiada (wyłączalne).',
    actions: [_privacy],
  );

  static final outbox = FeatureInfo(
    title: 'Zgłoszenia poprawek',
    what: 'Skrzynka z rzeczami, które telefon zgłasza do MusicDatabase.',
    why: 'Telefon zauważa, czego brakuje albo co jest źle w bazie: martwe linki YouTube (z filmem zastępczym), Twoje poprawki pól (ołówek w Informacjach o utworze), filmy znalezione dla utworów bez linku i utwory grane, których nie ma w bazie. Właściciel serwera je przegląda i poprawia bazę — poprawki wracają z następną bazą.',
    how: 'Zgłoszenia czekają na telefonie w małych plikach. Gdy serwer jest ustawiony, wysyłają się same (albo „Wyślij teraz”). Bez serwera: „Wyślij paczkę…” pakuje je w plik .zip, który wysyłasz komuś przez „Udostępnij” (np. komunikatorem), podpisany Twoją nazwą. Do czasu decyzji właściciela telefon pokazuje wartość z bazy, nie Twoją.',
    libraries: 'sqflite (pliki zgłoszeń), archive (paczka .zip), share_plus („Udostępnij”)',
    connects: 'Serwer MusicDatabase (PUT /inbox) — gdy jest ustawiony. Paczka: nic, idzie przez aplikację wybraną w „Udostępnij”.',
    actions: [_privacy],
  );

  static final newPipePlayback = FeatureInfo(
    title: 'NewPipeExtractor (odtwarzanie)',
    what: 'Główny sposób odtwarzania dźwięku z YouTube.',
    why: 'Pozwala słuchać utworów z YouTube w aplikacji: bez obrazu, reklam i konta, z ekranem wyłączonym i w tle.',
    how: 'NewPipeExtractor to silnik otwartej aplikacji NewPipe. Pyta YouTube o film tak jak przeglądarka, odczytuje listę strumieni (gdy YouTube je zabezpiecza, uruchamia u siebie kod odtwarzacza YouTube, żeby wyliczyć adres) i zwraca adres samego dźwięku — Opus 160 kb/s albo AAC 128 kb/s. Odtwarzacz aplikacji pobiera go wprost z serwerów wideo YouTube; odtworzone utwory trafiają do pamięci podręcznej. Adres działa tylko z IP telefonu. Zmiany po stronie YouTube mogą to zepsuć — naprawia to nowa wersja aplikacji. Tylko Android.',
    libraries: 'NewPipeExtractor (Java, GPLv3), just_audio (odtwarzacz)',
    connects: 'youtube.com i serwery wideo YouTube (googlevideo.com) — przy odtwarzaniu utworu z YouTube.',
    actions: [_privacy],
  );

  static final explodePlayback = FeatureInfo(
    title: 'youtube_explode (odtwarzanie)',
    what: 'Zapasowy sposób odtwarzania z YouTube — biblioteka napisana w Dart.',
    why: 'Na wypadek, gdyby NewPipe przestał działać albo na urządzeniach bez niego.',
    how: 'Działa podobnie do NewPipe: pyta YouTube jak przeglądarka i szuka adresu dźwięku. Obecnie YouTube odrzuca jego pobieranie (błąd 403), bo nie potrafi rozwiązać nowszych zabezpieczeń YouTube — dlatego jest dalej na liście i zwykle nie gra. Zostaje, bo może wrócić do działania z nową wersją biblioteki.',
    libraries: 'youtube_explode_dart',
    connects: 'youtube.com i serwery wideo YouTube — tylko gdy dojdzie do niego kolejka sposobów.',
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
}
