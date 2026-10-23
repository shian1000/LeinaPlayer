import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'local_library.dart';

/// "Kopia zapasowa" (sharing checklist 4.1): everything the user made on the phone in one `.zip`
/// they keep themselves (sent through the share sheet: Drive, e-mail, a computer) and restore
/// from on this or another phone — for people without a MusicDatabase account, whose data
/// otherwise lives only on the phone. No connection of its own.
///
/// In the file: `local.db` without what only caches (covers, YouTube audio, "Pobierz" — their
/// files aren't in the backup), the outbox, picked covers, the settings without secrets and
/// this phone's own state ([keptKeys]), and the links saved "Na później" (`LaterLinks.kt`).
///
/// A restore can't swap files the app has open, so [stage] only unpacks the backup next to
/// them (the links, held natively, go in at once) and the app closes; [applyPending], first
/// thing on the next start, puts the rest in place.
class UserBackup extends ChangeNotifier {
  UserBackup({
    Future<Directory> Function()? storageRoot,
    this.factoryOverride,
    DateTime Function()? now,
    LaterLinksFiles? laterLinks,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _laterLinks = laterLinks ?? const LaterLinksFiles();

  static const format = 'leina-radio-backup';
  static const formatVersion = 1;

  static const _lastExportKey = 'backup.last_export_ms';
  static const _restoredFromKey = 'backup.restored_from_ms';

  /// Never in a backup, and kept as they are on the phone a backup is restored on: secrets
  /// (the backup may go through Drive or e-mail), the login that goes with them, and what only
  /// describes this phone's copy of MusicDatabase's files or its update check.
  static const keptKeys = {
    'account.token',
    'account.password',
    'account.user_name',
    'account.permissions',
    'youtube_account.email',
    'youtube.api_key',
    'spotify.client_id',
    'spotify.client_secret',
    'database_sync.last_sync_ms',
    'database_sync.last_source',
    'database_sync.server_empty',
    'local_music.last_scan_ms',
    'updates.last_check_ms',
    'updates.latest',
    'updates.dismissed_build',
  };

  static bool _kept(String key) =>
      keptKeys.contains(key) || key.startsWith('backup.');

  /// Rows that point at files left out of the backup (they'd be missing after a restore).
  static const _cacheTables = [
    'cover_cache',
    'youtube_cache',
    'server_downloads',
    'download_queue',
  ];

  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;
  final LaterLinksFiles _laterLinks;

  /// SQLite implementation to use instead of sqflite's global one (tests use FFI).
  final DatabaseFactory? factoryOverride;

  DateTime? _lastExport;
  DateTime? _restoredFrom;
  bool _busy = false;

  DateTime? get lastExport => _lastExport;

  /// When the backup last restored on this phone was made.
  DateTime? get restoredFrom => _restoredFrom;

  bool get busy => _busy;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? at(String key) {
      final ms = prefs.getInt(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    _lastExport = at(_lastExportKey);
    _restoredFrom = at(_restoredFromKey);
    notifyListeners();
  }

  /// Makes the backup from [localDb] (the open `local.db`, so its own lock keeps writes out
  /// while it's copied). Only the newest backup is kept on the phone.
  Future<File> export(Database localDb) async {
    _setBusy(true);
    try {
      final root = await _storageRoot();
      final work = Directory('${root.path}/backup_work');
      if (await work.exists()) await work.delete(recursive: true);
      await work.create(recursive: true);
      try {
        final archive = Archive();
        final dbCopy = File('${work.path}/local.db');
        await _copyDatabase(localDb, dbCopy);
        await _dropCaches(dbCopy);
        archive.addFile(
          ArchiveFile.bytes('local.db', await dbCopy.readAsBytes()),
        );
        for (final folder in _folders) {
          await _addFolder(archive, Directory('${root.path}/$folder'), folder);
        }
        final now = _now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        archive.addFile(
          ArchiveFile.string(
            'backup.json',
            const JsonEncoder.withIndent(' ').convert({
              'format': format,
              'version': formatVersion,
              'created_at': now.millisecondsSinceEpoch,
              'local_db_version': LocalLibrary.schemaVersion,
              'preferences': {
                for (final key in prefs.getKeys().toList()..sort())
                  if (!_kept(key)) key: _encode(prefs.get(key)),
              },
              'later_links': await _laterLinks.read(),
            }),
          ),
        );
        final out = Directory('${root.path}/backup');
        if (await out.exists()) await out.delete(recursive: true);
        await out.create(recursive: true);
        final zip = File('${out.path}/leina-radio-kopia-${_stamp(now)}.zip');
        await zip.writeAsBytes(ZipEncoder().encodeBytes(archive));
        await prefs.setInt(_lastExportKey, now.millisecondsSinceEpoch);
        _lastExport = now;
        return zip;
      } finally {
        await work.delete(recursive: true);
      }
    } finally {
      _setBusy(false);
    }
  }

  /// What's restored besides `local.db` and the settings, as folders of the app's storage.
  static const _folders = ['outbox', 'custom_covers'];

  static Future<void> _copyDatabase(Database db, File to) async {
    // A WAL file's changes go into the database first (no-op in the default journal mode).
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.transaction((txn) async {
      await File(db.path).copy(to.path);
    });
  }

  Future<void> _dropCaches(File copy) async {
    final db = await (factoryOverride ?? databaseFactory).openDatabase(
      copy.path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final tables = {
        for (final row in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name'],
      };
      for (final table in _cacheTables) {
        if (tables.contains(table)) await db.delete(table);
      }
      await db.execute('VACUUM');
    } finally {
      await db.close();
    }
  }

  static Future<void> _addFolder(
    Archive archive,
    Directory dir,
    String prefix,
  ) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(dir.path.length + 1);
      archive.addFile(
        ArchiveFile.bytes('$prefix/$relative', await entity.readAsBytes()),
      );
    }
  }

  static Map<String, Object?> _encode(Object? value) => switch (value) {
    bool v => {'bool': v},
    int v => {'int': v},
    double v => {'double': v},
    String v => {'string': v},
    List v => {'list': v.cast<String>()},
    _ => {'null': null},
  };

  /// What the backup in [bytes] is, before asking whether to restore it; throws
  /// [BackupException] (with a Polish message) when it isn't one this version can restore.
  static BackupInfo inspect(List<int> bytes) => _read(bytes).info;

  static ({Archive archive, Map<String, Object?> json, BackupInfo info}) _read(
    List<int> bytes,
  ) {
    const notBackup = BackupException(
      'To nie jest plik kopii zapasowej Leina Radio.',
    );
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      debugPrint('Reading a backup failed: $e');
      throw notBackup;
    }
    final manifest = archive.findFile('backup.json');
    if (manifest == null || archive.findFile('local.db') == null) {
      throw notBackup;
    }
    final Map<String, Object?> json;
    try {
      json = jsonDecode(utf8.decode(manifest.content)) as Map<String, Object?>;
    } catch (e) {
      debugPrint('Reading the manifest of a backup failed: $e');
      throw const BackupException('Plik kopii zapasowej jest uszkodzony.');
    }
    if (json['format'] != format) throw notBackup;
    if ((json['version'] as int? ?? 0) > formatVersion ||
        (json['local_db_version'] as int? ?? 0) > LocalLibrary.schemaVersion) {
      throw const BackupException(
        'Kopia pochodzi z nowszej wersji aplikacji. Zaktualizuj Leina Radio '
        'i spróbuj ponownie.',
      );
    }
    return (archive: archive, json: json, info: BackupInfo.of(json));
  }

  /// Unpacks the backup in [bytes] to be put in place on the next start; throws
  /// [BackupException] like [inspect].
  Future<BackupInfo> stage(List<int> bytes) async {
    _setBusy(true);
    try {
      final (:archive, :json, :info) = _read(bytes);
      final pending = await _pendingDir();
      if (await pending.exists()) await pending.delete(recursive: true);
      await pending.create(recursive: true);
      for (final entry in archive) {
        if (!entry.isFile || !_safeName(entry.name)) continue;
        final out = File('${pending.path}/${entry.name}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content);
      }
      // Now rather than on the next start: Android may start Dart then before the activity
      // answers the links channel. The app closes right after, before it could save over them.
      final links = json['later_links'] as String?;
      if (links != null) await _laterLinks.write(links);
      return info;
    } finally {
      _setBusy(false);
    }
  }

  /// Only names [export] writes: nothing that climbs out of the folder it's unpacked to.
  static bool _safeName(String name) =>
      !name.startsWith('/') &&
      !name.split('/').any((part) => part == '..' || part.isEmpty) &&
      (name == 'backup.json' ||
          name == 'local.db' ||
          _folders.any((f) => name.startsWith('$f/')));

  Future<Directory> _pendingDir() async =>
      Directory('${(await _storageRoot()).path}/backup_restore');

  /// Puts a backup [stage]d before the app closed in place of the phone's data; called in
  /// `main` before anything opens it. Returns whether there was one.
  Future<bool> applyPending() async {
    final pending = await _pendingDir();
    final manifest = File('${pending.path}/backup.json');
    if (!await manifest.exists()) return false;
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    final root = await _storageRoot();
    // Each step leaves the pending copy only once it's in place, so one interrupted (the app
    // killed) is done again on the next start.
    final db = File('${pending.path}/local.db');
    if (await db.exists()) {
      final local = await Directory('${root.path}/local')
          .create(recursive: true);
      for (final suffix in ['', '-journal', '-wal', '-shm']) {
        final old = File('${local.path}/local.db$suffix');
        if (await old.exists()) await old.delete();
      }
      await db.rename('${local.path}/local.db');
    }
    for (final folder in _folders) {
      final target = Directory('${root.path}/$folder');
      final from = Directory('${pending.path}/$folder');
      final done = File('${pending.path}/$folder.done');
      if (await done.exists()) continue;
      if (await target.exists()) await target.delete(recursive: true);
      if (await from.exists()) await from.rename(target.path);
      await done.create();
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = (json['preferences'] as Map<String, Object?>? ?? const {});
    for (final key in prefs.getKeys().toList()) {
      if (!_kept(key) && !stored.containsKey(key)) await prefs.remove(key);
    }
    for (final MapEntry(:key, :value) in stored.entries) {
      if (_kept(key)) continue;
      final typed = (value as Map<String, Object?>).entries.single;
      switch (typed.key) {
        case 'bool':
          await prefs.setBool(key, typed.value! as bool);
        case 'int':
          await prefs.setInt(key, typed.value! as int);
        case 'double':
          await prefs.setDouble(key, (typed.value! as num).toDouble());
        case 'string':
          await prefs.setString(key, typed.value! as String);
        case 'list':
          await prefs.setStringList(key, (typed.value! as List).cast<String>());
        default:
          await prefs.remove(key);
      }
    }
    final created = BackupInfo.of(json).createdAt;
    await prefs.setInt(_restoredFromKey, created.millisecondsSinceEpoch);
    _restoredFrom = created;
    await pending.delete(recursive: true);
    return true;
  }

  void _setBusy(bool busy) {
    _busy = busy;
    notifyListeners();
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}';
  }
}

/// What a backup file says about itself, shown before it's restored.
class BackupInfo {
  const BackupInfo({required this.createdAt});

  factory BackupInfo.of(Map<String, Object?> json) => BackupInfo(
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      json['created_at'] as int? ?? 0,
    ),
  );

  final DateTime createdAt;
}

class BackupException implements Exception {
  const BackupException(this.message);

  /// In Polish, for display.
  final String message;

  @override
  String toString() => message;
}

/// The links saved "Na później", kept natively (`LaterLinks.kt`) as one JSON text; off Android
/// (tests) there are none.
class LaterLinksFiles {
  const LaterLinksFiles();

  static const _channel = MethodChannel('music_database_app/links');

  Future<String?> read() async {
    try {
      return await _channel.invokeMethod<String>('laterLinks');
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> write(String json) async {
    try {
      await _channel.invokeMethod<void>('replaceLaterLinks', json);
    } on MissingPluginException {
      debugPrint('No native store for links saved for later');
    }
  }
}

/// Makes the [UserBackup] reachable from any screen.
class UserBackupScope extends InheritedNotifier<UserBackup> {
  const UserBackupScope({
    super.key,
    required UserBackup super.notifier,
    required super.child,
  });

  static UserBackup of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserBackupScope>()!.notifier!;
}
