import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/database_sync.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Ustawienia › Serwer" — the addresses MusicDatabase's files are downloaded from (remote, and
/// local for the home Wi-Fi; the GitHub repository when no server answers) and the state of the
/// last download.
class DatabaseSourceScreen extends StatefulWidget {
  const DatabaseSourceScreen({super.key});

  static const remoteFieldKey = Key('database.remoteAddress');
  static const localFieldKey = Key('database.localAddress');
  static const gitHubFieldKey = Key('database.gitHubRepo');

  @override
  State<DatabaseSourceScreen> createState() => _DatabaseSourceScreenState();
}

class _DatabaseSourceScreenState extends State<DatabaseSourceScreen> {
  final _remote = TextEditingController();
  final _local = TextEditingController();
  final _gitHub = TextEditingController();
  String? _remoteError;
  String? _localError;
  String? _gitHubError;
  bool _initialized = false;
  bool _readingWifi = false;
  bool _searchingServer = false;

  // Kept for dispose, when the context can't be used any more.
  DatabaseSync? _sync;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync = DatabaseSyncScope.of(context);
    _messenger = ScaffoldMessenger.maybeOf(context);
    if (_initialized) return;
    _initialized = true;
    final sync = DatabaseSyncScope.of(context);
    _remote.text = sync.remoteUrl?.toString() ?? '';
    _local.text = sync.localUrl?.toString() ?? '';
    _gitHub.text = sync.gitHubRepo;
  }

  @override
  void dispose() {
    _saveOnLeaving();
    _remote.dispose();
    _local.dispose();
    _gitHub.dispose();
    super.dispose();
  }

  /// Leaving the screen keeps what was typed (owner's wish: "Zapisz" was easy to miss) — when
  /// every field is valid; otherwise nothing is saved and a note says so. A system Back pops tab
  /// routes without asking (AGENTS.md), so this runs here rather than in a PopScope.
  void _saveOnLeaving() {
    final sync = _sync;
    if (sync == null) return;
    String shown(Object? value) => value?.toString() ?? '';
    final changed =
        _remote.text.trim() != shown(sync.remoteUrl) ||
        _local.text.trim() != shown(sync.localUrl) ||
        _gitHub.text.trim() != sync.gitHubRepo;
    if (!changed) return;
    if (_validate(_remote.text) != null ||
        _validate(_local.text) != null ||
        _validateRepo(_gitHub.text) != null) {
      _noteAfterLeaving('Nie zapisano adresu serwera: jest nieprawidłowy');
      return;
    }
    final remote = _remote.text;
    final local = _local.text;
    final gitHub = _gitHub.text;
    () async {
      await sync.setRemoteUrl(remote);
      await sync.setLocalUrl(local);
      await sync.setGitHubRepo(gitHub);
      if (sync.hasSource) await sync.syncNow();
    }();
    _noteAfterLeaving('Zapisano adresy serwera');
  }

  /// A note shown once this screen is gone: during dispose the tree is locked and the
  /// messenger can't rebuild yet.
  void _noteAfterLeaving(String text) {
    final messenger = _messenger;
    if (messenger == null) return;
    Future.microtask(() {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(text)));
      }
    });
  }

  /// Message for a field that doesn't hold a usable address, or `null` if it's fine.
  static String? _validate(String text) {
    try {
      DatabaseSync.normalizeUrl(text);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  static String? _validateRepo(String text) {
    try {
      DatabaseSync.normalizeGitHubRepo(text);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  Future<void> _save(DatabaseSync sync) async {
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final remoteError = _validate(_remote.text);
    final localError = _validate(_local.text);
    final gitHubError = _validateRepo(_gitHub.text);
    setState(() {
      _remoteError = remoteError;
      _localError = localError;
      _gitHubError = gitHubError;
    });
    if (remoteError != null || localError != null || gitHubError != null) {
      return;
    }

    await sync.setRemoteUrl(_remote.text);
    await sync.setLocalUrl(_local.text);
    await sync.setGitHubRepo(_gitHub.text);
    setState(() {
      _remote.text = sync.remoteUrl?.toString() ?? '';
      _local.text = sync.localUrl?.toString() ?? '';
      _gitHub.text = sync.gitHubRepo;
    });
    if (!sync.hasSource) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sync.localUrl != null
                ? 'Zapisano. Wybierz jeszcze sieć Wi-Fi albo podaj adres zdalny.'
                : 'Usunięto adresy, a GitHub jest wyłączony — baza nie będzie pobierana',
          ),
        ),
      );
      return;
    }
    // Downloading right away tells the user at once whether the address works, instead of
    // only finding out on tomorrow's automatic run.
    final ok = await sync.syncNow();
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pobrano bazę danych')),
      );
    }
  }

  Future<void> _useCurrentWifi(DatabaseSync sync) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text, {SnackBarAction? action}) =>
        messenger.showSnackBar(SnackBar(content: Text(text), action: action));

    setState(() => _readingWifi = true);
    try {
      // Android only reveals the Wi-Fi name to apps allowed to use location.
      final permission = await Permission.locationWhenInUse.request();
      if (!permission.isGranted) {
        say(
          'Bez dostępu do lokalizacji Android nie podaje nazwy sieci Wi-Fi.',
          action: permission.isPermanentlyDenied
              ? const SnackBarAction(
                  label: 'Ustawienia',
                  onPressed: openAppSettings,
                )
              : null,
        );
        return;
      }
      final ssid = await sync.currentWifiName();
      if (ssid == null) {
        say(
          'Nie wykryto sieci Wi-Fi. Połącz się z Wi-Fi i włącz lokalizację w telefonie.',
        );
        return;
      }
      await sync.setLocalWifi(ssid);

      if (mounted) setState(() => _searchingServer = true);
      final server = await sync.discoverLocalServer();
      if (server == null) {
        say(
          'Zapisano sieć „$ssid”, ale nie znaleziono w niej serwera bazy danych. '
          'Wpisz adres sieci lokalnej ręcznie.',
        );
        return;
      }
      await sync.setLocalUrl(server.toString());
      if (mounted) {
        setState(() {
          _local.text = server.toString();
          _localError = null;
        });
      }
      say('Zapisano sieć „$ssid” i adres serwera $server');
    } finally {
      if (mounted) {
        setState(() {
          _readingWifi = false;
          _searchingServer = false;
        });
      }
    }
  }

  Widget _addressField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required String helper,
    required String? error,
    required VoidCallback onSubmitted,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        key: key,
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmitted(),
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          helperMaxLines: 4,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    final lastSync = sync.lastSync;
    final error = sync.lastError;
    final wifi = sync.localWifi;
    final canDownload = sync.hasSource && !sync.downloading;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Serwer'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Adres serwera (połączenie zdalne)'),
          _addressField(
            key: DatabaseSourceScreen.remoteFieldKey,
            controller: _remote,
            hint: 'http://serwer:8002/',
            helper:
                'Używany poza siecią lokalną. Pobierane są pliki '
                'music.db, tag.db i files.db (lokalizacja plików na serwerze).',
            error: _remoteError,
            onSubmitted: () => _save(sync),
          ),
          const SectionTitle('Adres serwera (sieć lokalna)'),
          _addressField(
            key: DatabaseSourceScreen.localFieldKey,
            controller: _local,
            hint: 'http://192.168.x.x:8002/',
            helper: 'Używany, gdy telefon jest w sieci Wi-Fi wybranej poniżej.',
            error: _localError,
            onSubmitted: () => _save(sync),
          ),
          const SectionTitle('GitHub (publiczna kopia bazy)'),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('Pobieraj z GitHuba'),
            subtitle: const Text(
              'Gdy żaden serwer nie jest ustawiony albo nie odpowiada',
            ),
            value: sync.gitHubOn,
            onChanged: sync.downloading ? null : sync.setGitHubOn,
          ),
          _addressField(
            key: DatabaseSourceScreen.gitHubFieldKey,
            controller: _gitHub,
            hint: DatabaseSync.defaultGitHubRepo,
            helper:
                'Repozytorium (właściciel/nazwa), którego wydanie „database” zawiera '
                'music.db i tag.db. Puste przywraca domyślne.',
            error: _gitHubError,
            enabled: sync.gitHubOn,
            onSubmitted: () => _save(sync),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                shape: palette.pillShape,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: sync.downloading ? null : () => _save(sync),
              child: const Text(
                'Zapisz adresy i pobierz bazę',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SectionTitle('Wi-Fi sieci lokalnej'),
          ListTile(
            leading: Icon(wifi == null ? Icons.wifi_off : Icons.wifi),
            title: Text(wifi ?? 'Nie wybrano'),
            subtitle: Text(
              wifi == null
                  ? 'Bez wybranej sieci używany jest tylko adres zdalny.'
                  : 'W tej sieci baza jest pobierana z adresu sieci lokalnej.',
            ),
            trailing: wifi == null
                ? null
                : IconButton(
                    tooltip: 'Usuń sieć',
                    icon: Icon(Icons.close, color: palette.textSecondary),
                    onPressed: () => sync.setLocalWifi(null),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Przycisk poniżej zapisuje bieżącą sieć Wi-Fi i wyszukuje w niej serwer bazy '
              '(na tym samym porcie co adres zdalny), a znaleziony adres wpisuje jako adres '
              'sieci lokalnej.',
              style: TextStyle(
                fontSize: AppFontSize.listSubtitle,
                color: palette.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                shape: palette.pillShape,
                side: BorderSide(
                  color: palette.outline ?? palette.textSecondary,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _readingWifi
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: Text(
                _searchingServer
                    ? 'Szukam serwera w sieci lokalnej…'
                    : 'Użyj bieżącego połączenia',
              ),
              onPressed: _readingWifi ? null : () => _useCurrentWifi(sync),
            ),
          ),
          const SectionTitle('Pobieranie'),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Ostatnie pobranie'),
            subtitle: Text(
              sync.downloading
                  ? 'Pobieranie…'
                  : lastSync == null
                  ? 'Nigdy'
                  : _describeLastSync(lastSync, sync.lastSource),
            ),
            trailing: sync.downloading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (error != null && !sync.downloading)
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Ostatnia próba się nie udała'),
              subtitle: Text(error),
            ),
          ListTile(
            enabled: canDownload,
            leading: Icon(Icons.download, color: palette.accent),
            title: Text(
              'Pobierz teraz',
              style: TextStyle(
                color: canDownload ? palette.accent : palette.textSecondary,
              ),
            ),
            onTap: sync.syncNow,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Baza jest pobierana automatycznie raz dziennie przy uruchomieniu aplikacji. '
              'W wybranej sieci Wi-Fi z adresu sieci lokalnej (a gdy ten nie odpowiada — z '
              'adresu zdalnego), poza nią z adresu zdalnego. Gdy żaden serwer nie odpowiada, '
              'z GitHuba. Rozpoznanie sieci wymaga '
              'dostępu do lokalizacji i włączonej lokalizacji w telefonie.',
              style: TextStyle(
                fontSize: AppFontSize.listSubtitle,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _describeLastSync(DateTime d, DatabaseSource? source) {
  String two(int n) => n.toString().padLeft(2, '0');
  final when =
      '${two(d.day)}.${two(d.month)}.${d.year}, ${two(d.hour)}:${two(d.minute)}';
  return switch (source) {
    DatabaseSource.local => '$when (sieć lokalna)',
    DatabaseSource.remote => '$when (połączenie zdalne)',
    DatabaseSource.github => '$when (GitHub)',
    null => when,
  };
}
