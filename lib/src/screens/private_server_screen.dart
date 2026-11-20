import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/database_sync.dart';
import '../data/server_trust.dart';
import '../data/sync_sources.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../l10n.dart';

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
      _noteAfterLeaving(l10n.privateServerScreenInvalidNotSaved);
      return;
    }
    final remote = _remote.text;
    final local = _local.text;
    () async {
      await sync.setRemoteUrl(remote);
      await sync.setLocalUrl(local);
      if (sync.usesServer(SyncFeature.database)) await sync.syncNow();
    }();
    _noteAfterLeaving(l10n.privateServerScreenAddressesSaved);
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
                ? l10n.privateServerScreenSavedPickWifi
                : l10n.privateServerScreenAddressesRemoved,
          ),
        ),
      );
      return;
    }
    if (!await _confirmCertificates([sync.remoteUrl, sync.localUrl])) return;
    if (!sync.usesServer(SyncFeature.database)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.privateServerScreenAddressesSaved)),
      );
      return;
    }
    // Downloading right away tells the user at once whether the address works, instead of
    // only finding out on tomorrow's automatic run.
    final ok = await sync.syncNow();
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.privateServerScreenDatabaseDownloaded)),
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
          l10n.privateServerScreenNoLocationPermission,
          action: permission.isPermanentlyDenied
              ? SnackBarAction(
                  label: l10n.privateServerScreenSettingsAction,
                  onPressed: openAppSettings,
                )
              : null,
        );
        return;
      }
      final ssid = await sync.currentWifiName();
      if (ssid == null) {
        say(l10n.privateServerScreenNoWifi);
        return;
      }
      await sync.setLocalWifi(ssid);

      if (mounted) setState(() => _searchingServer = true);
      final server = await sync.discoverLocalServer();
      if (server == null) {
        say(l10n.privateServerScreenWifiSavedNoServer(ssid));
        return;
      }
      if (!await _confirmCertificates([server])) {
        say(
          l10n.privateServerScreenWifiSavedCertRejected(
            ssid,
            server.toString(),
          ),
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
      say(l10n.privateServerScreenWifiAndServerSaved(ssid, server.toString()));
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
        title: Text(l10n.privateServerScreenForgetCertTitle),
        content: Text(l10n.privateServerScreenForgetCertText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.privateServerScreenForget),
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
        title: Text(l10n.privateServerScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionTitle(l10n.privateServerScreenRemoteAddress),
          _addressField(
            key: PrivateServerScreen.remoteFieldKey,
            controller: _remote,
            hint: 'https://serwer:8002/',
            helper: l10n.privateServerScreenRemoteAddressHelp,
            error: _remoteError,
            onSubmitted: () => _save(sync),
          ),
          SectionTitle(l10n.privateServerScreenLocalAddress),
          _addressField(
            key: PrivateServerScreen.localFieldKey,
            controller: _local,
            hint: 'https://192.168.x.x:8002/',
            helper: l10n.privateServerScreenLocalAddressHelp,
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
              child: Text(
                l10n.privateServerScreenSaveAddresses,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (ServerTrust.instance.hasPins) ...[
            SectionTitle(l10n.privateServerScreenCertificate),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(l10n.privateServerScreenCertificateTrusted),
              subtitle: Text(l10n.privateServerScreenCertificateHelp),
              trailing: TextButton(
                onPressed: _forgetCertificates,
                child: Text(l10n.privateServerScreenForget),
              ),
            ),
          ],
          SectionTitle(l10n.privateServerScreenLocalWifi),
          ListTile(
            leading: Icon(wifi == null ? Icons.wifi_off : Icons.wifi),
            title: Text(wifi ?? l10n.privateServerScreenNoWifiPicked),
            subtitle: Text(
              wifi == null
                  ? l10n.privateServerScreenNoWifiPickedHelp
                  : l10n.privateServerScreenWifiPickedHelp,
            ),
            trailing: wifi == null
                ? null
                : IconButton(
                    tooltip: l10n.privateServerScreenRemoveWifi,
                    icon: Icon(Icons.close, color: palette.textSecondary),
                    onPressed: () => sync.setLocalWifi(null),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.privateServerScreenUseCurrentHelp,
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
                    ? l10n.privateServerScreenSearchingServer
                    : l10n.privateServerScreenUseCurrent,
              ),
              onPressed: _readingWifi ? null : () => _useCurrentWifi(sync),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.privateServerScreenExplanation,
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
      title: Text(l10n.privateServerScreenConfirmCertTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.privateServerScreenConfirmCertCode(url.host, url.port)),
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
            l10n.privateServerScreenConfirmCertHelp,
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.privateServerScreenReject),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.privateServerScreenAccept),
        ),
      ],
    ),
  );
  return yes == true;
}
