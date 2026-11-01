import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'download_files.dart';
import 'song_catalog.dart';

/// One file of MusicDatabase's music library downloaded with "Pobierz".
class ServerDownload {
  const ServerDownload({
    required this.fileId,
    required this.file,
    required this.sizeBytes,
    required this.downloadedAt,
  });

  /// files.db's `files.id`.
  final int fileId;
  final File file;
  final int sizeBytes;
  final DateTime downloadedAt;
}

/// Songs from MusicDatabase's music library ([ServerFile], streamed from `GET /library/<id>`,
/// ADR 0010) kept on the phone with "Pobierz", so they play without the server: the files in
/// `<support dir>/downloads/` as `<files.id>.<ext>`, or in the user's [folder] as
/// `Artist - Title.<ext>`, listed in `local.db`'s `server_downloads` (tables created by `LocalLibrary`;
/// `file_name` is a full path for a file in the user's folder). Unlike the YouTube cache there's
/// no limit — only what the user picked.
class ServerDownloads extends ChangeNotifier {
  ServerDownloads(
    this._database, {
    Future<Directory> Function()? storageRoot,
    String? Function()? folder,
    DateTime Function()? now,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _folder = folder ?? (() => null),
       _now = now ?? DateTime.now;

  final Future<Database> Function() _database;
  final Future<Directory> Function() _storageRoot;

  /// The user's folder for downloads, `null` for the app's own.
  final String? Function() _folder;
  final DateTime Function() _now;

  Map<int, ServerDownload> _downloads = const {};
  final _inFlight = <int, Future<bool>>{};

  Future<Directory> _dir() async =>
      Directory('${(await _storageRoot()).path}/downloads')
          .create(recursive: true);

  List<ServerDownload> get entries => [..._downloads.values];
  int get totalBytes =>
      _downloads.values.fold(0, (sum, d) => sum + d.sizeBytes);

  bool isDownloaded(int fileId) => _downloads.containsKey(fileId);

  /// The downloaded copy of [fileId], `null` when there's none (or it's gone from the disk).
  Future<File?> fileFor(int fileId) async {
    final download = _downloads[fileId];
    if (download == null) return null;
    if (await download.file.exists()) return download.file;
    await load();
    return null;
  }

  Future<void> load() async {
    final db = await _database();
    final dir = await _dir();
    final found = <int, ServerDownload>{};
    for (final row in await db.query('server_downloads')) {
      final download = ServerDownload(
        fileId: row['file_id']! as int,
        file: _fileNamed(dir, row['file_name']! as String),
        sizeBytes: row['size_bytes']! as int,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(
          row['downloaded_at']! as int,
        ),
      );
      if (await download.file.exists()) {
        found[download.fileId] = download;
      } else if (!await download.file.parent.exists()) {
        // The user's folder out of reach (an SD card taken out): kept for when it's back.
      } else {
        await db.delete(
          'server_downloads',
          where: 'file_id = ?',
          whereArgs: [download.fileId],
        );
      }
    }
    _downloads = found;
    notifyListeners();
    // Left over from downloads that stopped half-way.
    await for (final file in dir.list()) {
      if (file is File && file.path.endsWith('.part')) await file.delete();
    }
  }

  static File _fileNamed(Directory dir, String name) =>
      File(name.startsWith('/') ? name : '${dir.path}/$name');

  /// What `file_name` says for [file]: a full path outside the app's own folder.
  static String _nameFor(Directory dir, File file) =>
      file.parent.path == dir.path ? file.uri.pathSegments.last : file.path;

  /// Saves [file] from the first of [uris] (its `/library/<id>` on each server address) that
  /// sends it; whether it's on the phone now. [name] ("Artist - Title") names it in the user's
  /// folder. A second call for the same file waits for the first.
  Future<bool> download(ServerFile file, List<Uri> uris, {String? name}) async {
    if (isDownloaded(file.id)) return true;
    return _inFlight[file.id] ??= _download(file, uris, name).whenComplete(() {
      // A block: `=> remove(…)` would return this very future, which then waits for itself.
      _inFlight.remove(file.id);
    });
  }

  Future<bool> _download(ServerFile file, List<Uri> uris, String? name) async {
    final dir = await _dir();
    final extension = fileExtension(file.fileName);
    // Written in the app's folder, so the user's never shows a half-done file.
    final part = File('${dir.path}/${file.id}$extension.part');
    for (final uri in uris) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final response = await (await client.getUrl(uri))
            .close()
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          continue;
        }
        // Not openWrite(): its errors escape the try/catch (as in YouTubeLibrary.download).
        final out = await part.open(mode: FileMode.write);
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 30),
          )) {
            await out.writeFrom(chunk);
          }
        } finally {
          await out.close();
        }
        final target = await moveFile(
          part,
          await _target(dir, file.id, extension, name),
        );
        final db = await _database();
        await db.insert('server_downloads', {
          'file_id': file.id,
          'file_name': _nameFor(dir, target),
          'size_bytes': await target.length(),
          'downloaded_at': _now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await load();
        await announceMediaFiles([
          if (target.parent.path != dir.path) target.path,
        ]);
        return true;
      } catch (e) {
        debugPrint('Downloading server file ${file.id} from $uri failed: $e');
        if (await part.exists()) await part.delete();
      } finally {
        client.close(force: true);
      }
    }
    return false;
  }

  /// Where a download of [fileId] goes now.
  Future<File> _target(
    Directory dir,
    int fileId,
    String extension,
    String? name,
  ) async {
    final folder = _folder();
    if (folder == null) return File('${dir.path}/$fileId$extension');
    return freeFileIn(Directory(folder), name ?? '$fileId', extension);
  }

  /// Moves every download not where [ServerDownloads.download] puts them now there, [nameOf]
  /// naming them in the user's folder; returns how many couldn't be moved (they stay usable
  /// where they are). [onMoved] after each.
  Future<int> relocate(
    String? Function(int fileId) nameOf, {
    void Function()? onMoved,
  }) async {
    final dir = await _dir();
    final wanted = _folder() ?? dir.path;
    final db = await _database();
    final announced = <String>[];
    var failed = 0;
    for (final download in entries) {
      if (download.file.parent.path == wanted) {
        onMoved?.call();
        continue;
      }
      try {
        final target = await moveFile(
          download.file,
          await _target(
            dir,
            download.fileId,
            fileExtension(download.file.path),
            nameOf(download.fileId),
          ),
        );
        await db.update(
          'server_downloads',
          {'file_name': _nameFor(dir, target)},
          where: 'file_id = ?',
          whereArgs: [download.fileId],
        );
        announced.addAll([download.file.path, target.path]);
      } catch (e) {
        debugPrint('Moving server file ${download.fileId} failed: $e');
        failed++;
      }
      onMoved?.call();
    }
    await load();
    await announceMediaFiles([
      for (final path in announced)
        if (!isInFolder(path, dir.path)) path,
    ]);
    return failed;
  }

  /// Takes [fileId]'s copy off the phone.
  Future<void> remove(int fileId) async {
    final download = _downloads[fileId];
    if (download == null) return;
    if (await download.file.exists()) await download.file.delete();
    final dir = await _dir();
    if (download.file.parent.path != dir.path) {
      await announceMediaFiles([download.file.path]);
    }
    await (await _database()).delete(
      'server_downloads',
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
    await load();
  }
}
