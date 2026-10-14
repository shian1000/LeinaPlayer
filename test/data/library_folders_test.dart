import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/library_folders.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlaylistSummary _playlist(
  int id,
  String name, {
  required int created,
  required int updated,
  String? owner,
}) => PlaylistSummary(
  id: id,
  name: name,
  owner: owner,
  trackCount: 0,
  duration: Duration.zero,
  createdAt: DateTime(2026, 1, created),
  updatedAt: DateTime(2026, 2, updated),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final playlists = [
    _playlist(1, 'Żeglarskie', created: 1, updated: 5, owner: 'Bartek'),
    _playlist(2, 'ambient', created: 3, updated: 1),
    _playlist(3, 'Ballady', created: 2, updated: 3, owner: 'Ania'),
  ];

  List<String> names(List<LibraryEntry> entries) => [
    for (final e in entries) e.name,
  ];

  test(
    'each order: opened or changed last, added last, by name (accents and case '
    'aside), by creator',
    () async {
      var now = DateTime(2026, 3, 1);
      final folders = LibraryFolders(now: () => now);
      await folders.load();

      List<String> sortedBy(LibrarySort sort) {
        folders.setSort(sort);
        return names(folders.entries(playlists: playlists, moods: const []));
      }

      expect(sortedBy(LibrarySort.recent), [
        'Żeglarskie',
        'Ballady',
        'ambient',
      ]);
      await folders.opened(LibraryFolders.playlistKey(2));
      expect(sortedBy(LibrarySort.recent), [
        'ambient',
        'Żeglarskie',
        'Ballady',
      ]);
      expect(sortedBy(LibrarySort.added), ['ambient', 'Ballady', 'Żeglarskie']);
      expect(sortedBy(LibrarySort.alphabetical), [
        'ambient',
        'Ballady',
        'Żeglarskie',
      ]);
      // Made on the phone: "Ty".
      expect(sortedBy(LibrarySort.creator), [
        'Ballady',
        'Żeglarskie',
        'ambient',
      ]);

      // A folder: first by creator, by its newest item for "Ostatnie".
      final folder = await folders.create(' Stare ');
      await folders.move(LibraryFolders.playlistKey(3), folder.id);
      expect(folder.name, 'Stare');
      expect(sortedBy(LibrarySort.creator), ['Stare', 'Żeglarskie', 'ambient']);
      now = DateTime(2026, 4, 1);
      await folders.opened(LibraryFolders.playlistKey(3));
      expect(sortedBy(LibrarySort.recent), ['Stare', 'ambient', 'Żeglarskie']);
    },
  );

  test('an item is in one folder at a time; deleting a folder lets its items out; all of '
      'it is kept', () async {
    final folders = LibraryFolders();
    await folders.load();
    final a = await folders.create('A');
    final b = await folders.create('B');
    final key = LibraryFolders.playlistKey(1);

    await folders.move(key, a.id);
    await folders.move(key, b.id);
    expect(folders.folderOf(key)?.id, b.id);
    expect(folders.byId(a.id)!.items, isEmpty);

    final top = folders.entries(playlists: playlists, moods: const []);
    expect(names(top), containsAll(['A', 'B', 'ambient', 'Ballady']));
    expect(names(top), isNot(contains('Żeglarskie')));
    final inB = top.whereType<FolderEntry>().firstWhere((f) => f.name == 'B');
    expect(names(inB.contents), ['Żeglarskie']);
    // A filter's flat list: every playlist, no folders.
    expect(
      names(
        folders.entries(
          playlists: playlists,
          moods: const [],
          withFolders: false,
        ),
      ),
      hasLength(3),
    );

    await folders.rename(a.id, 'Nowe');
    await folders.setSort(LibrarySort.added);
    final reloaded = LibraryFolders();
    await reloaded.load();
    expect([for (final f in reloaded.folders) f.name], ['Nowe', 'B']);
    expect(reloaded.folderOf(key)?.id, b.id);
    expect(reloaded.sort, LibrarySort.added);

    await reloaded.delete(b.id);
    expect(reloaded.folderOf(key), isNull);
    expect(
      names(reloaded.entries(playlists: playlists, moods: const [])),
      contains('Żeglarskie'),
    );
  });
}
