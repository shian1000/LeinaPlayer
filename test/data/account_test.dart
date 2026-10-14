import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/account.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late HttpServer server;
  late List<String> loggedOut;
  late List<Map<String, Object?>> logins;
  int? loginAnswer;
  var permissions = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    loggedOut = [];
    logins = [];
    loginAnswer = null;
    permissions = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      switch (request.uri.path) {
        // Like MusicDatabase's server: no chunked bodies.
        case '/login' when request.contentLength < 0:
          request.response.statusCode = HttpStatus.lengthRequired;
        case '/login' when request.method == 'POST':
          final login = jsonDecode(body) as Map<String, Object?>;
          logins.add(login);
          if (loginAnswer != null) {
            request.response.statusCode = loginAnswer!;
            if (loginAnswer == HttpStatus.tooManyRequests) {
              request.response.headers.set(HttpHeaders.retryAfterHeader, '290');
            }
          } else if (login['username'] == 'Owner' &&
              login['password'] == 'tajne1') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'username': 'owner',
                'token': 'tok-123',
                'permissions': permissions,
              }),
            );
          } else {
            request.response.statusCode = HttpStatus.unauthorized;
          }
        case '/users/owner' when request.method == 'GET':
          if (request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer tok-123') {
            request.response.statusCode = HttpStatus.unauthorized;
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'username': 'owner', 'permissions': permissions}),
            );
          }
        case '/logout' when request.method == 'POST':
          loggedOut.add(
            request.headers.value(HttpHeaders.authorizationHeader) ?? '',
          );
          request.response.statusCode = HttpStatus.noContent;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri base() => Uri.parse('http://127.0.0.1:${server.port}/');

  test(
    'logging in keeps the server\'s username and the token, not the password',
    () async {
      final account = Account();
      await account.load();
      expect(account.loggedIn, isFalse);

      expect(await account.logIn([base()], ' Owner ', 'tajne1'), isNull);
      expect(logins.single, {'username': 'Owner', 'password': 'tajne1'});
      expect(account.loggedIn, isTrue);
      expect(account.userName, 'owner');
      expect(account.token, 'tok-123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {
        'account.user_name',
        'account.token',
        'account.permissions',
      });
      expect(prefs.getKeys().map(prefs.get), isNot(contains('tajne1')));

      final restarted = Account();
      await restarted.load();
      expect(restarted.userName, 'owner');
      expect(restarted.token, 'tok-123');
    },
  );

  test('a wrong password, an old server and no server say so', () async {
    final account = Account();
    expect(
      await account.logIn([base()], 'owner', 'zle'),
      contains('Nieprawidłowa'),
    );
    loginAnswer = HttpStatus.tooManyRequests;
    expect(
      await account.logIn([base()], 'owner', 'tajne1'),
      allOf(contains('Za dużo'), contains('5 min')),
    );
    loginAnswer = HttpStatus.notFound;
    expect(
      await account.logIn([base()], 'owner', 'tajne1'),
      contains('nie obsługuje jeszcze logowania'),
    );
    final gone = base();
    await server.close(force: true);
    expect(
      await account.logIn([gone], 'owner', 'tajne1'),
      contains('Brak połączenia'),
    );
    expect(await account.logIn([], 'owner', 'tajne1'), contains('adres'));
    expect(account.loggedIn, isFalse);
  });

  test(
    'logging out forgets the login and revokes the token on the server',
    () async {
      final account = Account();
      await account.logIn([base()], 'Owner', 'tajne1');
      await account.logOut([base()]);
      expect(account.loggedIn, isFalse);
      expect(account.userName, isNull);
      expect(loggedOut, ['Bearer tok-123']);
      final restarted = Account();
      await restarted.load();
      expect(restarted.loggedIn, isFalse);
    },
  );

  test(
    'a token the server rejects: log in again, the name stays for the form',
    () async {
      final account = Account();
      await account.logIn([base()], 'Owner', 'tajne1');
      await account.tokenRejected();
      expect(account.loggedIn, isFalse);
      expect(account.needsLogin, isTrue);
      expect(account.userName, 'owner');
    },
  );

  test('permissions come with the login and are refreshed', () async {
    permissions = ['edit_global_moods'];
    final account = Account();
    await account.load();
    expect(account.hasPermission(Account.editGlobalMoods), isFalse);
    await account.logIn([base()], 'Owner', 'tajne1');
    expect(account.hasPermission(Account.editGlobalMoods), isTrue);

    // Revoked in MusicDatabase: the next refresh drops it, and it stays dropped.
    permissions = [];
    await account.refreshPermissions([base()]);
    expect(account.hasPermission(Account.editGlobalMoods), isFalse);
    final restarted = Account();
    await restarted.load();
    expect(restarted.hasPermission(Account.editGlobalMoods), isFalse);

    // Granted again.
    permissions = ['edit_global_moods'];
    await restarted.refreshPermissions([base()]);
    expect(restarted.hasPermission(Account.editGlobalMoods), isTrue);

    await restarted.logOut([base()]);
    expect(restarted.hasPermission(Account.editGlobalMoods), isFalse);
  });

  test('permissions the phone does not know are ignored', () async {
    permissions = [
      'edit_global_moods',
      'apply_corrections',
      'not_invented_yet',
    ];
    final account = Account();
    await account.load();
    await account.logIn([base()], 'Owner', 'tajne1');
    expect(account.loggedIn, isTrue);
    expect(account.hasPermission(Account.editGlobalMoods), isTrue);

    await account.refreshPermissions([base()]);
    expect(account.loggedIn, isTrue);
    expect(account.hasPermission(Account.editGlobalMoods), isTrue);
  });
}
