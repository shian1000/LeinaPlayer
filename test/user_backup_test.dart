import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/user_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeLaterLinks implements LaterLinksFiles {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String json) async => stored = json;
}

/// One phone: its own storage folder and `local.db`.
class _Phone {
  _Phone(this.root)
    : sync = DatabaseSync(storageRoot: () async => root),
      links = _FakeLaterLinks() {
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    library = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    backup = UserBackup(
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
      now: () => DateTime(2026, 10, 23, 14, 5),
      laterLinks: links,
    );
  }

  final Directory root;
  final DatabaseSync sync;
  final _FakeLaterLinks links;
  late final SongCatalog catalog;
  late final LocalLibrary library;
  late final UserBackup backup;

  void dispose() {
    backup.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
  }
}

void main() {
  sqfliteFfiInit();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('user_backup_test');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<File> makeBackup() async {
    SharedPreferences.setMockInitialValues({
      'appearance.dark_mode': true,
      'playback.crossfade_seconds': 4,
      'library.folders': '[]',
      'search.fields': ['title', 'artist'],
      'account.token': 'secret-token',
      'account.user_name': 'tester',
      'youtube.api_key': 'AIza-secret',
      'database_sync.last_sync_ms': 1,
    });
    final phone = _Phone(await Directory('${temp.path}/old').create());
    final db = await phone.library.database();
    await db.insert('playlists', {
      'name': 'Do auta',
      'uid': 'p1',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('playlist_tracks', {
      'playlist_id': 1,
      'position': 0,
      'title': 'Chromatic',
      'main_db_id': 4601,
    });
    await db.insert('youtube_cache', {
      'video_id': 'v1',
      'file_name': 'v1.m4a',
      'size_bytes': 10,
      'downloaded_at': 1,
      'last_played_at': 1,
    });
    await db.insert('youtube_matches', {
      'main_db_id': 4602,
      'video_id': 'ad5ukUkNjgw',
      'matched_at': 1,
    });
    await File('${phone.root.path}/outbox/1_found_youtube_links.db')
        .create(recursive: true);
    File('${phone.root.path}/custom_covers/${'a' * 64}.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    await File('${phone.root.path}/youtube_cache/v1.m4a')
        .create(recursive: true);
    phone.links.stored = '{"people":[{"id":"x","name":"Ola"}],"links":[]}';

    final file = await phone.backup.export(db);
    expect(phone.backup.lastExport, DateTime(2026, 10, 23, 14, 5));
    final copy = await file.copy('${temp.path}/kopia.zip');
    phone.dispose();
    return copy;
  }

  test(
    'a backup restored on another phone brings back its data, not its secrets',
    () async {
      final file = await makeBackup();
      expect(file.path, endsWith('kopia.zip'));
      final bytes = await file.readAsBytes();
      expect(
        UserBackup.inspect(bytes).createdAt,
        DateTime(2026, 10, 23, 14, 5),
      );

      // The other phone, already used: its own settings, login and a playlist of its own.
      SharedPreferences.setMockInitialValues({
        'appearance.dark_mode': false,
        'covers.order': 'itunes',
        'account.token': 'new-phone-token',
        'account.user_name': 'other',
        'database_sync.last_sync_ms': 99,
      });
      var phone = _Phone(await Directory('${temp.path}/new').create());
      final before = await phone.library.database();
      await before.insert('playlists', {
        'name': 'Stara',
        'uid': 'p9',
        'created_at': 1,
        'updated_at': 1,
      });

      await phone.backup.stage(bytes);
      expect(phone.links.stored, contains('Ola'));
      // The app closes; next start.
      final links = phone.links;
      phone.dispose();
      await Future<void>.delayed(Duration.zero);
      phone = _Phone(phone.root);
      expect(await phone.backup.applyPending(), isTrue);
      expect(await phone.backup.applyPending(), isFalse);

      final db = await phone.library.database();
      expect(
        [for (final r in await db.query('playlists')) r['name']],
        ['Do auta'],
      );
      expect(await db.query('playlist_tracks'), hasLength(1));
      expect(await db.query('youtube_matches'), hasLength(1));
      expect(await db.query('youtube_cache'), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('appearance.dark_mode'), isTrue);
      expect(prefs.getInt('playback.crossfade_seconds'), 4);
      expect(prefs.getStringList('search.fields'), ['title', 'artist']);
      expect(prefs.containsKey('covers.order'), isFalse);
      expect(prefs.getString('account.token'), 'new-phone-token');
      expect(prefs.getString('account.user_name'), 'other');
      expect(prefs.containsKey('youtube.api_key'), isFalse);
      expect(prefs.getInt('database_sync.last_sync_ms'), 99);

      expect(
        File('${phone.root.path}/outbox/1_found_youtube_links.db').existsSync(),
        isTrue,
      );
      expect(
        File('${phone.root.path}/custom_covers/${'a' * 64}.png')
            .readAsBytesSync(),
        [1, 2, 3],
      );
      expect(
        Directory('${phone.root.path}/backup_restore').existsSync(),
        isFalse,
      );
      await phone.backup.load();
      expect(phone.backup.restoredFrom, DateTime(2026, 10, 23, 14, 5));
      expect(links.stored, contains('Ola'));
      phone.dispose();
    },
  );

  test(
    'a file that is not a backup is refused before anything changes',
    () async {
      expect(
        () => UserBackup.inspect([1, 2, 3]),
        throwsA(isA<BackupException>()),
      );
      SharedPreferences.setMockInitialValues({});
      final phone = _Phone(await Directory('${temp.path}/p').create());
      await expectLater(
        phone.backup.stage([1, 2, 3]),
        throwsA(isA<BackupException>()),
      );
      expect(await phone.backup.applyPending(), isFalse);
      phone.dispose();
    },
  );
}
