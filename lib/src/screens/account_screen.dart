import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/database_sync.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/playlist_sync.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Ustawienia › Konto" (also "Menu profilu › Dodaj konto"): logging in with a MusicDatabase
/// user, or who is logged in and "Wyloguj" ([ADR 0006](../../../docs/decisions/0006-musicdatabase-login.md)).
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  static const userFieldKey = Key('account.userName');
  static const passwordFieldKey = Key('account.password');

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _user.text = AccountScope.of(context).userName ?? '';
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    final account = AccountScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Wpisz nazwę użytkownika i hasło');
      return;
    }
    setState(() => _error = null);
    final error = await account.logIn(
      await sync.serverAddresses(),
      _user.text,
      _password.text,
    );
    if (!mounted) return;
    setState(() {
      _error = error;
      if (error == null) _password.clear();
    });
    if (error == null) await _offerPhonePlaylists();
  }

  /// Playlists and moods made while logged out live only on this phone; the user decides
  /// whether they join the account (and so MusicDatabase and the account's other phones).
  Future<void> _offerPhonePlaylists() async {
    final playlists = PlaylistLibraryScope.maybeOf(context);
    final moods = MoodLibraryScope.maybeOf(context);
    final user = AccountScope.of(context).userName;
    if (user == null) return;
    final playlistCount = await playlists?.phoneOnlyCount() ?? 0;
    final moodCount = moods?.phoneOnlyCount ?? 0;
    if ((playlistCount == 0 && moodCount == 0) || !mounted) return;
    final what = [
      if (playlistCount > 0) 'playlisty',
      if (moodCount > 0) 'nastroje',
    ].join(' i ');
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dodać $what z telefonu do konta?'),
        content: Text(
          [
            if (playlistCount > 0)
              'Playlisty tylko na tym telefonie: $playlistCount.',
            if (moodCount > 0) 'Nastroje tylko na tym telefonie: $moodCount.',
            'Dodane do konta $user będą też w MusicDatabase i na innych telefonach tego '
                'konta. Bez dodania zostaną tylko tutaj.',
          ].join(' '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nie teraz'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
    if (!(add ?? false)) return;
    await playlists?.addPhoneOnlyToAccount();
    await moods?.addPhoneOnlyToAccount();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final account = AccountScope.of(context);
    final hint = TextStyle(
      fontSize: AppFontSize.listSubtitle,
      color: palette.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Konto'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: account.loggedIn
            ? [
                const SectionTitle('Konto MusicDatabase'),
                ListTile(
                  leading: const ProfileAvatar(radius: 20),
                  title: Text(account.userName!),
                  subtitle: const Text('Zalogowano'),
                ),
                const _PlaylistSyncTile(),
                const _MoodSyncTile(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: const LogOutButton(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'Playlisty z Biblioteki są zapisywane na tym koncie w MusicDatabase i '
                    'widoczne na każdym telefonie, na którym się na nie zalogujesz. '
                    'Zgłoszenia poprawek wysyłane do MusicDatabase są podpisane tym kontem.',
                    style: hint,
                  ),
                ),
              ]
            : [
                const SectionTitle('Zaloguj się do MusicDatabase'),
                if (account.needsLogin)
                  ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text(
                      'Serwer nie przyjął zapisanego logowania',
                    ),
                    subtitle: const Text('Wpisz hasło jeszcze raz.'),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: AccountScreen.userFieldKey,
                    controller: _user,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Nazwa użytkownika',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: AccountScreen.passwordFieldKey,
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _logIn(),
                    decoration: InputDecoration(
                      labelText: 'Hasło',
                      errorText: _error,
                      errorMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                  ),
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
                    onPressed: account.busy ? null : _logIn,
                    child: account.busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.onAccent,
                            ),
                          )
                        : const Text(
                            'Zaloguj',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'Konta zakłada się w MusicDatabase (Main menu › Users). Logowanie '
                    'wymaga połączenia z serwerem bazy danych; telefon zapamiętuje nazwę '
                    'użytkownika i znak logowania, nie hasło.',
                    style: hint,
                  ),
                ),
              ],
      ),
    );
  }
}

