import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a place showed with its cover, besides the picture.
typedef _Extras = ({Color? color, String? title, String? subtitle});

const _Extras _noExtras = (color: null, title: null, subtitle: null);

/// A cover remembered for [StartupCovers]: its image file, the song it was the cover of, the
/// seed its filter was drawn with and, for the mini player, its main colour, for Home's cards
/// their texts.
class StartupCover {
  const StartupCover(
    this.file,
    this.check,
    this.seed, {
    this.snapshot = false,
    this.color,
    this.title,
    this.subtitle,
  });

  final File file;

  /// What the place showed it for ([StartupCovers.of] compares it).
  final String check;
  final String seed;

  /// A picture of the cover as it was drawn (a collage, a picked cover; its filter already on):
  /// shown as it is.
  final bool snapshot;
  final Color? color;

  /// A Home card's title and subtitle as shown, for its row still being read at start.
  final String? title;
  final String? subtitle;

  _Extras get _extras => (color: color, title: title, subtitle: subtitle);

  StartupCover _withExtras(_Extras extras) => StartupCover(
    file,
    check,
    seed,
    snapshot: snapshot,
    color: extras.color,
    title: extras.title,
    subtitle: extras.subtitle,
  );

  Map<String, Object?> toJson() => {
    'file': file.path,
    'check': check,
    'seed': seed,
    if (snapshot) 'snapshot': true,
    if (color case final color?) 'color': color.toARGB32(),
    'title': ?title,
    'subtitle': ?subtitle,
  };

  static StartupCover fromJson(Map<String, Object?> json) => StartupCover(
    File(json['file']! as String),
    json['check']! as String,
    json['seed']! as String,
    snapshot: json['snapshot'] == true,
    color: switch (json['color']) {
      final int value => Color(value),
      _ => null,
    },
    title: json['title'] as String?,
    subtitle: json['subtitle'] as String?,
  );
}

/// The covers Home's first cards and the mini player showed, so the next start shows them in
/// its first frames: [AlbumCovers] finds a cover only once it has read its tables and, for
/// Home's songs, music.db has loaded — about two seconds into a start on a slow phone. A file
/// of the cover cache is remembered by its path; a cover read from a song's own file is kept
/// here as a file of its own. Only on this phone; cleared with the cover cache.
class StartupCovers {
  StartupCovers({Future<Directory> Function()? storageRoot})
    : _storageRoot = storageRoot ?? getApplicationSupportDirectory;

  static const _key = 'startup_covers';

  final Future<Directory> Function() _storageRoot;
  Map<String, StartupCover> _covers = {};
  Timer? _saveSoon;

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    _covers = {
      for (final MapEntry(:key, :value)
          in (jsonDecode(raw) as Map).cast<String, Object?>().entries)
        key: StartupCover.fromJson((value! as Map).cast()),
    };
  }

  /// What [slot] showed last time, when it shows the same song ([check]) now.
  StartupCover? of(String slot, String check) {
    final cover = _covers[slot];
    return cover?.check == check ? cover : null;
  }

  /// What [slot] showed last time, whichever song it was: for a place whose song isn't known
  /// yet.
  StartupCover? at(String slot) => _covers[slot];

  /// [image] as [slot]'s cover for [check]'s song, drawn with [seed] — or, with [snapshot], a
  /// picture of the cover as drawn.
  Future<void> remember(
    String slot,
    String check,
    ImageProvider image,
    String seed, {
    bool snapshot = false,
  }) async {
    final known = _covers[slot];
    final ownFile = known != null && await _isOwn(known.file);
    final File file;
    switch (image) {
      case FileImage(file: final cached):
        if (known?.file.path == cached.path &&
            known?.check == check &&
            known?.seed == seed) {
          return;
        }
        file = cached;
      case MemoryImage(:final bytes):
        // Taken as the same picture: the place shows the same song as before.
        if (ownFile && known.check == check && known.seed == seed) return;
        final dir = await _dir();
        file = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.img');
        await file.writeAsBytes(bytes, flush: true);
      default:
        return;
    }
    if (ownFile && known.file.path != file.path) await _delete(known.file);
    final early = _early.remove(slot);
    _covers[slot] = StartupCover(file, check, seed, snapshot: snapshot)
        ._withExtras(
          early?.check == check
              ? early!.extras
              : known?.check == check
              ? known!._extras
              : _noExtras,
        );
    _save();
  }

  /// What came for a slot before its cover was remembered, for [remember].
  final _early = <String, ({String check, _Extras extras})>{};

  /// The main colour of [slot]'s cover for [check]'s song.
  void rememberColor(String slot, String check, Color? color) =>
      _rememberExtras(
        slot,
        check,
        (e) => (color: color, title: e.title, subtitle: e.subtitle),
      );

  /// The texts of [slot]'s card for [check]'s song.
  void rememberTexts(
    String slot,
    String check,
    String title,
    String subtitle,
  ) => _rememberExtras(
    slot,
    check,
    (e) => (color: e.color, title: title, subtitle: subtitle),
  );

  void _rememberExtras(
    String slot,
    String check,
    _Extras Function(_Extras) change,
  ) {
    final known = _covers[slot];
    if (known == null || known.check != check) {
      final early = _early[slot];
      _early[slot] = (
        check: check,
        extras: change(early?.check == check ? early!.extras : _noExtras),
      );
      return;
    }
    final extras = change(known._extras);
    if (extras == known._extras) return;
    _covers[slot] = known._withExtras(extras);
    _save();
  }

  Future<void> clear() async {
    _covers = {};
    _early.clear();
    _saveSoon?.cancel();
    await (await SharedPreferences.getInstance()).remove(_key);
    final dir = await _dir();
    await for (final file in dir.list()) {
      if (file is File) await _delete(file);
    }
  }

  void _save() {
    _saveSoon?.cancel();
    // A screen of covers comes at once: saved together.
    _saveSoon = Timer(
      const Duration(milliseconds: 500),
      () => _write().catchError(
        (Object e) => debugPrint('Saving the start-up covers failed: $e'),
      ),
    );
  }

  Future<void> _write() async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({
          for (final MapEntry(:key, :value) in _covers.entries)
            key: value.toJson(),
        }),
      );

  Future<Directory> _dir() async =>
      Directory('${(await _storageRoot()).path}/startup_covers')
          .create(recursive: true);

  Future<bool> _isOwn(File file) async =>
      file.parent.path == (await _dir()).path;

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Deleting a start-up cover failed: $e');
    }
  }

  /// Saves now what would be saved in a moment.
  @visibleForTesting
  Future<void> flush() async {
    if (_saveSoon?.isActive != true) return;
    _saveSoon!.cancel();
    await _write();
  }
}
