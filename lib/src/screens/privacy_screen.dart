import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/app_updates.dart';
import '../data/database_sync.dart';
import '../data/source_settings.dart';
import '../data/youtube_account.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'cache_settings_screen.dart';
import 'cover_sources_screen.dart';
import 'data_saver_screen.dart';
import 'database_source_screen.dart';
import 'playback_order_screen.dart';
import 'spotify_source_screen.dart';
import 'youtube_source_screen.dart';

/// "Ustawienia › Prywatność i połączenia": who the app talks to, why, when and what they get,
/// each with a way to the switch that stops it — or a note that it only happens when the user
/// does it. Mirrors the connections the code makes (no analytics, ads or crash reports).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.maybeOf(context);
    final account = AccountScope.maybeOf(context);
    final settings = SourceSettingsScope.maybeOf(context);
    final updates = AppUpdatesScope.maybeOf(context);
    final google = YouTubeAccountScope.maybeOf(context);
    final userName = account?.userName;

    Widget text(String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        value,
        style: TextStyle(
          fontSize: AppFontSize.body,
          color: strong ? palette.textPrimary : palette.textSecondary,
        ),
      ),
    );
    // The accent while the service is reached, the theme's error red while it isn't.
    Widget status(bool connects, String value) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        'Teraz: $value',
        style: TextStyle(
          fontSize: AppFontSize.small,
          color: connects
              ? palette.accent
              : Theme.of(context).colorScheme.error,
        ),
      ),
    );
    Widget statusOf(List<String> what) => what.isEmpty
        ? status(false, 'nie łączy się')
        : status(true, 'łączy się z internetem (${what.join(', ')})');
    Widget onlyWhenUsed([String? what]) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 18,
            color: palette.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              what ?? 'Tylko gdy sam tego użyjesz — nie ma czego wyłączać.',
              style: TextStyle(
                fontSize: AppFontSize.small,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
    Widget goTo(String label, Widget Function() screen) => ListTile(
      dense: true,
      leading: Icon(Icons.tune, color: palette.accent),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen())),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Prywatność i połączenia'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          text(
            'Aplikacja nie ma reklam, analityki ani raportów o awariach. Łączy się z siecią '
            'tylko wtedy, gdy wymaga tego funkcja, której używasz albo którą masz włączoną. '
            'Każdy serwis, z którym się łączy, widzi adres IP telefonu — jak przy każdym '
            'połączeniu w internecie.',
            strong: true,
          ),
          text(
            'Biblioteka (playlisty, nastroje, polubione, „Na później”), statystyki słuchania, '
            'historia i ustawienia zostają tylko na telefonie — dopóki nie zalogujesz się na '
            'serwer MusicDatabase.',
          ),

          const SectionTitle('Serwer MusicDatabase'),
          text(
            'Baza utworów, Twoje pliki muzyczne (źródło „Serwer”) i zgłoszenia poprawek. Po '
            'zalogowaniu także synchronizacja konta: playlisty, nastroje, foldery, okładki, '
            'polubione, „Na później”, linki na później (z imieniem nadawcy) i każde '
            'odtworzenie — co, kiedy, jak długo i skąd. Właściciel serwera widzi wszystko, co '
            'na niego trafia.',
          ),
          if (sync != null)
            sync.hasServer
                ? status(
                    true,
                    'łączy się z serwerem, '
                    '${userName != null ? 'zalogowano jako $userName' : 'bez logowania'}',
                  )
                : status(
                    false,
                    'nie łączy się — żaden serwer nie jest ustawiony',
                  ),
          goTo('Serwer: adresy', () => const DatabaseSourceScreen()),
          goTo('Konto: logowanie i wylogowanie', () => const AccountScreen()),

          const SectionTitle('GitHub'),
          text(
            'Publiczna kopia bazy utworów (gdy żaden serwer nie odpowiada) i sprawdzanie, czy '
            'jest nowa wersja aplikacji. Raz dziennie przy otwarciu. Nie wysyła nic o Tobie — '
            'tylko samo zapytanie.',
          ),
          if (sync != null)
            statusOf([
              if (sync.gitHubOn) 'baza',
              if (updates != null && updates.configured && updates.autoCheck)
                'aktualizacje',
            ]),
          goTo(
            'Serwer › Pobieraj z GitHuba',
            () => const DatabaseSourceScreen(),
          ),
          if (updates != null && updates.configured)
            goTo(
              'Informacje i pomoc › Sprawdzaj aktualizacje',
              () => const AboutScreen(),
            ),

          const SectionTitle('YouTube'),
          text(
            'Odtwarzanie dźwięku z filmów, wyszukiwanie, dopasowywanie utworów do filmów i '
            'import playlist. Aplikacja łączy się z YouTube jak anonimowa przeglądarka (biblioteka '
            'NewPipe): bez konta i bez klucza. YouTube dostaje identyfikatory filmów i to, '
            'czego szukasz (tytuł i wykonawcę). Odtworzone utwory zostają w pamięci '
            'podręcznej; kolejne z kolejki mogą być pobierane z wyprzedzeniem.',
          ),
          if (settings != null)
            statusOf([
              if (settings.enabledSources.contains(PlaybackSource.youtube))
                'odtwarzanie',
              if (settings.youTubeSearchEnabled) 'wyszukiwanie',
            ]),
          goTo(
            'Kolejność odtwarzania: źródła, w tym YouTube',
            () => const PlaybackOrderScreen(),
          ),
          goTo(
            'YouTube: wyszukiwanie i klucz API',
            () => const YouTubeSourceScreen(),
          ),
          goTo(
            'Pamięć podręczna: pobieranie z wyprzedzeniem',
            () => const CacheSettingsScreen(),
          ),

          const SectionTitle('Konto Google'),
          text(
            '„Utwórz na YouTube” tworzy playlistę na Twoim koncie YouTube: logowanie w oknie '
            'Google, potem nazwa playlisty i jej filmy idą do YouTube Data API. Aplikacja '
            'zapamiętuje tylko adres e-mail konta.',
          ),
          if (google?.email case final email?) ...[
            status(
              true,
              'łączy się z internetem przy „Utwórz na YouTube”, zalogowano jako $email',
            ),
            goTo('Konto › Wyloguj z Google', () => const AccountScreen()),
          ] else if (google != null && !google.supported)
            status(
              false,
              'nie łączy się — ta wersja aplikacji nie ma tej funkcji',
            )
          else ...[
            status(false, 'nie łączy się — nie jesteś zalogowany'),
            onlyWhenUsed('Tylko gdy sam stukniesz „Utwórz na YouTube”.'),
          ],

          const SectionTitle('Spotify'),
          text(
            'Import playlist, albumów i utworów z linków Spotify oraz wyszukiwanie playlist '
            'Spotify. Spotify dostaje identyfikator playlisty / albumu / utworu albo to, czego '
            'szukasz. Bez konta (z kluczem API tylko, jeśli go wpiszesz).',
          ),
          if (settings != null)
            statusOf([
              if (settings.spotifyPlaylistSearch) 'wyszukiwanie playlist',
            ]),
          goTo(
            'Spotify: wyszukiwanie playlist i klucz API',
            () => const SpotifySourceScreen(),
          ),
          onlyWhenUsed(
            'Import z linku — tylko gdy sam otworzysz link Spotify.',
          ),

          const SectionTitle('Okładki: iTunes, Deezer, miniatury YouTube'),
          text(
            'Okładki albumów, których nie ma w pliku na telefonie. Serwisy dostają wykonawcę '
            'i album (albo tytuł) lub identyfikator filmu; znaleziona okładka zostaje w pamięci '
            'podręcznej.',
          ),
          if (settings != null)
            statusOf([
              for (final source in settings.activeCoverSources)
                if (source == CoverSource.itunes ||
                    source == CoverSource.deezer ||
                    source == CoverSource.youtube)
                  source.label,
              if (settings.coverWifiOnly &&
                  settings.activeCoverSources.any(
                    (s) => s != CoverSource.file && s != CoverSource.server,
                  ))
                'tylko przez Wi-Fi',
            ]),
          goTo(
            'Źródła okładek (każde osobno)',
            () => const CoverSourcesScreen(),
          ),
          goTo(
            'Oszczędzanie danych › Okładki tylko przez Wi-Fi',
            () => const DataSaverScreen(),
          ),

          const SectionTitle('LRCLIB: teksty piosenek'),
          text(
            'Tekst utworu na karcie pod odtwarzaczem, gdy otwarty jest pełny odtwarzacz. LRCLIB '
            '(projekt społecznościowy) dostaje tytuł, wykonawcę, album i długość utworu. Teksty '
            'nie są zapisywane na telefonie.',
          ),
          if (settings != null) statusOf([if (settings.lyrics) 'LRCLIB']),
          goTo(
            'Oszczędzanie danych › Pobieraj teksty piosenek',
            () => const DataSaverScreen(),
          ),

          const SectionTitle('Przeglądarka i „Udostępnij”'),
          text(
            'Linki w Informacjach o utworze (MusicBrainz, Apple Music, Deezer, Spotify), kod '
            'źródłowy i pobranie nowej wersji otwierają się w przeglądarce. Paczka zgłoszeń, '
            'linki i podsumowania trafiają do aplikacji, którą wybierzesz w „Udostępnij”.',
          ),
          status(false, 'nie łączy się sama'),
          onlyWhenUsed(),

          const SectionTitle('Kto widzi Twoje dane'),
          text(
            '• Właściciel serwera MusicDatabase, z którym się łączysz — zgłoszenia, a po '
            'zalogowaniu Twoją Bibliotekę i historię słuchania.',
          ),
          text(
            '• Osoba, której wyślesz paczkę zgłoszeń — zgłoszenia podpisane nazwą, którą '
            'wpisałeś.',
          ),
          text(
            '• Nikt inny. Imiona osób, które przysłały linki „Na później”, zostają na telefonie '
            '(po zalogowaniu także na serwerze) — te osoby nic nie dostają.',
          ),
        ],
      ),
    );
  }
}