/// "Wyloguj", asking first; shared by Konto and the bottom of Ustawienia.
class LogOutButton extends StatelessWidget {
  const LogOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.outline ?? palette.textSecondary),
          shape: palette.pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        ),
        onPressed: () => _confirm(context),
        child: const Text(
          'Wyloguj',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final account = AccountScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wylogować?'),
        content: Text(
          'Telefon zapomni logowanie konta ${account.userName}. Playlisty konta znikną '
          'z Biblioteki do ponownego zalogowania (zmiany jeszcze niewysłane poczekają). '
          'Zgłoszenia, które czekają na wysłanie, zostaną.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wyloguj'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await account.logOut(await sync.serverAddresses());
  }
}

/// How the account's playlists last synced with MusicDatabase, and "sync now".
class _PlaylistSyncTile extends StatelessWidget {
  const _PlaylistSyncTile();

  @override
  Widget build(BuildContext context) {
    final playlists = PlaylistLibraryScope.maybeOf(context);
    if (playlists == null) return const SizedBox.shrink();
    final phoneOnly = playlists.playlists
        .where((p) => p.account == null)
        .length;
    final syncTile = _SyncTile(
      title: 'Playlisty',
      syncing: playlists.syncing,
      last: playlists.lastSync,
      onSync: () async =>
          playlists.sync(await DatabaseSyncScope.of(context).serverAddresses()),
    );
    if (phoneOnly == 0) return syncTile;
    // Also for a phone logged in before playlists synced, which was never asked.
    return Column(
      children: [
        syncTile,
        ListTile(
          leading: const Icon(Icons.phone_android),
          title: Text('Playlisty tylko na tym telefonie: $phoneOnly'),
          subtitle: const Text('Dotknij, aby dodać je do konta'),
          onTap: playlists.addPhoneOnlyToAccount,
        ),
      ],
    );
  }
}

/// How the account's moods last synced with MusicDatabase (with this phone's changes to global
/// moods), and "sync now".
class _MoodSyncTile extends StatelessWidget {
  const _MoodSyncTile();

  @override
  Widget build(BuildContext context) {
    final moods = MoodLibraryScope.maybeOf(context);
    if (moods == null) return const SizedBox.shrink();
    final syncTile = _SyncTile(
      title: 'Nastroje',
      syncing: moods.syncing,
      last: moods.lastSync,
      onSync: () async {
        final servers = await DatabaseSyncScope.of(context).serverAddresses();
        if (!context.mounted) return;
        await AccountScope.of(context).refreshPermissions(servers);
        await moods.sync(servers);
      },
    );
    final phoneOnly = moods.phoneOnlyCount;
    if (phoneOnly == 0) return syncTile;
    return Column(
      children: [
        syncTile,
        ListTile(
          leading: const Icon(Icons.phone_android),
          title: Text('Nastroje tylko na tym telefonie: $phoneOnly'),
          subtitle: const Text('Dotknij, aby dodać je do konta'),
          onTap: moods.addPhoneOnlyToAccount,
        ),
      ],
    );
  }
}

class _SyncTile extends StatelessWidget {
  const _SyncTile({
    required this.title,
    required this.syncing,
    required this.last,
    required this.onSync,
  });

  final String title;
  final bool syncing;
  final PlaylistSyncResult? last;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final last = this.last;
    final error = Theme.of(context).colorScheme.error;
    String two(int n) => n.toString().padLeft(2, '0');
    return ListTile(
      leading: Icon(
        last?.problem == null ? Icons.sync : Icons.sync_problem,
        color: last?.problem == null ? null : error,
      ),
      title: Text(title),
      subtitle: Text(
        syncing
            ? 'Synchronizowanie…'
            : last == null
            ? 'Jeszcze nie synchronizowano'
            : last.problem ??
                  'Zsynchronizowano o ${two(last.at.hour)}:${two(last.at.minute)}',
      ),
      trailing: IconButton(
        tooltip: 'Synchronizuj teraz',
        icon: const Icon(Icons.refresh),
        onPressed: syncing ? null : onSync,
      ),
    );
  }
}
