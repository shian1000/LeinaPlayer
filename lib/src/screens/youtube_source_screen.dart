import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../data/youtube_search.dart';
import '../theme.dart';
import 'cache_contents_screen.dart';
import '../widgets/common.dart';
import 'youtube_playback_screen.dart';

/// "Ustawienia › Źródła muzyki › YouTube": searching YouTube ([YouTubeMethod]s), playing it
/// ([YouTubePlaybackMethod]s) and the cache of played songs. Methods are tried top to bottom.
class YouTubeSourceScreen extends StatelessWidget {
  const YouTubeSourceScreen({super.key});

  Future<void> _editApiKey(
    BuildContext context,
    SourceSettings settings,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Kod YouTube API',
        hint: 'Klucz YouTube Data API',
        initial: settings.apiKey ?? '',
      ),
    );
    if (result != null) await settings.setApiKey(result);
  }

  Future<void> _editCacheLimit(
    BuildContext context,
    SourceSettings settings,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Liczba utworów w pamięci podręcznej',
        hint: '${SourceSettings.defaultCacheLimit}',
        initial: '${settings.cacheLimit}',
        number: true,
      ),
    );
    final limit = int.tryParse(result?.trim() ?? '');
    if (limit == null || !context.mounted) return;
    await settings.setCacheLimit(limit);
    if (!context.mounted) return;
    await YouTubeLibraryScope.of(context).trim(settings.cacheKeep);
  }

  Future<void> _clearCache(BuildContext context) async {
    final library = YouTubeLibraryScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wyczyścić pamięć podręczną?'),
        content: const Text(
          'Zapisane na telefonie utwory z YouTube zostaną usunięte i przy następnym '
          'odtworzeniu pobrane ponownie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Wyczyść'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await library.clearCache();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final library = YouTubeLibraryScope.of(context);
    final enabled = settings.youTubeSearchEnabled;
    final apiKey = settings.apiKey;
    final cacheOn = settings.playbackMethods.contains(
      YouTubePlaybackMethod.cache,
    );

    final newPipeSearch = YouTubeScope.searchOf(context).newPipeAvailable;
    String methodNote(YouTubeMethod m) => switch (m) {
      YouTubeMethod.newPipe =>
        newPipeSearch
            ? 'Wyszukiwanie z telefonu, ta sama biblioteka co odtwarzanie'
            : 'Dostępne tylko na Androidzie',
      YouTubeMethod.explode => 'Wyszukiwanie z telefonu (pakiet Dart)',
      YouTubeMethod.ytDlpServer =>
        'Jeszcze niedostępne — serwer bazy danych nie obsługuje wyszukiwania',
      YouTubeMethod.api =>
        apiKey == null ? 'Wymaga kodu YouTube API' : 'YouTube Data API',
    };
    final hint = TextStyle(
      fontSize: AppFontSize.listSubtitle,
      color: palette.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('YouTube'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Wyszukiwanie'),
          SwitchListTile(
            secondary: const Icon(Icons.travel_explore),
            title: const Text('Włącz szukanie w serwisie YouTube'),
            value: enabled,
            onChanged: settings.setYouTubeSearchEnabled,
          ),
          for (final method in YouTubeMethod.values)
            SwitchListTile(
              secondary: Icon(switch (method) {
                YouTubeMethod.newPipe => Icons.smartphone,
                YouTubeMethod.explode => Icons.smartphone_outlined,
                YouTubeMethod.ytDlpServer => Icons.dns_outlined,
                YouTubeMethod.api => Icons.api,
              }),
              title: Text(method.label),
              subtitle: Text(methodNote(method)),
              value: settings.methods.contains(method),
              onChanged:
                  enabled && (method != YouTubeMethod.newPipe || newPipeSearch)
                  ? (v) => settings.setMethod(method, v)
                  : null,
            ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Kod YouTube API'),
            subtitle: Text(apiKey == null ? 'Nie ustawiono' : _masked(apiKey)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editApiKey(context, settings),
          ),
          const SectionTitle('Odtwarzanie'),
          ListTile(
            leading: const Icon(Icons.low_priority),
            title: const Text('Sposoby odtwarzania'),
            subtitle: Text(
              [
                for (final (i, m) in settings.activePlaybackMethods.indexed)
                  '${i + 1}. ${shortPlaybackLabel(m)}',
              ].join(', '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const YouTubePlaybackScreen(),
              ),
            ),
          ),
          const SectionTitle('Pamięć podręczna'),
          ListTile(
            enabled: cacheOn,
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Liczba utworów'),
            subtitle: Text('${settings.cacheLimit}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editCacheLimit(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Zajęte miejsce'),
            subtitle: Text(
              '${library.cachedCount} ${_songs(library.cachedCount)}, '
              '${(library.cachedBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
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
            title: const Text('Wyczyść pamięć podręczną'),
            onTap: () => _clearCache(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Używany jest pierwszy włączony sposób od góry, a kolejne tylko wtedy, gdy '
              'poprzedni zawiedzie. Gdy pamięć podręczna jest pełna, usuwany jest utwór, '
              'którego najdawniej słuchano.',
              style: hint,
            ),
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

/// Owns its text controller, so it's disposed only once the closing animation is over.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.hint,
    required this.initial,
    this.number = false,
  });

  final String title;
  final String hint;
  final String initial;
  final bool number;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: widget.number ? TextInputType.number : null,
        inputFormatters: widget.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// Only the last characters, so the key isn't shown in full on screen.
String _masked(String key) =>
    key.length <= 4 ? '••••' : '••••${key.substring(key.length - 4)}';
