import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/play_history.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/screens/recents_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('plays are kept in local.db, newest first', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('play_history_test');
    final sync = DatabaseSync(storageRoot: () async => root);
    final catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    final library = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    var clock = DateTime(2026, 10, 11, 12);
    final history = PlayHistory(library.database, now: () => clock);
    await history.load();
    expect(history.entries, isEmpty);

    await history.record(const TrackRef(title: 'A', videoId: 'v1'));
    clock = clock.add(const Duration(minutes: 3));
    await history.record(
      const TrackRef(title: 'B', mainDbId: 5),
      playlistId: 2,
      playlistName: 'Do auta',
    );

    final again = PlayHistory(library.database);
    await again.load();
    expect([for (final e in again.entries) e.track.title], ['B', 'A']);
    expect(again.entries.first.playlistName, 'Do auta');
    expect(again.entries.last.track.videoId, 'v1');

    history.dispose();
    again.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  test('plays older than the chosen days go; clearing empties it', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('play_history_test');
    final sync = DatabaseSync(storageRoot: () async => root);
    final catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    final library = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    var clock = DateTime(2026, 1, 1);
    final history = PlayHistory(library.database, now: () => clock);
    await history.load();
    expect(history.keepDays, PlayHistory.defaultKeepDays);

    await history.record(const TrackRef(title: 'stary', videoId: 'a'));
    clock = DateTime(2026, 3, 1);
    await history.record(const TrackRef(title: 'nowy', videoId: 'b'));
    await history.setKeepDays(30);
    expect([for (final e in history.entries) e.track.title], ['nowy']);

    // Still gone after a restart, and the choice is remembered.
    final again = PlayHistory(library.database, now: () => clock);
    await again.load();
    expect((again.keepDays, again.entries.length), (30, 1));

    await again.clear();
    expect(again.entries, isEmpty);
    final empty = PlayHistory(library.database, now: () => clock);
    await empty.load();
    expect(empty.entries, isEmpty);

    for (final h in [history, again, empty]) {
      h.dispose();
    }
    library.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  group('"Ostatnie" grouping', () {
    final now = DateTime(2026, 10, 11, 18);
    PlayedTrack play(String title, DateTime at, {int? playlist}) => PlayedTrack(
      track: TrackRef(title: title, videoId: title),
      playedAt: at,
      playlistId: playlist,
      playlistName: playlist == null ? null : 'P$playlist',
    );

    test('by day; each song once a day, per playlist it came from', () {
      final days = groupRecents([
        play('c', DateTime(2026, 10, 11, 17)),
        play('b', DateTime(2026, 10, 11, 16)),
        play('c', DateTime(2026, 10, 11, 15)),
        play('p2', DateTime(2026, 10, 11, 14), playlist: 1),
        play('p1', DateTime(2026, 10, 11, 13), playlist: 1),
        play('c', DateTime(2026, 10, 11, 12), playlist: 1),
        play('y', DateTime(2026, 10, 10, 20)),
        play('old', DateTime(2026, 10, 5, 20)),
        play('older', DateTime(2025, 12, 24, 20)),
      ], now);
      expect(
        [for (final d in days) d.label],
        ['Dzisiaj', 'Wczoraj', '5 października', '24 grudnia 2025'],
      );
      expect(
        [for (final p in days.first.plays) (p.track.title, p.playlistId)],
        [('c', null), ('b', null), ('p2', 1), ('p1', 1), ('c', 1)],
      );
    });
  });
}
