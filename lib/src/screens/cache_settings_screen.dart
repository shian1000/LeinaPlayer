import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../playback/downloads.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cache_contents_screen.dart';

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// Everything the phone keeps to play and show without the internet: YouTube audio, the queue's
/// next songs (downloaded into that audio cache), songs kept with "Pobierz" and album covers, in
/// bytes.
int cacheBytesOf(BuildContext context) =>
    (YouTubeLibraryScope.maybeOf(context)?.cachedBytes ?? 0) +
    (DownloadsScope.maybeOf(context)?.bytes ?? 0) +
    (AlbumCoversScope.maybeOf(context)?.cachedBytes ?? 0);

/// "Ustawienia › Oszczędzanie danych i tryb offline › Pamięć podręczna": every cache setting in
/// one place — YouTube songs, the queue's songs downloaded ahead, what the phone found out on
/// YouTube itself, album covers.
class CacheSettingsScreen extends StatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  State<CacheSettingsScreen> createState() => _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends State<CacheSettingsScreen> {
  static const _coverLimits = [25, 50, 100, 200, 500];

  Future<bool> _confirm(
    String title,
    String text, {
    String action = 'Wyczyść',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  void _done(String message) {
    if (!mounted) return;
    // Cover sizes aren't a notifier the screen listens to.
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editSongLimit(SourceSettings settings) async {
    final library = YouTubeLibraryScope.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Liczba utworów w pamięci podręcznej',
        hint: '${SourceSettings.defaultCacheLimit}',
        initial: '${settings.cacheLimit}',
        number: true,
      ),
    );
    final limit = int.tryParse(result?.trim() ?? '');
    if (limit == null) return;
    await settings.setCacheLimit(limit);
    await library.trim(settings.cacheKeep);
  }

  Future<void> _clearSongs() async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      'Wyczyścić utwory z YouTube?',
      'Zapisane na telefonie utwory z YouTube zostaną usunięte i przy następnym '
          'odtworzeniu pobrane ponownie.',
    )) {
      return;
    }
    await library.clearCache();
    _done('Wyczyszczono utwory z YouTube.');
  }

  Future<void> _forgetMatches() async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      'Zapomnieć filmy dopasowane przez telefon?',
      'Utwory, do których telefon sam znalazł film na YouTube, zostaną przy następnym '
          'odtworzeniu wyszukane od nowa. Linki z bazy danych zostają.',
      action: 'Zapomnij',
    )) {
      return;
    }
    await library.forgetPhoneMatches();
    _done('Zapomniano filmy dopasowane przez telefon.');
  }

  Future<void> _forgetNotFound() async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      'Zapomnieć „nie znaleziono na YouTube”?',
      'Telefon poszuka tych utworów na YouTube ponownie, także w kolejce. Oznaczenia N/A z '
          'bazy danych zostają.',
      action: 'Zapomnij',
    )) {
      return;
    }
    await library.forgetNotFound();
    _done('Zapomniano utwory nieznalezione na YouTube.');
  }

  Future<void> _pickPrefetch(SourceSettings settings) async {
    final count = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Ile następnych utworów z kolejki zapisywać?'),
        children: [
          for (var n = 1; n <= SourceSettings.maxQueuePrefetch; n++)
            ListTile(
              title: Text(_nextSongs(n)),
              trailing: n == settings.queuePrefetch
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(n),
            ),
        ],
      ),
    );
    if (count != null) await settings.setQueuePrefetch(count);
  }

  Future<void> _pickCoverLimit(SourceSettings settings) async {
    final mb = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Rozmiar pamięci podręcznej okładek'),
        children: [
          for (final mb in _coverLimits)
            ListTile(
              title: Text('$mb MB'),
              trailing: mb == settings.coverCacheLimitMb
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(mb),
            ),
        ],
      ),
    );
    if (mb != null) await settings.setCoverCacheLimitMb(mb);
    if (mounted) setState(() {});
  }

  Future<void> _clearCovers(AlbumCovers covers) async {
    if (!await _confirm(
      'Wyczyścić okładki?',
      'Pobrane okładki zostaną usunięte i pobrane ponownie, gdy będą potrzebne.',
    )) {
      return;
    }
    await covers.clear();
    _done('Wyczyszczono okładki.');
  }

  Future<void> _clearAll(AlbumCovers? covers) async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      'Wyczyścić całą pamięć podręczną?',
      'Zapisane utwory z YouTube i pobrane okładki zostaną usunięte. Pobrana baza danych, '
          'utwory pobrane przyciskiem „Pobierz” i muzyka z telefonu zostają.',
    )) {
      return;
    }
    await library.clearCache();
    await covers?.clear();
    _done('Wyczyszczono pamięć podręczną.');
  }

  Future<void> _removeDownloads(Downloads downloads) async {
    if (!await _confirm(
      'Usunąć wszystkie pobrane?',
      'Utwory pobrane przyciskiem „Pobierz” przestaną być dostępne bez internetu. Pliki z '
          'serwera zostaną usunięte z telefonu, utwory z YouTube wrócą do zwykłej pamięci '
          'podręcznej.',
      action: 'Usuń',
    )) {
      return;
    }
    await downloads.removeAll();
    _done('Usunięto pobrane utwory.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final downloads = DownloadsScope.maybeOf(context);
    final library = YouTubeLibraryScope.of(context);
    final covers = AlbumCoversScope.maybeOf(context);
    final songsOn = settings.playbackMethods.contains(
      YouTubePlaybackMethod.cache,
    );
    final hint = TextStyle(
      fontSize: AppFontSize.listSubtitle,
      color: palette.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Pamięć podręczna'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Zajęte razem: ${_mb(cacheBytesOf(context))} MB.',
              style: hint,
            ),
          ),
          if (downloads != null) ...[
            const SectionTitle('Pobrane'),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Pobrane utwory'),
              subtitle: Text(
                '${downloads.count} ${_songs(downloads.count)}, '
                '${_mb(downloads.bytes)} MB',
              ),
            ),
            ListTile(
              enabled: downloads.count > 0,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Usuń wszystkie pobrane'),
              onTap: () => _removeDownloads(downloads),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Utwory i playlisty pobrane przyciskiem „Pobierz” zostają na telefonie. '
                'Muzyka z telefonu nie liczy się do limitu pamięci podręcznej.',
                style: hint,
              ),
            ),
          ],
          const SectionTitle('Utwory z YouTube'),
          ListTile(
            enabled: songsOn,
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Liczba utworów'),
            subtitle: Text(
              songsOn ? '${settings.cacheLimit}' : 'Wyłączone (Odtwarzanie › Sposoby odtwarzania YouTube › Pamięć podręczna)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editSongLimit(settings),
          ),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Zajęte miejsce'),
            subtitle: Text(
              '${library.cachedCount} ${_songs(library.cachedCount)}, '
              '${_mb(library.cachedBytes)} MB',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CacheContentsScreen(),
              ),
            ),
          ),
          ListTile(
            enabled: library.cachedCount > 0,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Wyczyść utwory z YouTube'),
            onTap: _clearSongs,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Gdy pamięć jest pełna, usuwany jest utwór, którego najdawniej słuchano.',
              style: hint,
            ),
          ),
          const SectionTitle('Kolejka'),
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: const Text(
              'Zapisuj z wyprzedzeniem następne utwory z kolejki',
            ),
            subtitle: Text(
              songsOn
                  ? 'Następne utwory z YouTube są pobierane na telefon, zanim zagrają'
                  : 'Wymaga zapisywania utworów z YouTube (powyżej)',
            ),
            value: settings.queuePrefetchEnabled,
            onChanged: settings.setQueuePrefetchEnabled,
          ),
          ListTile(
            enabled: settings.queuePrefetchEnabled,
            leading: const Icon(Icons.queue_music),
            title: const Text('Ile następnych utworów'),
            subtitle: Text(_nextSongs(settings.queuePrefetch)),
            onTap: () => _pickPrefetch(settings),
          ),
          const SectionTitle('Dopasowania z YouTube'),
          ListTile(
            enabled: library.phoneMatchCount > 0,
            leading: const Icon(Icons.youtube_searched_for),
            title: const Text('Zapomnij filmy dopasowane przez telefon'),
            subtitle: Text(
              '${library.phoneMatchCount} ${_songs(library.phoneMatchCount)} — '
              'zostaną wyszukane od nowa',
            ),
            onTap: _forgetMatches,
          ),
          ListTile(
            enabled: library.notFoundCount > 0,
            leading: const Icon(Icons.search_off),
            title: const Text('Zapomnij „nie znaleziono na YouTube”'),
            subtitle: Text(
              '${library.notFoundCount} ${_songs(library.notFoundCount)} — '
              'telefon poszuka ich ponownie',
            ),
            onTap: _forgetNotFound,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          ),
          if (covers != null) ...[
            const SectionTitle('Okładki'),
            ListTile(
              leading: const Icon(Icons.photo_size_select_large_outlined),
              title: const Text('Rozmiar'),
              subtitle: Text('${settings.coverCacheLimitMb} MB'),
              onTap: () => _pickCoverLimit(settings),
            ),
            ListTile(
              enabled: covers.cachedCount > 0,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Wyczyść okładki'),
              subtitle: Text(
                'Zajęte: ${_mb(covers.cachedBytes)} MB '
                '(${covers.cachedCount} obrazów)',
              ),
              onTap: () => _clearCovers(covers),
            ),
          ],
          const Divider(height: 32),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: palette.accent),
            title: const Text('Wyczyść wszystko'),
            subtitle: const Text(
              'Utwory z YouTube i okładki (pobrane zostają)',
            ),
            onTap: () => _clearAll(covers),
          ),
        ],
      ),
    );
  }
}

/// "1 utwór", "2 utwory", "5 utworów".
String _songs(int n) {
  if (n == 1) return 'utwór';
  final tens = n % 100;
  if (n % 10 >= 2 && n % 10 <= 4 && (tens < 12 || tens > 14)) return 'utwory';
  return 'utworów';
}

/// "1 następny utwór", "3 następne utwory", "5 następnych utworów".
String _nextSongs(int n) {
  if (n == 1) return '1 następny utwór';
  final few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return few ? '$n następne utwory' : '$n następnych utworów';
}
