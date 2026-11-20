import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/database_sync.dart';
import '../data/server_trust.dart';
import '../data/sync_sources.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Synchronizacja › … › Prywatny serwer" (and Odtwarzanie › Źródła) — the addresses of the
/// user's MusicDatabase server (remote, and local for the home Wi-Fi) and its certificate; one
/// server for every synced function, each switching it apart on its own screen.
class PrivateServerScreen extends StatefulWidget {
  const PrivateServerScreen({super.key});

  static const remoteFieldKey = Key('database.remoteAddress');
  static const localFieldKey = Key('database.localAddress');

  @override
  State<PrivateServerScreen> createState() => _PrivateServerScreenState();
}

class _PrivateServerScreenState extends State<PrivateServerScreen> {
  final _remote = TextEditingController();
  final _local = TextEditingController();
  String? _remoteError;
  String? _localError;
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
  }

  @override
  void dispose() {
    _saveOnLeaving();
    _remote.dispose();
    _local.dispose();
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
        _local.text.trim() != shown(sync.localUrl);
    if (!changed) return;
    if (_validate(_remote.text) != null || _validate(_local.text) != null) {
      _noteAfterLeaving('Nie zapisano adresu serwera: jest nieprawidłowy');
      return;
    }
    final remote = _remote.text;
    final local = _local.text;
    () async {
      await sync.setRemoteUrl(remote);
      await sync.setLocalUrl(local);
      if (sync.usesServer(SyncFeature.database)) await sync.syncNow();
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

  Future<void> _save(DatabaseSync sync) async {
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final remoteError = _validate(_remote.text);
    final localError = _validate(_local.text);
    setState(() {
      _remoteError = remoteError;
      _localError = localError;
    });
    if (remoteError != null || localError != null) return;

    await sync.setRemoteUrl(_remote.text);
    await sync.setLocalUrl(_local.text);
    setState(() {
      _remote.text = sync.remoteUrl?.toString() ?? '';
      _local.text = sync.localUrl?.toString() ?? '';
    });
    if (!sync.hasServer) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sync.localUrl != null
                ? 'Zapisano. Wybierz jeszcze sieć Wi-Fi albo podaj adres zdalny.'
                : 'Usunięto adresy — telefon nie łączy się z prywatnym serwerem',
          ),
        ),
      );
      return;
    }
    if (!await _confirmCertificates([sync.remoteUrl, sync.localUrl])) return;
    if (!sync.usesServer(SyncFeature.database)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Zapisano adresy serwera')),
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
      if (!await _confirmCertificates([server])) {
        say(
          'Zapisano sieć „$ssid”. Nie zapisano serwera $server — certyfikat odrzucony.',
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

  /// Asks about every HTTPS address in [urls] whose server shows a certificate the phone
  /// doesn't trust yet ([ServerTrust.check]); `false` once the user says one isn't theirs. An
  /// address that doesn't answer now is left for the download to report.
  Future<bool> _confirmCertificates(List<Uri?> urls) async {
    final trust = ServerTrust.instance;
    for (final url in urls) {
      if (url == null || url.scheme != 'https') continue;
      final result = await trust.check(
        url.resolve(DatabaseSync.fileNames.first),
      );
      if (result is! CertificateUnknown) continue;
      if (!mounted) return false;
      final yes = await confirmServerCertificate(context, url, result.code);
      if (!yes) return false;
      await trust.pin(result.certificate);
      if (mounted) setState(() {});
    }
    return true;
  }

  Future<void> _forgetCertificates() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zapomnieć certyfikat serwera?'),
        content: const Text(
          'Przy następnym zapisaniu adresów telefon znów pokaże kod certyfikatu do '
          'porównania. Do tego czasu połączenia z serwerem przez HTTPS nie będą działać.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zapomnij'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await ServerTrust.instance.forgetAll();
    if (mounted) setState(() {});
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
    final wifi = sync.localWifi;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Prywatny serwer'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Adres serwera (połączenie zdalne)'),
          _addressField(
            key: PrivateServerScreen.remoteFieldKey,
            controller: _remote,
            hint: 'https://serwer:8002/',
            helper:
                'Używany poza siecią lokalną. Pobierane są pliki '
                'music.db, tag.db i files.db (lokalizacja plików na serwerze).',
            error: _remoteError,
            onSubmitted: () => _save(sync),
          ),
          const SectionTitle('Adres serwera (sieć lokalna)'),
          _addressField(
            key: PrivateServerScreen.localFieldKey,
            controller: _local,
            hint: 'https://192.168.x.x:8002/',
            helper: 'Używany, gdy telefon jest w sieci Wi-Fi wybranej poniżej.',
            error: _localError,
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
                'Zapisz adresy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (ServerTrust.instance.hasPins) ...[
            const SectionTitle('Certyfikat serwera'),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Zaufany certyfikat zapamiętany'),
              subtitle: const Text(
                'Telefon łączy się przez HTTPS tylko z serwerem, którego kod potwierdzono. '
                'Gdy serwer dostał nowy certyfikat, zapomnij stary i zapisz adresy ponownie.',
              ),
              trailing: TextButton(
                onPressed: _forgetCertificates,
                child: const Text('Zapomnij'),
              ),
            ),
          ],
          const SectionTitle('Wi-Fi sieci lokalnej'),
          ListTile(
            leading: Icon(wifi == null ? Icons.wifi_off : Icons.wifi),
            title: Text(wifi ?? 'Nie wybrano'),
            subtitle: Text(
              wifi == null
                  ? 'Bez wybranej sieci używany jest tylko adres zdalny.'
                  : 'W tej sieci telefon łączy się z adresem sieci lokalnej.',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'W wybranej sieci Wi-Fi telefon łączy się z adresem sieci lokalnej (a gdy ten nie '
              'odpowiada — z adresem zdalnym), poza nią z adresem zdalnym. Rozpoznanie sieci '
              'wymaga dostępu do lokalizacji i włączonej lokalizacji w telefonie. Z czym się '
              'synchronizuje, ustawisz w Synchronizacja — osobno dla bazy danych, biblioteki i '
              'próśb do bazy.',
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

/// "Czy to Twój serwer?" with the certificate's code ([certificateCode]) to compare with the
/// one MusicDatabase shows; `true` when the user says it's theirs.
Future<bool> confirmServerCertificate(
  BuildContext context,
  Uri url,
  String code,
) async {
  final palette = context.palette;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Czy to Twój serwer?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Serwer ${url.host}:${url.port} pokazuje certyfikat o kodzie:'),
          const SizedBox(height: 12),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Porównaj go z kodem, który pokazuje MusicDatabase (serwer wypisuje go przy '
            'starcie). Potwierdź tylko, gdy oba są takie same — inny kod może oznaczać, że '
            'ktoś podszywa się pod serwer.',
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nie, odrzuć'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Tak, to mój serwer'),
        ),
      ],
    ),
  );
  return yes == true;
}
