import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_api.dart';

/// Managing the user's YouTube playlists (YouTube Data API).
const youTubeScope = 'https://www.googleapis.com/auth/youtube';

/// The Web client of the app's Google Cloud project. Android's Credential Manager needs it as
/// `serverClientId`; the app itself is recognised by its Android client (package name + the
/// signing key's SHA-1) — see `docs/agent-notes/youtube.md`.
const _webClientId =
    '120009798113-2s1vgh8j3f6cp87jgoue8hfbgmkhso2j.apps.googleusercontent.com';

/// Why signing in to Google failed, for display; [cancelled] when the user closed the window.
class GoogleSignInFailed implements Exception {
  const GoogleSignInFailed(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// The Google sign-in itself, replaced in tests.
abstract class GoogleAuth {
  /// Signs in (asking the user when needed) and returns the account's e-mail and an access
  /// token for [scopes]. [interactive] `false` never shows anything and returns `null` instead.
  Future<({String email, String token})?> signIn(
    List<String> scopes, {
    required bool interactive,
  });

  /// The token was refused (expired): the next [signIn] gets a new one.
  Future<void> forgetToken(String token);
  Future<void> signOut();
}

class _PluginGoogleAuth implements GoogleAuth {
  Future<void>? _initialized;
  GoogleSignInAccount? _user;

  Future<void> _init() => _initialized ??= GoogleSignIn.instance.initialize(
    serverClientId: _webClientId,
  );

  @override
  Future<({String email, String token})?> signIn(
    List<String> scopes, {
    required bool interactive,
  }) async {
    try {
      await _init();
      final signIn = GoogleSignIn.instance;
      var user = _user ??= await signIn.attemptLightweightAuthentication();
      if (user == null) {
        if (!interactive) return null;
        user = _user = await signIn.authenticate(scopeHint: scopes);
      }
      final client = user.authorizationClient;
      final authorization =
          await client.authorizationForScopes(scopes) ??
          (interactive ? await client.authorizeScopes(scopes) : null);
      if (authorization == null) return null;
      return (email: user.email, token: authorization.accessToken);
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      throw switch (e.code) {
        GoogleSignInExceptionCode.canceled => const GoogleSignInFailed(
          'Logowanie do Google przerwane',
          cancelled: true,
        ),
        GoogleSignInExceptionCode.clientConfigurationError =>
          const GoogleSignInFailed(
            'Aplikacja nie jest poprawnie zarejestrowana w Google Cloud',
          ),
        _ => GoogleSignInFailed(
          'Nie udało się zalogować do Google (${e.code.name})',
        ),
      };
    }
  }

  @override
  Future<void> forgetToken(String token) async {
    await _init();
    await _user?.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
  }

  @override
  Future<void> signOut() async {
    await _init();
    _user = null;
    await GoogleSignIn.instance.signOut();
  }
}

/// The Google account the phone makes YouTube playlists with — separate from the MusicDatabase
/// login ([Account]); MusicDatabase isn't involved. Only the e-mail is kept, for Ustawienia ›
/// Konto; Google Play Services keeps the sign-in itself.
class YouTubeAccount extends ChangeNotifier {
  YouTubeAccount({GoogleAuth? auth, YouTubeApi? api, bool? supported})
    : _auth = auth ?? _PluginGoogleAuth(),
      api = api ?? YouTubeApi(),
      supported = supported ?? (!kIsWeb && Platform.isAndroid);

  final GoogleAuth _auth;

  /// What playlists are made with, with this account's [token].
  final YouTubeApi api;

  /// Only Android has its Google Cloud client so far.
  final bool supported;

  static const _emailKey = 'youtube_account.email';

  String? _email;

  /// The Google account last signed in with; `null`: none.
  String? get email => _email;

  Future<void> load() async {
    _email = (await SharedPreferences.getInstance()).getString(_emailKey);
    notifyListeners();
  }

  /// An access token for [youTubeScope], signing in first when needed (Google's own window).
  /// Throws [GoogleSignInFailed].
  Future<String> token() async {
    if (!supported) {
      throw const GoogleSignInFailed(
        'Tworzenie playlist na YouTube działa na razie tylko na Androidzie',
      );
    }
    final result = await _auth.signIn(const [youTubeScope], interactive: true);
    if (result == null) {
      throw const GoogleSignInFailed('Nie udało się zalogować do Google');
    }
    if (result.email != _email) {
      _email = result.email;
      await (await SharedPreferences.getInstance()).setString(
        _emailKey,
        result.email,
      );
      notifyListeners();
    }
    return result.token;
  }

  /// YouTube refused [token] (HTTP 401).
  Future<void> tokenRejected(String token) => _auth.forgetToken(token);

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Google sign-out failed: $e');
    }
    _email = null;
    await (await SharedPreferences.getInstance()).remove(_emailKey);
    notifyListeners();
  }
}

class YouTubeAccountScope extends InheritedNotifier<YouTubeAccount> {
  const YouTubeAccountScope({
    super.key,
    required YouTubeAccount super.notifier,
    required super.child,
  });

  static YouTubeAccount of(BuildContext context) => maybeOf(context)!;

  static YouTubeAccount? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<YouTubeAccountScope>()
      ?.notifier;
}
