import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_updates.dart';
import '../theme.dart';

/// "Dostępna nowa wersja": the release's notes, "Pobierz" (the APK in the browser, which hands
/// it to Android's installer) and "Później" (no more dialogs for this release).
Future<void> showUpdateDialog(
  BuildContext context,
  AppUpdates updates,
  AppRelease release,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final download = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.palette;
      return AlertDialog(
        title: Text('Dostępna nowa wersja ${release.label}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (release.notes.isNotEmpty) ...[
                Text(
                  'Co nowego',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  release.notes,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                '„Pobierz” otworzy plik w przeglądarce. Po pobraniu stuknij go i '
                'zainstaluj — za pierwszym razem Android poprosi o zgodę na instalowanie '
                'aplikacji z przeglądarki. Dane w aplikacji zostają.',
                style: TextStyle(
                  fontSize: AppFontSize.small,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Później'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Pobierz'),
          ),
        ],
      );
    },
  );
  if (download == null) return;
  if (!download) {
    await updates.dismiss();
    return;
  }
  final opened = await launchUrl(
    release.apkUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!opened) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Nie udało się otworzyć przeglądarki.')),
    );
  }
}
