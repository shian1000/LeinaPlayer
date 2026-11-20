import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_name.dart';
import '../data/app_updates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/update_dialog.dart';
import 'cache_settings_screen.dart';
import '../l10n.dart';

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
        SnackBar(content: Text(l10n.aboutScreenBrowserFailed)),
      );
    }
  }

  Future<void> _copySource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: sourceUrl.toString()));
    messenger.showSnackBar(SnackBar(content: Text(l10n.aboutScreenLinkCopied)));
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
        title: Text(l10n.aboutScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _VersionTile(packageInfo: packageInfo ?? PackageInfo.fromPlatform),
          if (AppUpdatesScope.maybeOf(context) case final updates?
              when updates.configured)
            ..._updateTiles(context, updates),
          SectionTitle(l10n.aboutScreenPrivateUse),
          paragraph(l10n.aboutScreenPrivateUseText),
          SectionTitle(l10n.aboutScreenAppSize),
          paragraph(l10n.aboutScreenAppSizeText),
          paragraph(l10n.aboutScreenAppVariantsText),
          _ApkVariantTile(packageInfo: packageInfo ?? PackageInfo.fromPlatform),
          paragraph(l10n.aboutScreenCacheText),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l10n.aboutScreenCache),
            subtitle: Text(
              l10n.aboutScreenCacheUsed(
                (cacheBytesOf(context) / (1024 * 1024)).toStringAsFixed(1),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CacheSettingsScreen(),
              ),
            ),
          ),
          SectionTitle(l10n.aboutScreenLinks),
          paragraph(l10n.aboutScreenLinksText(appName)),
          SectionTitle(l10n.aboutScreenLicense),
          paragraph('GNU General Public License v3 (GPLv3)'),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.aboutScreenSourceCode),
            subtitle: Text(sourceUrl.toString()),
            trailing: IconButton(
              tooltip: l10n.aboutScreenCopyLink,
              icon: const Icon(Icons.copy),
              onPressed: () => _copySource(context),
            ),
            onTap: () => _openSource(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutScreenLibraryLicenses),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                showLicensePage(context: context, applicationName: appName),
          ),
        ],
      ),
    );
  }
}

/// "Aktualizacje" and the daily check's switch; only in builds that know their releases
/// ([AppUpdates.configured]).
List<Widget> _updateTiles(BuildContext context, AppUpdates updates) => [
  updateCheckTile(context, updates),
  SwitchListTile(
    secondary: const Icon(Icons.schedule),
    title: Text(l10n.aboutScreenAutoCheck),
    subtitle: Text(l10n.aboutScreenAutoCheckSubtitle),
    value: updates.autoCheck,
    onChanged: updates.setAutoCheck,
  ),
];

/// "Aktualizacje": the newest release on GitHub, tapped to download or to check now — in
/// Informacje i pomoc.
Widget updateCheckTile(BuildContext context, AppUpdates updates) {
  final palette = context.palette;
  final release = updates.available;
  final last = updates.lastCheck;
  String two(int n) => n.toString().padLeft(2, '0');
  final subtitle = updates.checking
      ? l10n.aboutScreenChecking
      : release != null
      ? l10n.aboutScreenUpdateAvailable(release.label)
      : updates.problem ??
            (last == null
                ? l10n.aboutScreenNeverChecked
                : l10n.aboutScreenUpToDate(
                    dayMonthLabel(last),
                    '${two(last.hour)}:${two(last.minute)}',
                  ));
  return ListTile(
    leading: Icon(
      Icons.system_update_outlined,
      color: release != null ? palette.accent : null,
    ),
    title: Text(l10n.aboutScreenUpdates),
    subtitle: Text(
      subtitle,
      style: release != null ? TextStyle(color: palette.accent) : null,
    ),
    trailing: IconButton(
      tooltip: l10n.aboutScreenCheckNow,
      icon: const Icon(Icons.refresh),
      onPressed: updates.checking ? null : updates.check,
    ),
    onTap: updates.checking
        ? null
        : release != null
        ? () => showUpdateDialog(context, updates, release)
        : updates.check,
  );
}

/// The commit a build was made from (`tool/build_release_apk.sh`), with "+zmiany" when its
/// files differed from it; empty for builds made otherwise (`flutter run`).
const gitCommit = String.fromEnvironment('GIT_COMMIT');

/// "1.0.0 (kompilacja 312, c11e6c4)": the build number and commit only when known.
String versionLabel(String version, String buildNumber, String commit) {
  final details = [
    if (buildNumber.isNotEmpty) l10n.aboutScreenBuild(buildNumber),
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
  // The label is made in build, so a language change reaches "kompilacja".
  late final Future<PackageInfo?> _info = widget
      .packageInfo()
      .then<PackageInfo?>((info) => info)
      .catchError((Object _) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo?>(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      return ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.aboutScreenVersion(appName)),
        subtitle: Text(
          snapshot.connectionState != ConnectionState.done
              ? '…'
              : info == null
              ? l10n.aboutScreenVersionUnknown
              : versionLabel(
                  info.version,
                  buildNumberOf(info.buildNumber),
                  gitCommit,
                ),
        ),
      );
    },
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
              ? l10n.aboutScreenInstalledLarge
              : l10n.aboutScreenInstalledSmall,
        ),
        subtitle: Text(
          universal
              ? l10n.aboutScreenNextUpdateSmall
              : l10n.aboutScreenOnlyThisCpu,
        ),
      );
    },
  );
}
