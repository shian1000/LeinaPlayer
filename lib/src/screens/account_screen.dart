import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/database_sync.dart';
import '../data/library_folders.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/youtube_account.dart';
import '../widgets/feature_info.dart';
import 'feature_infos.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../l10n.dart';

/// "Ustawienia › Konto" (also the profile card in "Ja"): logging in with a MusicDatabase
/// user, or who is logged in and "Wyloguj" ([ADR 0006](../../../docs/decisions/0006-musicdatabase-login.md)),
/// and the Google account playlists are made on YouTube with. What syncs is on Synchronizacja.
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
      setState(() => _error = l10n.accountScreenEnterCredentials);
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
    final folders = LibraryFoldersScope.maybeOf(context);
    final user = AccountScope.of(context).userName;
    if (user == null) return;
    final playlistCount = await playlists?.phoneOnlyCount() ?? 0;
    final moodCount = moods?.phoneOnlyCount ?? 0;
    final folderCount = folders?.phoneOnlyCount ?? 0;
    if ((playlistCount == 0 && moodCount == 0 && folderCount == 0) ||
        !mounted) {
      return;
    }
    final kinds = [
      if (playlistCount > 0) l10n.accountScreenKindPlaylists,
      if (moodCount > 0) l10n.accountScreenKindMoods,
      if (folderCount > 0) l10n.accountScreenKindFolders,
    ];
    final what = kinds.length == 1
        ? kinds.single
        : l10n.accountScreenListAnd(
            kinds.sublist(0, kinds.length - 1).join(', '),
            kinds.last,
          );
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountScreenAddToAccountTitle(what)),
        content: Text(
          [
            if (playlistCount > 0)
              l10n.accountScreenPhoneOnlyPlaylists(playlistCount),
            if (moodCount > 0) l10n.accountScreenPhoneOnlyMoods(moodCount),
            if (folderCount > 0)
              l10n.accountScreenPhoneOnlyFolders(folderCount),
            l10n.accountScreenAddToAccountText(user),
          ].join(' '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.accountScreenNotNow),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonAdd),
          ),
        ],
      ),
    );
    if (!(add ?? false)) return;
    await playlists?.addPhoneOnlyToAccount();
    await moods?.addPhoneOnlyToAccount();
    await folders?.addPhoneOnlyToAccount();
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
        title: Text(l10n.accountScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ...account.loggedIn
              ? [
                  SectionTitle(l10n.accountScreenMusicDatabaseAccount),
                  ListTile(
                    leading: const ProfileAvatar(radius: 20),
                    title: Text(account.userName!),
                    subtitle: Text(l10n.accountScreenSignedIn),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: const LogOutButton(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(l10n.accountScreenSignedInText, style: hint),
                  ),
                  const _YouTubeAccountSection(),
                ]
              : [
                  SectionTitle(l10n.accountScreenSignInTitle),
                  if (account.needsLogin)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(l10n.accountScreenLoginRejected),
                      subtitle: Text(l10n.accountScreenEnterPasswordAgain),
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
                      decoration: InputDecoration(
                        labelText: l10n.accountScreenUserName,
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
                        labelText: l10n.accountScreenPassword,
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
                          : Text(
                              l10n.accountScreenSignIn,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(l10n.accountScreenSignInHelp, style: hint),
                  ),
                  const _YouTubeAccountSection(),
                ],
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
        child: Text(
          l10n.accountScreenSignOut,
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
        title: Text(l10n.accountScreenSignOutTitle),
        content: Text(l10n.accountScreenSignOutText(account.userName ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.accountScreenSignOut),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await account.logOut(await sync.serverAddresses());
  }
}

/// The Google account playlists are made on YouTube with ("Utwórz na YouTube"), once
/// signed in; signing out lets the next one pick another account.
class _YouTubeAccountSection extends StatelessWidget {
  const _YouTubeAccountSection();

  @override
  Widget build(BuildContext context) {
    final account = YouTubeAccountScope.maybeOf(context);
    final email = account?.email;
    if (account == null || email == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        SectionTitle(l10n.accountScreenGoogleAccount),
        ListTile(
          leading: const Icon(Icons.smart_display_outlined),
          title: Text(email),
          onLongPress: () =>
              showFeatureInfo(context, FeatureInfos.googleAccount),
          trailing: TextButton(
            onPressed: account.signOut,
            child: Text(l10n.accountScreenSignOut),
          ),
        ),
      ],
    );
  }
}
