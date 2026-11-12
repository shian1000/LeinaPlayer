import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/text_normalizer.dart';
import 'package:music_database_app/src/data/version_names.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';
import '../support/waiting.dart';

void main() {
  sqfliteFfiInit();

  group('normalizeForSearch', () {
    test('strips Polish and other diacritics and lowercases', () {
      expect(normalizeForSearch('Zażółć GĘŚLĄ jaźń'), 'zazolc gesla jazn');
      expect(normalizeForSearch('Beyoncé • Motörhead'), 'beyonce motorhead');
    });

    test('drops apostrophes, turns other punctuation into spaces', () {
      expect(normalizeForSearch("Don't Stop (Remix)!"), 'dont stop remix');
      expect(normalizeForSearch('  AC/DC  -  T.N.T. '), 'ac dc t n t');
    });

    test('spells out letters that do not decompose', () {
      expect(
        normalizeForSearch('Straße Œuvre Øresund'),
        'strasse oeuvre oresund',
      );
    });
  });

  group('SongCatalog', () {
    late Directory storage;
    late DatabaseSync sync;
    late SongCatalog catalog;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('song_catalog_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    });

    tearDown(() async {
      catalog.dispose();
      sync.dispose();
      await storage.delete(recursive: true);
    });

    Future<void> loadSample() async {
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
    }

    test('reports a missing database instead of failing', () async {
      await catalog.ensureLoaded();
      expect(catalog.status, CatalogStatus.noDatabase);
      expect(catalog.search('anything'), isEmpty);
    });

    test(
      'reads the videos MusicDatabase found bad; none without the table',
      () async {
        final path = (await sync.localFile('music.db')).path;
        await writeMusicDb(path);
        final before = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
        await before.ensureLoaded();
        expect(before.status, CatalogStatus.ready);
        expect(before.badVideos.everySong, isEmpty);
        expect(before.badVideos.forSong, isEmpty);
        before.dispose();

        final db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('''
        CREATE TABLE bad_youtube_videos (
          id INTEGER PRIMARY KEY, video_id TEXT NOT NULL, song_id INTEGER,
          reason TEXT NOT NULL, marked_at TEXT NOT NULL)''');
        for (final (video, song, reason) in [
          ('gone1234567', null, 'removed'),
          ('wrong123456', 1, 'wrong_for_song'),
          ('wrong654321', 1, 'wrong_for_song'),
        ]) {
          await db.insert('bad_youtube_videos', {
            'video_id': video,
            'song_id': song,
            'reason': reason,
            'marked_at': '2026-10-14T12:00:00+02:00',
          });
        }
        await db.close();
        await catalog.ensureLoaded();

        expect(catalog.badVideos.everySong, {'gone1234567'});
        expect(catalog.badVideos.isWrongFor(1, 'wrong123456'), isTrue);
        expect(catalog.badVideos.isWrongFor(1, 'gone1234567'), isFalse);
        expect(catalog.badVideos.isWrongFor(2, 'wrong123456'), isFalse);
      },
    );

    test('recognises other uploads of a song after its own link; '
        'none without the table', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final before = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      await before.ensureLoaded();
      expect(before.status, CatalogStatus.ready);
      expect(before.findByYouTubeId('live1234567'), isNull);
      before.dispose();

      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('''
        CREATE TABLE additional_youtube_videos (
          video_id TEXT PRIMARY KEY NOT NULL, song_id INTEGER NOT NULL,
          source TEXT NOT NULL, added_at TEXT NOT NULL)''');
      await db.execute('''
        CREATE TABLE bad_youtube_videos (
          id INTEGER PRIMARY KEY, video_id TEXT NOT NULL, song_id INTEGER,
          reason TEXT NOT NULL, marked_at TEXT NOT NULL)''');
      for (final (video, song) in [
        ('live1234567', 1),
        ('topic123456', 3),
        ('X2XWBcd5jn0', 2),
        ('wrong123456', 2),
      ]) {
        await db.insert('additional_youtube_videos', {
          'video_id': video,
          'song_id': song,
          'source': 'folder_playlist',
          'added_at': '2026-10-31 12:00:00',
        });
      }
      await db.insert('bad_youtube_videos', {
        'video_id': 'wrong123456',
        'song_id': 2,
        'reason': 'wrong_for_song',
        'marked_at': '2026-10-31 12:00:00',
      });
      await db.close();
      await catalog.ensureLoaded();

      expect(catalog.findByYouTubeId('live1234567')?.id, 1);
      // An N/A song's uploads are recognised; it still has no link.
      expect(catalog.findByYouTubeId('topic123456')?.id, 3);
      expect(catalog.byId(3)!.youtubeVideoId, isNull);
      // A song's own link wins.
      expect(catalog.findByYouTubeId('X2XWBcd5jn0')?.id, 1);
      expect(catalog.findByYouTubeId('wrong123456'), isNull);
      expect(catalog.findByOwnYouTubeId('live1234567'), isNull);
    });

    test('files on the server come from files.db, the largest one per song; '
        'none without it', () async {
      await loadSample();
      expect(catalog.byId(1)!.serverFile, isNull);

      await writeFilesDb((await sync.localFile('files.db')).path, [
        (10, 'Dawid Podsiadło/Małomiasteczkowy.mp3', 5000, 1),
        (11, 'Dawid Podsiadło/Małomiasteczkowy (128k).mp3', 3000, 1),
        (12, 'Unknown/track.mp3', 4000, null),
        (13, 'Led Zeppelin/Going to California.mp3', 6000, 2),
      ]);
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await again.ensureLoaded();
      expect(again.byId(1)!.serverFile!.id, 10);
      expect(again.byId(1)!.serverFile!.fileName, 'Małomiasteczkowy.mp3');
      expect(
        again.byId(2)!.serverFile!.path,
        'Led Zeppelin/Going to California.mp3',
      );
      expect(again.byId(3)!.serverFile, isNull);
    });

    test('video lengths come from youtube_video_durations, file lengths from '
        'files.db; unknown without them', () async {
      await loadSample();
      expect(catalog.videoDuration('X2XWBcd5jn0'), isNull);

      final path = (await sync.localFile('music.db')).path;
      await addVideoDurations(path, {'X2XWBcd5jn0': 245});
      await writeFilesDb(
        (await sync.localFile('files.db')).path,
        [
          (10, 'Led Zeppelin/Going to California.mp3', 6000, 2),
          (11, 'Afina/Pay Your Respect.mp3', 6000, 3),
        ],
        durations: {10: 211},
      );
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await again.ensureLoaded();
      expect(again.videoDuration('X2XWBcd5jn0'), const Duration(seconds: 245));
      expect(again.videoDuration('other123456'), isNull);
      expect(again.videoDuration(null), isNull);
      expect(again.byId(2)!.serverFile!.duration, const Duration(seconds: 211));
      expect(again.byId(3)!.serverFile!.duration, isNull);
    });

    test('a cover knows its covered artist, stays titled without the credit '
        'and is recognised by a video title with it', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE artists ADD COLUMN name_latin VARCHAR');
      await db.execute(
        'ALTER TABLE songs ADD COLUMN covered_artist_id INTEGER',
      );
      await db.rawInsert(
        'INSERT INTO artists (id, name, synonyms, name_latin) VALUES '
        "(7, 'Hannah Rue', NULL, NULL), "
        "(8, 'Radiohead', NULL, NULL), "
        "(9, 'Кино', NULL, 'Kino')",
      );
      await db.rawInsert(
        'INSERT INTO songs (id, title, language, artist_id, '
        'covered_artist_id) VALUES '
        "(16, 'Creep', 'English', 7, 8), "
        "(17, 'Creep', 'English', 8, NULL), "
        "(18, 'Группа крови', 'Russian', 7, 9)",
      );
      await db.execute('ALTER TABLE songs ADD COLUMN covered_title TEXT');
      await db.rawInsert(
        'INSERT INTO songs (id, title, language, artist_id, '
        'covered_artist_id, covered_title) VALUES '
        "(19, 'Українська лють', 'Ukrainian', 7, NULL, 'Bella Ciao'), "
        "(20, 'Дарма', 'Ukrainian', 7, 8, 'Never Meant')",
      );
      await db.close();
      await catalog.ensureLoaded();

      final cover = catalog.byId(16)!;
      expect(cover.title, 'Creep');
      expect(cover.artistLabel, 'Hannah Rue');
      expect(cover.coverOf!.name, 'Radiohead');
      expect(cover.youTubeTarget.query, 'Hannah Rue Creep Radiohead cover');
      expect(catalog.byId(17)!.coverOf, isNull);
      expect(catalog.byId(18)!.coverOf!.latin, 'Kino');
      final traditional = catalog.byId(19)!;
      expect(traditional.coverOf!.name, 'Bella Ciao');
      expect(
        traditional.youTubeTarget.query,
        'Hannah Rue Українська лють Bella Ciao cover',
      );
      expect(catalog.byId(20)!.coverOf!.name, 'Radiohead');
      expect(catalog.search('radiohead cover'), contains(cover));

      expect(
        catalog
            .findExact(title: 'Creep (Radiohead cover)', artist: 'Hannah Rue')
            ?.id,
        16,
      );
      expect(
        catalog
            .findExact(
              title: 'Creep (Cover by Hannah Rue)',
              artist: 'Radiohead',
            )
            ?.id,
        16,
      );
      expect(
        catalog.findExact(title: 'Creep (cover)', artist: 'Radiohead'),
        isNull,
      );
    });

    test('Latin forms of names in another alphabet: music.db\'s, else an '
        'artist\'s Latin synonym; found by search', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE artists ADD COLUMN name_latin VARCHAR');
      await db.execute('ALTER TABLE songs ADD COLUMN title_latin VARCHAR');
      await db.execute('ALTER TABLE songs ADD COLUMN album_id INTEGER');
      await db.execute(
        'CREATE TABLE albums (id INTEGER PRIMARY KEY, title VARCHAR NOT NULL, '
        'title_latin VARCHAR)',
      );
      await db.rawInsert(
        "INSERT INTO albums VALUES (1, 'Группа крови', 'Gruppa krovi')",
      );
      await db.rawInsert(
        "INSERT INTO artists (id, name, synonyms, name_latin) VALUES "
        "(7, 'Кино', NULL, 'Kino'), "
        "(8, 'Бумбокс', 'Бумбокс UA, familyboombox, Bumboks', NULL), "
        "(9, 'Земфира', NULL, NULL)",
      );
      await db.rawInsert(
        'INSERT INTO songs (id, title, album, language, artist_id, '
        'title_latin, album_id) VALUES '
        "(6, 'Группа крови', 'Группа крови', 'Russian', 7, 'Gruppa krovi', 1), "
        "(7, 'Вахтёрам', NULL, 'Ukrainian', 8, NULL, NULL), "
        "(8, 'Хочешь?', NULL, 'Russian', 9, 'Khochesh?', NULL)",
      );
      await db.rawInsert(
        "INSERT INTO additional_song_artists VALUES (7, 2, 'feat')",
      );
      await db.execute("UPDATE songs SET title_latin = 'Maly' WHERE id = 1");
      await db.close();
      await catalog.ensureLoaded();

      final kino = catalog.byId(6)!;
      expect(kino.titleLatin, 'Gruppa krovi');
      expect(kino.artistLatin, 'Kino');
      expect(kino.albumLatin, 'Gruppa krovi');
      final boombox = catalog.byId(7)!;
      expect(boombox.titleLatin, isNull);
      expect(boombox.artistLatin, 'familyboombox feat. Led Zeppelin');
      // Nothing to go by: no Latin form rather than a half-Latin one.
      expect(catalog.byId(8)!.artistLatin, isNull);
      // Already in Latin letters: nothing more to show.
      expect(catalog.byId(1)!.titleLatin, isNull);
      expect(catalog.byId(1)!.artistLatin, isNull);

      expect(catalog.search('gruppa kino').single.id, 6);
      expect(catalog.search('khochesh').single.id, 8);
      expect(catalog.findExact(title: 'Группа крови', artist: 'Kino')?.id, 6);

      // An artist by any of its names: a channel name, a Latin form.
      expect(catalog.artistNamed('FamilyBoomBox'), 'Бумбокс');
      expect(catalog.artistNamed('Kino'), 'Кино');
      expect(catalog.artistNamed('Бумбокс'), 'Бумбокс');
      expect(catalog.artistNamed('led zeppelin'), 'Led Zeppelin');
      expect(catalog.artistNamed('Nobody'), isNull);
    });

    test('by name: also without the title\'s feat. credit, or swapped; '
        'another version stays apart', () async {
      await loadSample();
      expect(
        catalog.findByName(title: 'Pay Your Respect', artist: 'Afina')?.id,
        3,
      );
      expect(
        catalog
            .findByName(
              title: 'Pay Your Respect (feat. CJ Pitts)',
              artist: 'Afina',
            )
            ?.id,
        3,
      );
      expect(
        catalog
            .findByName(title: 'Pay Your Respect ft. CJ Pitts', artist: 'Afina')
            ?.id,
        3,
      );
      // A YouTube upload credits the guest in the artist: "Afina feat. CJ Pitts - …".
      expect(
        catalog
            .findByName(
              title: 'Pay Your Respect',
              artist: 'Afina feat. CJ Pitts',
            )
            ?.id,
        3,
      );
      expect(
        catalog
            .findByName(title: 'Led Zeppelin', artist: 'Going to California')
            ?.id,
        2,
      );
      expect(
        catalog.findByName(
          title: 'Going to California (Live)',
          artist: 'Led Zeppelin',
        ),
        isNull,
      );
      // A joined credit: each of its artists credited by the song.
      for (final artist in ['Artur Rojek i CatchUp', 'CatchUp & Artur Rojek']) {
        expect(catalog.findByName(title: 'Pusty', artist: artist)?.id, 4);
      }
      expect(
        catalog.findByName(title: 'Pusty', artist: 'Artur Rojek i Afina'),
        isNull,
      );
      // … or their names side by side, a joint channel's.
      for (final artist in ['Artur Rojek CatchUp', 'CatchUp Artur Rojek']) {
        expect(catalog.findByName(title: 'Pusty', artist: artist)?.id, 4);
      }
      for (final artist in ['Artur Rojek Afina', 'Artur CatchUp']) {
        expect(catalog.findByName(title: 'Pusty', artist: artist), isNull);
      }
      expect(
        catalog.findByName(
          title: 'Pusty (Live)',
          artist: 'Artur Rojek i CatchUp',
        ),
        isNull,
      );
      expect(
        catalog.findExact(
          title: 'Pay Your Respect (feat. CJ Pitts)',
          artist: 'Afina',
        ),
        isNull,
      );
    });

    test('versions: shown with their marker, matched by it only, '
        'listed with their original', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE songs ADD COLUMN version_kind TEXT');
      await db.execute('ALTER TABLE songs ADD COLUMN version_label TEXT');
      await db.execute('ALTER TABLE songs ADD COLUMN version_of INTEGER');
      await db.rawInsert(
        'INSERT INTO songs (id, title, language, artist_id, version_kind, '
        'version_label, version_of) VALUES '
        "(30, 'Boję się', 'Polish', 5, NULL, NULL, NULL), "
        "(31, 'Boję się', 'Polish', 5, 'live', NULL, 30), "
        "(32, 'Boję się', 'Polish', 5, 'live', 'Live at Opener', 30), "
        "(33, 'Boję się', 'Polish', 5, 'remix', 'Ptaki Remix', 30), "
        "(34, 'Recover', 'English', 6, 'remix', 'Cid Rim Remix', NULL), "
        "(35, 'Werewolf (Live)', 'English', 6, NULL, NULL, NULL), "
        "(36, 'Engel', 'German', 6, 'something new', NULL, NULL)",
      );
      await db.close();
      await catalog.ensureLoaded();

      final live = catalog.byId(31)!;
      expect(live.title, 'Boję się');
      expect(live.version!.kind, VersionKind.live);
      expect(live.version!.marker, 'Live');
      expect(live.version!.originalId, 30);
      expect(catalog.byId(32)!.version!.marker, 'Live at Opener');
      expect(catalog.byId(36)!.version!.kind, VersionKind.other);
      expect(catalog.byId(30)!.version, isNull);
      expect(live.youTubeTarget.query, 'Artur Rojek Boję się Live');
      expect(
        catalog.byId(34)!.youTubeTarget.query,
        'CatchUp Recover Cid Rim Remix',
      );
      expect(catalog.search('boje sie remix').map((s) => s.id), [33]);

      int? found(String title, [String artist = 'Artur Rojek']) =>
          catalog.findByName(title: title, artist: artist)?.id;
      expect(found('Boję się'), 30);
      expect(found('Boję się (Live)'), 31);
      expect(found('Boję się [live]'), 31);
      expect(found('Boję się (Live at Opener)'), 32);
      expect(found('Boję się - Live at Opener'), 32);
      expect(found('Boję się (Live in Jarocin)'), 31);
      expect(found('Boję się (Ptaki Remix)'), 33);
      expect(found('Boję się (Remix)'), 33);
      expect(found('Boję się (Acoustic)'), isNull);
      expect(found('Boję się (Radio Edit)'), isNull);
      expect(found('Recover', 'CatchUp'), isNull);
      expect(found('Recover (Cid Rim Remix)', 'CatchUp'), 34);
      expect(found('Recover CID RIM REMIX', 'CatchUp'), 34);
      expect(found('Recover Remix', 'CatchUp'), isNull);
      expect(found('Boję się Live'), 31);
      expect(found('Werewolf (Live)', 'CatchUp'), 35);
      expect(found('Werewolf', 'CatchUp'), isNull);
      expect(found('Engel (Version)', 'CatchUp'), 36);
      expect(found('Engel', 'CatchUp'), isNull);

      List<int> others(int id) => [
        for (final song in catalog.otherVersionsOf(catalog.byId(id)!)) song.id,
      ];
      expect(others(30), [31, 32, 33]);
      expect(others(32), [30, 31, 33]);
      expect(others(34), isEmpty);
      expect(others(1), isEmpty);
    });

    test('no versions in a music.db from before them', () async {
      await loadSample();
      expect(catalog.songs.where((s) => s.version != null), isEmpty);
      expect(catalog.otherVersionsOf(catalog.byId(1)!), isEmpty);
    });

    test('projects: names naming one match only its songs, names naming none '
        'never do', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      await addProjects(
        path,
        {
          1: ('Kaunas Acoustics', null, null),
          2: (
            'Tiny Desk',
            'NPR Music Tiny Desk Concert,Tiny Desk Concert',
            'NPR Music',
          ),
          3: ('Like a Version', 'triple j Like a Version', 'triple j'),
          4: ('Męskie Granie', null, null),
        },
        {
          40: ('Sobie i Wam', 7, null),
          41: ('Sobie i Wam', 7, 4),
          42: ('Boys', 8, 3),
          43: ('Tiny Desk Concert', 9, 2),
          44: ('Pieno Fabrikėlis', 10, 1),
          45: ('Wojenka', 11, 4),
        },
        artists: {
          7: 'Nosowska',
          8: 'Wolf Alice',
          9: 'Daughter',
          10: 'Liūdni slibinai',
          11: 'Męskie Granie Orkiestra 2016',
        },
      );
      await catalog.ensureLoaded();

      expect(catalog.byId(41)!.project, 'Męskie Granie');
      expect(catalog.byId(41)!.title, 'Sobie i Wam');
      expect(catalog.byId(40)!.project, isNull);

      int? found(String title, String artist) =>
          catalog.findByName(title: title, artist: artist)?.id;
      expect(found('Sobie i Wam', 'Nosowska'), 40);
      expect(found('Sobie i Wam (Męskie Granie 2018)', 'Nosowska'), 41);
      expect(found('Sobie i Wam - Live at Męskie Granie', 'Nosowska'), 41);
      expect(found('Sobie i Wam [MĘSKIE GRANIE]', 'Nosowska'), 41);
      // Only the project as the artist: who plays isn't said, and the studio song isn't it.
      expect(found('Sobie i Wam', 'Męskie Granie'), isNull);
      // An artist whose name only contains the project keeps it.
      expect(found('Wojenka', 'Męskie Granie Orkiestra 2016'), 45);
      expect(found('Boys', 'Wolf Alice'), isNull);
      expect(found('Boys (Like a Version)', 'Wolf Alice'), 42);
      expect(found('Wolf Alice - Boys | Like a Version', 'triple j'), 42);
      expect(found('Daughter: Tiny Desk Concert', 'NPR Music'), 43);
      expect(found('Tiny Desk Concert', 'Daughter'), 43);
      expect(
        found('Pieno Fabrikėlis', 'Kaunas Acoustics : Liūdni slibinai'),
        44,
      );
      expect(found('Pieno Fabrikėlis', 'Liūdni slibinai'), isNull);
      // Swapped, as an upload titled "Title - Artist".
      expect(found('Nosowska', 'Sobie i Wam (Męskie Granie)'), 41);
      expect(
        catalog.findExact(title: 'Sobie i Wam', artist: 'Nosowska')?.id,
        40,
      );
      expect(
        catalog
            .findExact(
              title: 'Sobie i Wam',
              artist: 'Nosowska',
              project: 'Męskie Granie',
            )
            ?.id,
        41,
      );
    });

    test('no projects in a music.db from before them', () async {
      await loadSample();
      expect(catalog.songs.where((s) => s.project != null), isEmpty);
      expect(
        catalog
            .findByName(title: 'Małomiasteczkowy', artist: 'Dawid Podsiadło')
            ?.id,
        1,
      );
    });

    test('no Latin forms in a music.db from before them', () async {
      await loadSample();
      expect(catalog.byId(1)!.titleLatin, isNull);
      expect(catalog.byId(1)!.albumLatin, isNull);
    });

    test('loads every song with its artists', () async {
      await loadSample();
      expect(catalog.status, CatalogStatus.ready);
      expect(catalog.songCount, 5);
      expect(
        catalog.search('respect').single.artistLabel,
        'Afina feat. CJ Pitts',
      );
      expect(
        catalog.search('pusty').single.artistLabel,
        'Artur Rojek, CatchUp',
      );
    });

    test(
      'matches title and artist words regardless of accents and case',
      () async {
        await loadSample();
        expect(catalog.search('malomiasteczkowy podsiadlo').single.id, 1);
        expect(catalog.search('MAŁOMIASTECZKOWY').single.id, 1);
        expect(catalog.search('catchup').single.id, 4);
        expect(catalog.search('zeppelin nothing'), isEmpty);
        expect(catalog.search('   '), isEmpty);
      },
    );

    test('reads a Spotify track link, not an album one', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE songs ADD COLUMN spotify_url VARCHAR');
      await db.rawUpdate(
        "UPDATE songs SET spotify_url = "
        "'https://open.spotify.com/track/7lQ8MOhq6IN2w8EYcFNSUk' WHERE id = 2",
      );
      await db.rawUpdate(
        "UPDATE songs SET spotify_url = "
        "'https://open.spotify.com/album/1Ugdi2OTxKopVVqsprp5pb' WHERE id = 5",
      );
      await db.close();
      await catalog.ensureLoaded();
      expect(catalog.byId(2)!.spotifyTrackId, '7lQ8MOhq6IN2w8EYcFNSUk');
      expect(catalog.byId(5)!.spotifyTrackId, isNull);
      expect(catalog.byId(1)!.spotifyTrackId, isNull);
    });

    test('songs.kind: full albums marked, an unknown value is a song, no '
        'column at all is songs only', () async {
      await loadSample();
      expect(catalog.songs.any((s) => s.isFullAlbum), isFalse);

      final path = (await sync.localFile('music.db')).path;
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE songs ADD COLUMN kind TEXT');
      await db.rawUpdate("UPDATE songs SET kind = 'full_album' WHERE id = 2");
      await db.rawUpdate("UPDATE songs SET kind = 'dj_mix' WHERE id = 3");
      await db.close();
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await again.ensureLoaded();
      expect(again.byId(2)!.kind, SongKind.fullAlbum);
      expect(again.byId(2)!.youTubeTarget.fullAlbum, isTrue);
      expect(again.byId(3)!.kind, SongKind.song);
      expect(again.byId(1)!.kind, SongKind.song);
      expect(again.byId(1)!.youTubeTarget.fullAlbum, isFalse);
    });

    test('puts titles starting with the query first', () async {
      await loadSample();
      expect(catalog.search('california').map((s) => s.id).toList(), [5, 2]);
    });

    test('reloads after a new download', () async {
      await loadSample();
      final db = await databaseFactoryFfi.openDatabase(
        (await sync.localFile('music.db')).path,
      );
      await db.rawInsert(
        "INSERT INTO songs VALUES (6, 'Nowa', NULL, NULL, NULL, 1, NULL)",
      );
      await db.close();
      expect(catalog.search('nowa'), isEmpty);

      // Simulates DatabaseSync announcing a new lastSync, as after a successful download.
      SharedPreferences.setMockInitialValues({
        'database_sync.url': 'http://127.0.0.1:1/',
        'database_sync.last_sync_ms': DateTime(
          2026,
          10,
          10,
        ).millisecondsSinceEpoch,
      });
      await sync.load();
      // The reload runs in the background and touches the real file system.
      await waitUntil(() => catalog.search('nowa').isNotEmpty);
      expect(catalog.search('nowa').single.id, 6);
    });

    test('search fields: defaults are title, artist and album', () async {
      await loadSample();
      expect(catalog.searchFields, SearchField.defaults);
      expect(catalog.search('led zeppelin iv').single.id, 2); // album
      expect(catalog.search('cj pitts').single.id, 3); // featured artist
      expect(catalog.search('2018'), isEmpty);
      expect(catalog.search('polish'), isEmpty);
      expect(catalog.search('silesia'), isEmpty);
    });

    test('search fields: year, language, origin, artist synonyms', () async {
      await loadSample();
      await catalog.setSearchFields({SearchField.year});
      expect(catalog.search('2018').single.id, 1);

      await catalog.setSearchFields({SearchField.language});
      expect(
        catalog.search('polish').map((s) => s.id),
        unorderedEquals([1, 4]),
      );
      expect(catalog.search('unknown'), isEmpty);

      await catalog.setSearchFields({SearchField.origin});
      // Origin of an additional artist counts too (CJ Pitts on song 3).
      expect(catalog.search('ohio').single.id, 3);
      expect(
        catalog.search('silesia').map((s) => s.id),
        unorderedEquals([1, 4]),
      );

      // Other artist names (synonyms) come with the artist field, not on their own.
      await catalog.setSearchFields({SearchField.artist});
      expect(
        catalog.search('ledzeppelinofficial').map((s) => s.id),
        unorderedEquals([2, 5]),
      );
      await catalog.setSearchFields({SearchField.title});
      expect(catalog.search('ledzeppelinofficial'), isEmpty);
    });

    test(
      'search fields: combined words may come from different fields',
      () async {
        await loadSample();
        await catalog.setSearchFields({SearchField.title, SearchField.year});
        expect(catalog.search('california 1971').single.id, 2);
      },
    );

    test('search fields: never empty, and remembered', () async {
      await loadSample();
      await catalog.setSearchFields({});
      expect(catalog.searchFields, SearchField.defaults);

      await catalog.setSearchFields({SearchField.year, SearchField.title});
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await waitUntil(() => again.searchFields.length == 2);
      expect(again.searchFields, {SearchField.year, SearchField.title});
    });

    test('YouTube link: id, "N/A" annotation, or nothing stored', () async {
      await loadSample();
      CatalogSong song(String title) => catalog.search(title).first;

      expect(song('Małomiasteczkowy').youTube, YouTubeLink.linked);
      expect(song('Małomiasteczkowy').youtubeVideoId, 'X2XWBcd5jn0');
      expect(song('Pay Your Respect').youTube, YouTubeLink.notOnYouTube);
      expect(song('Pay Your Respect').youtubeVideoId, isNull);
      expect(song('Pusty').youTube, YouTubeLink.unknown);
      expect(song('Going to California').youTube, YouTubeLink.unknown);
    });
  });
}
