import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
/// `<support dir>/downloads/`, listed in `local.db`'s `server_downloads` (tables created by
/// `LocalLibrary`). Unlike the YouTube cache there's no limit — only what the user picked.
class ServerDownloads extends ChangeNotifier {
  ServerDownloads(
    this._database, {
    Future<Directory> Function()? storageRoot,
    DateTime Function()? now,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final Future<Database> Function() _database;
  final Future<Directory> Function() _storageRoot;
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
        file: File('${dir.path}/${row['file_name']}'),
        sizeBytes: row['size_bytes']! as int,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(
          row['downloaded_at']! as int,
        ),
      );
      if (await download.file.exists()) {
        found[download.fileId] = download;
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

  /// Saves [file] from the first of [uris] (its `/library/<id>` on each server address) that
  /// sends it; whether it's on the phone now. A second call for the same file waits for the
  /// first.
  Future<bool> download(ServerFile file, List<Uri> uris) async {
    if (isDownloaded(file.id)) return true;
    return _inFlight[file.id] ??= _download(file, uris).whenComplete(() {
      // A block: `=> remove(…)` would return this very future, which then waits for itself.
      _inFlight.remove(file.id);
    });
  }

  Future<bool> _download(ServerFile file, List<Uri> uris) async {
    final dot = file.fileName.lastIndexOf('.');
    final name = '${file.id}${dot < 0 ? '' : file.fileName.substring(dot)}';
    final target = File('${(await _dir()).path}/$name');
    final part = File('${target.path}.part');
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
        await part.rename(target.path);
        final db = await _database();
        await db.insert('server_downloads', {
          'file_id': file.id,
          'file_name': name,
          'size_bytes': await target.length(),
          'downloaded_at': _now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await load();
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

  /// Takes [fileId]'s copy off the phone.
  Future<void> remove(int fileId) async {
    final download = _downloads[fileId];
    if (download == null) return;
    if (await download.file.exists()) await download.file.delete();
    await (await _database()).delete(
      'server_downloads',
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
    await load();
  }
}
