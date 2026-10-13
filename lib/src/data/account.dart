import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The MusicDatabase user logged in on this phone ([ADR 0006](../../../docs/decisions/0006-musicdatabase-login.md)).
/// Users are created in MusicDatabase (main menu › Users); the phone logs in with a username and
/// password checked by the sharing server (`POST /login`), which answers with a token. Only the
/// username and the token are kept (in `shared_preferences`), never the password. The token goes
/// with every request sent to the inbox, so MusicDatabase knows who sent it; the username goes
/// into the request file names ([Outbox]).
class Account extends ChangeNotifier {
  static const _userKey = 'account.user_name';
  static const _tokenKey = 'account.token';

  /// How long to wait for the server before trying the next address (or giving up).
  static const timeout = Duration(seconds: 8);

  String? _userName;
  String? _token;
  bool _busy = false;

  /// The logged-in user (MusicDatabase's lowercase name), or the last one when the server no
  /// longer accepts the token ([needsLogin]); `null` when nobody logged in.
  String? get userName => _userName;

  /// Sent with requests to MusicDatabase; `null` while logged out.
  String? get token => _token;

  bool get loggedIn => _token != null;

  /// The server stopped accepting the saved login (token revoked, user deleted or renamed):
  /// the name is kept for the form, the password has to be typed again.
  bool get needsLogin => _userName != null && _token == null;

  /// A login or logout is under way.
  bool get busy => _busy;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString(_userKey);
    _token = prefs.getString(_tokenKey);
    notifyListeners();
  }

  /// Logs in on the first of [servers] (MusicDatabase's sharing server, best address first)
  /// that answers. Returns why it failed (Polish, for display), `null` on success.
  Future<String?> logIn(
    List<Uri> servers,
    String userName,
    String password,
  ) async {
    if (_busy) return 'Logowanie już trwa';
    if (servers.isEmpty) {
      return 'Najpierw ustaw adres serwera (Źródła muzyki › Baza danych)';
    }
    _busy = true;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = timeout;
    String? problem;
    try {
      for (final server in servers) {
        try {
          final request = await client
              .postUrl(server.resolve('/login'))
              .timeout(timeout);
          // MusicDatabase's server needs Content-Length (411 for a chunked body).
          final body = utf8.encode(
            jsonEncode({'username': userName.trim(), 'password': password}),
          );
          request.headers.contentType = ContentType.json;
          request.contentLength = body.length;
          request.add(body);
          final response = await request.close().timeout(timeout);
          final answerText = await utf8
              .decodeStream(response)
              .timeout(timeout);
          switch (response.statusCode) {
            case HttpStatus.ok:
              final answer = jsonDecode(answerText) as Map<String, Object?>;
              await _save(
                answer['username'] as String? ?? userName.trim().toLowerCase(),
                answer['token']! as String,
              );
              return null;
            case HttpStatus.unauthorized:
              return 'Nieprawidłowa nazwa użytkownika lub hasło';
            case HttpStatus.tooManyRequests:
              final seconds =
                  int.tryParse(
                    response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
                  ) ??
                  300;
              return 'Za dużo nieudanych prób logowania — spróbuj ponownie za '
                  '${(seconds / 60).ceil()} min';
            case HttpStatus.serviceUnavailable:
              return 'Dysk serwera MusicDatabase nie jest podłączony';
            case HttpStatus.notFound:
              problem = 'Serwer MusicDatabase nie obsługuje jeszcze logowania';
            default:
              problem = 'Serwer odpowiedział: HTTP ${response.statusCode}';
          }
        } catch (e) {
          debugPrint('Login on $server failed: $e');
          problem = 'Brak połączenia z serwerem MusicDatabase';
        }
      }
      return problem;
    } finally {
      client.close(force: true);
      _busy = false;
      notifyListeners();
    }
  }

  /// Forgets the login on the phone and asks the server (best effort) to revoke the token.
  Future<void> logOut(List<Uri> servers) async {
    final token = _token;
    _userName = null;
    _token = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
    if (token == null || servers.isEmpty) return;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      for (final server in servers) {
        try {
          final request = await client
              .postUrl(server.resolve('/logout'))
              .timeout(timeout);
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          request.contentLength = 0;
          final response = await request.close().timeout(timeout);
          await response.drain<void>();
          return;
        } catch (e) {
          debugPrint('Logout on $server failed: $e');
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  /// The server answered 401 to the saved token: log in again ([needsLogin]).
  Future<void> tokenRejected() async {
    if (_token == null) return;
    _token = null;
    notifyListeners();
    await (await SharedPreferences.getInstance()).remove(_tokenKey);
  }

  Future<void> _save(String userName, String token) async {
    _userName = userName;
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, userName);
    await prefs.setString(_tokenKey, token);
  }
}

class AccountScope extends InheritedNotifier<Account> {
  const AccountScope({
    super.key,
    required Account super.notifier,
    required super.child,
  });

  static Account of(BuildContext context) => maybeOf(context)!;

  /// `null` outside the app (widget tests that pump a single screen).
  static Account? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()?.notifier;
}
