import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_name.dart';
import '../data/app_updates.dart';
import '../data/error_log.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/update_dialog.dart';
import 'cache_settings_screen.dart';
import 'error_log_screen.dart';
import 'problem_report_screen.dart';

/// "Ustawienia › Informacje i pomoc": the app's version and the terms it may be shared under.
/// Mostly a reminder for the owner — the app is for private use only and must never go to an
/// app store.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.packageInfo});

  /// Where the version comes from; tests pass their own.
  final Future<PackageInfo> Function()? packageInfo;

  static final sourceUrl = Uri.parse(
    'https://github.com/shian1000/LeinaPlayer',
  );

  Future<void> _openSource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      sourceUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć przeglądarki.')),
      );
    }
  }

  Future<void> _copySource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: sourceUrl.toString()));
    messenger.showSnackBar(
      const SnackBar(content: Text('Skopiowano link do kodu źródłowego')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.body,
          color: palette.textSecondary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Informacje i pomoc'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _VersionTile(packageInfo: packageInfo ?? PackageInfo.fromPlatform),
          if (AppUpdatesScope.maybeOf(context) case final updates?
              when updates.configured)
            ..._updateTiles(context, updates),
          const SectionTitle('Tylko do użytku prywatnego'),
          paragraph(
            'Aplikacja pobiera i odtwarza dźwięk z YouTube poza jego oficjalnym '
            'odtwarzaczem, co jest niezgodne z regulaminem YouTube i zasadami sklepów. '
            'Nie publikuj jej w Google Play ani w żadnym innym sklepie.',
          ),
          const SectionTitle('Problemy'),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Zgłoś problem'),
            subtitle: const Text(
              'Raport z wersją, telefonem i ostatnimi błędami — wysyłasz go sam',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProblemReportScreen(),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: ErrorLog.instance,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Dziennik błędów'),
              subtitle: Text(
                ErrorLog.instance.entries.isEmpty
                    ? 'Pusty'
                    : 'Wpisów: ${ErrorLog.instance.entries.length} '
                          '(ostatnie ${ErrorLog.keepFor.inDays} dni, tylko na telefonie)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ErrorLogScreen()),
              ),
            ),
          ),
          const SectionTitle('Rozmiar aplikacji'),
          paragraph(
            'Sama aplikacja to ok. 22 MB: silnik Flutter, którym rysuje ekran, i jej kod '
            'skompilowany do kodu maszynowego, razem z biblioteką NewPipe i silnikiem JavaScript '
            'do odtwarzania z YouTube.',
          ),
          paragraph(
            'Aplikacja jest wydawana w dwóch wersjach. Mała (ok. 25 MB) jest dla '
            'współczesnych telefonów z procesorem 64-bitowym — prawie wszystkich. Duża (ok. '
            '69 MB) zawiera wersje dla trzech rodzajów procesorów i działa na każdym '
            'telefonie, ale zajmuje około trzy razy więcej: Android przechowuje cały plik, '
            'choć używa tylko jednej części. Aktualizacje same wybierają małą, jeśli pasuje do '
            'telefonu; z dużej można przejść na małą bez utraty danych.',
          ),
          _ApkVariantTile(packageInfo: packageInfo ?? PackageInfo.fromPlatform),
          paragraph(
            'W trakcie używania najwięcej miejsca zajmuje pamięć podręczna: utwory z YouTube '
            '(by grały bez internetu i nie pobierały się ponownie), okładki i utwory zapisane '
            'przez „Pobierz”. Jej limit ustawisz poniżej. Baza utworów zajmuje kilka MB.',
          ),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Pamięć podręczna'),
            subtitle: Text(
              'Zajęte ${(cacheBytesOf(context) / (1024 * 1024)).toStringAsFixed(1)} MB',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CacheSettingsScreen(),
              ),
            ),
          ),
          const SectionTitle('Linki z YouTube i Spotify'),
          paragraph(
            'Co robi kliknięty albo udostępniony link i jak sprawić, żeby trafiał do '
            '$appName: Ustawienia › Otwieranie linków.',
          ),
          const SectionTitle('Licencja'),
          paragraph('GNU General Public License v3 (GPLv3)'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Kod źródłowy'),
            subtitle: Text(sourceUrl.toString()),
            trailing: IconButton(
              tooltip: 'Kopiuj link',
              icon: const Icon(Icons.copy),
              onPressed: () => _copySource(context),
            ),
            onTap: () => _openSource(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licencje bibliotek'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                showLicensePage(context: context, applicationName: appName),
          ),
        ],
      ),
    );
  }
}

