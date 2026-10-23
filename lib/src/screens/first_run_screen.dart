import 'package:flutter/material.dart';

import '../app_name.dart';
import '../data/database_sync.dart';
import '../theme.dart';

/// The first start's question: may the music catalog come from GitHub? "Tak" leaves Ustawienia ›
/// Serwer › "Pobieraj z GitHuba" on and downloads it at once, "Nie" switches it off. Shown by
/// `AppShell` while [DatabaseSync.needsGitHubChoice]; it can't be dismissed without an answer.
class FirstRunScreen extends StatelessWidget {
  const FirstRunScreen({super.key});

  static const yesKey = Key('firstRun.gitHubYes');
  static const noKey = Key('firstRun.gitHubNo');

  static Future<void> show(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const FirstRunScreen(),
        ),
      );

  Future<void> _answer(BuildContext context, bool gitHub) async {
    final sync = DatabaseSyncScope.of(context);
    final navigator = Navigator.of(context);
    await sync.setGitHubOn(gitHub);
    navigator.pop();
    if (gitHub) await sync.syncIfDue();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    TextStyle body(Color color) =>
        TextStyle(fontSize: AppFontSize.body, color: color, height: 1.4);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              Icon(Icons.library_music, size: 56, color: palette.accent),
              const SizedBox(height: 24),
              Text(
                'Witaj w $appName',
                style: TextStyle(
                  fontSize: AppFontSize.hero,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pobierać bazę danych muzyki z GitHuba?',
                style: TextStyle(
                  fontSize: AppFontSize.section,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To publiczny katalog utworów (tytuły, wykonawcy, albumy, nastroje) z '
                'repozytorium ${sync.gitHubRepo}, pobierany raz dziennie. Dzięki niemu działa '
                'wyszukiwanie, radio, Odkrywaj i rekomendacje — także bez własnego serwera '
                'MusicDatabase.',
                style: body(palette.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'Bez niego aplikacja odtwarza muzykę z telefonu i z YouTube, a bazę może pobrać '
                'z Twojego serwera. Zmienisz to później w Ustawienia › Serwer › „Pobieraj z '
                'GitHuba”.',
                style: body(palette.textSecondary),
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: yesKey,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _answer(context, true),
                child: const Text('Tak, pobieraj z GitHuba'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: noKey,
                style: TextButton.styleFrom(
                  foregroundColor: palette.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _answer(context, false),
                child: const Text('Nie, bez GitHuba'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
