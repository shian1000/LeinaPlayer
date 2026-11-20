import 'package:flutter/material.dart';

import '../data/database_sync.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Synchronizacja › Baza danych › GitHub": the repository whose release `database` holds the
/// public copy of the catalog (ADR 0014); its switch and place in the order are on Baza danych.
class GitHubSourceScreen extends StatefulWidget {
  const GitHubSourceScreen({super.key});

  static const repoFieldKey = Key('database.gitHubRepo');

  @override
  State<GitHubSourceScreen> createState() => _GitHubSourceScreenState();
}

class _GitHubSourceScreenState extends State<GitHubSourceScreen> {
  final _repo = TextEditingController();
  String? _error;
  bool _initialized = false;

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
    _repo.text = _sync!.gitHubRepo;
  }

  @override
  void dispose() {
    _saveOnLeaving();
    _repo.dispose();
    super.dispose();
  }

  static String? _validate(String text) {
    try {
      DatabaseSync.normalizeGitHubRepo(text);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  /// Leaving the screen keeps what was typed, as on Prywatny serwer.
  void _saveOnLeaving() {
    final sync = _sync;
    if (sync == null || _repo.text.trim() == sync.gitHubRepo) return;
    final messenger = _messenger;
    final valid = _validate(_repo.text) == null;
    if (valid) sync.setGitHubRepo(_repo.text);
    if (messenger == null) return;
    // During dispose the tree is locked and the messenger can't rebuild yet.
    Future.microtask(() {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              valid
                  ? l10n.githubSourceScreenSaved
                  : l10n.githubSourceScreenNotSaved,
            ),
          ),
        );
      }
    });
  }

  Future<void> _save(DatabaseSync sync) async {
    final error = _validate(_repo.text);
    setState(() => _error = error);
    if (error != null) return;
    await sync.setGitHubRepo(_repo.text);
    if (mounted) setState(() => _repo.text = sync.gitHubRepo);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('GitHub'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionTitle(l10n.githubSourceScreenPublicCopy),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: GitHubSourceScreen.repoFieldKey,
              controller: _repo,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(sync),
              decoration: InputDecoration(
                hintText: DatabaseSync.defaultGitHubRepo,
                helperText: l10n.githubSourceScreenRepoHelper,
                helperMaxLines: 4,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              sync.gitHubOn
                  ? l10n.githubSourceScreenOn
                  : l10n.githubSourceScreenOff,
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