/// "Aktualizacje" (the newest release on GitHub, tapped to download or to check now) and the
/// daily check's switch; only in builds that know their releases ([AppUpdates.configured]).
List<Widget> _updateTiles(BuildContext context, AppUpdates updates) {
  final palette = context.palette;
  final release = updates.available;
  final last = updates.lastCheck;
  String two(int n) => n.toString().padLeft(2, '0');
  final subtitle = updates.checking
      ? 'Sprawdzam…'
      : release != null
      ? 'Dostępna wersja ${release.label} — stuknij, żeby pobrać'
      : updates.problem ??
            (last == null
                ? 'Jeszcze nie sprawdzano'
                : 'Masz najnowszą wersję (sprawdzono '
                      '${dayMonthLabel(last)}, ${two(last.hour)}:${two(last.minute)})');
  return [
    ListTile(
      leading: Icon(
        Icons.system_update_outlined,
        color: release != null ? palette.accent : null,
      ),
      title: const Text('Aktualizacje'),
      subtitle: Text(
        subtitle,
        style: release != null ? TextStyle(color: palette.accent) : null,
      ),
      trailing: IconButton(
        tooltip: 'Sprawdź teraz',
        icon: const Icon(Icons.refresh),
        onPressed: updates.checking ? null : updates.check,
      ),
      onTap: updates.checking
          ? null
          : release != null
          ? () => showUpdateDialog(context, updates, release)
          : updates.check,
    ),
    SwitchListTile(
      secondary: const Icon(Icons.schedule),
      title: const Text('Sprawdzaj aktualizacje automatycznie'),
      subtitle: const Text('Raz dziennie, w wydaniach aplikacji na GitHubie'),
      value: updates.autoCheck,
      onChanged: updates.setAutoCheck,
    ),
  ];
}

/// The commit a build was made from (`tool/build_release_apk.sh`), with "+zmiany" when its
/// files differed from it; empty for builds made otherwise (`flutter run`).
const gitCommit = String.fromEnvironment('GIT_COMMIT');

/// "1.0.0 (kompilacja 312, c11e6c4)": the build number and commit only when known.
String versionLabel(String version, String buildNumber, String commit) {
  final details = [
    if (buildNumber.isNotEmpty) 'kompilacja $buildNumber',
    if (commit.isNotEmpty) commit,
  ];
  return details.isEmpty ? version : '$version (${details.join(', ')})';
}

/// "Wersja": `version` from `pubspec.yaml`, the build number (the commit count when built with
/// `tool/build_release_apk.sh`) and the commit.
class _VersionTile extends StatefulWidget {
  const _VersionTile({required this.packageInfo});

  final Future<PackageInfo> Function() packageInfo;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  late final Future<String> _version = widget
      .packageInfo()
      .then(
        (info) => versionLabel(
          info.version,
          buildNumberOf(info.buildNumber),
          gitCommit,
        ),
      )
      .catchError((Object _) => 'nieznana');

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _version,
    builder: (context, snapshot) => ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text('$appName — wersja'),
      subtitle: Text(snapshot.data ?? '…'),
    ),
  );
}

/// "Zainstalowana wersja: mała / duża", from the installed APK's versionCode; nothing when it
/// can't tell ([isUniversalApk]).
class _ApkVariantTile extends StatefulWidget {
  const _ApkVariantTile({required this.packageInfo});

  final Future<PackageInfo> Function() packageInfo;

  @override
  State<_ApkVariantTile> createState() => _ApkVariantTileState();
}

class _ApkVariantTileState extends State<_ApkVariantTile> {
  // Once: the screen rebuilds whenever the update check reports.
  late final Future<PackageInfo> _info = widget.packageInfo();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final universal = info == null ? null : isUniversalApk(info.buildNumber);
      if (universal == null) return const SizedBox.shrink();
      return ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          universal
              ? 'Zainstalowana wersja: duża'
              : 'Zainstalowana wersja: mała',
        ),
        subtitle: Text(
          universal
              ? 'Następna aktualizacja przejdzie na małą, jeśli pasuje do telefonu'
              : 'Tylko dla procesora tego telefonu',
        ),
      );
    },
  );
}
