import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/song_requests.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DateTime now;

  Outbox newOutbox() => Outbox(
    storageRoot: () async => root,
    factoryOverride: databaseFactoryFfi,
    now: () => now,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('song_requests_test');
    now = DateTime(2026, 10, 18, 9, 30);
  });

  tearDown(() => root.delete(recursive: true));

  SearchHit video(String title, String artist, String id) =>
      SearchHit.youTubeOnly(title: title, artistLabel: artist, videoId: id);

  test('what a song outside music.db is asked as, by where it comes from', () {
    final fromVideo = SongRequest.of(video('Unseen', 'Elise Trouw', 'v1'))!;
    expect(fromVideo.source, SongRequestSource.youtube);
    expect(fromVideo.youtubeVideoId, 'v1');
    expect(fromVideo.artist, 'Elise Trouw');

    // A playlist video's length goes with it, so MusicDatabase sees a long mix for what it is.
    final mix = SongRequest.of(
      SearchHit.youTubeOnly(
        title: 'After Dark',
        artistLabel: 'Songs that actually match the vibe of Mr. Kitty',
        videoId: 'bHU-MASMBjM',
        duration: const Duration(seconds: 1939),
      ),
    )!;
    expect(mix.duration, const Duration(seconds: 1939));
    expect(fromVideo.duration, isNull);

    final fromSpotify = SongRequest.of(
      SearchHit.youTubeOnly(
        title: 'Unseen',
        artistLabel: 'Nieznany wykonawca',
        videoId: null,
        spotifyTrackId: 'sp1',
      ),
    )!;
    expect(fromSpotify.source, SongRequestSource.spotify);
    expect(fromSpotify.artist, isNull);

    final fromFile = SongRequest.of(
      SearchHit.phoneOnly(
        LocalSong(
          id: 1,
          filePath: '/music/unseen.mp3',
          title: 'Unseen',
          artist: 'Elise Trouw',
          album: 'Unseen',
          year: 2020,
          pending: true,
        ),
      ),
    )!;
    expect(fromFile.source, SongRequestSource.phoneFile);
    expect((fromFile.album, fromFile.year), ('Unseen', 2020));

    final inMusicDb = SearchHit.main(
      CatalogSong(id: 1, title: 'Chromatic', artistLabel: 'Elise Trouw'),
      const [],
    );
    expect(SongRequest.of(inMusicDb), isNull);
  });

  test('an artist known by another name is asked as music.db spells it', () {
    String? artistNamed(String name) =>
        name == 'familyboombox' ? 'Бумбокс' : null;
    final request = SongRequest.of(
      video('Ангела (feat. Крихітка)', 'familyboombox', 'YoCl9HzwCm0'),
      artistNamed: artistNamed,
    )!;
    expect(request.artist, 'Бумбокс');
    expect(request.title, 'Ангела (feat. Крихітка)');
    // One music.db doesn't know stays as shown.
    expect(
      SongRequest.of(
        video('Unseen', 'Elise Trouw', 'v1'),
        artistNamed: artistNamed,
      )!.artist,
      'Elise Trouw',
    );
  });

  test('a video\'s title stored with junk by an older import is asked for '
      'without it (the playlist "Скачать (2018.06)")', () {
    String? artistNamed(String name) =>
        name == 'nipplepeople' ? 'Nipplepeople' : null;
    expect(
      SongRequest.of(
        video('ゆらゆら（Official Music Video）', 'YeYe', 'StkLx0e4f6c'),
      )!.title,
      'ゆらゆら',
    );
    final frka = SongRequest.of(
      video('FRKA , Kire Mitrev, Slavica Maras', 'nipplepeople', '2pfLE5YJ1Fo'),
      artistNamed: artistNamed,
    )!;
    // Stored before the credits were cut: nothing marks them any more, so the title stays.
    expect(frka.title, 'FRKA , Kire Mitrev, Slavica Maras');
    expect(frka.artist, 'Nipplepeople');
    expect(
      SongRequest.of(
        video('FRKA (Official video), Kire Mitrev', 'nipplepeople', 'v2'),
        artistNamed: artistNamed,
      )!.title,
      'FRKA',
    );
    // Versions and a phone file's tags stay.
    expect(
      SongRequest.of(video('ゆらゆら (Live)', 'YeYe', 'v3'))!.title,
      'ゆらゆら (Live)',
    );
    expect(
      SongRequest.of(
        SearchHit.phoneOnly(
          LocalSong(
            id: 2,
            filePath: '/music/x.mp3',
            title: 'Song (Official Video)',
            artist: 'X',
            pending: true,
          ),
        ),
      )!.title,
      'Song (Official Video)',
    );
  });

  test('the video length is written as duration_s and read back', () async {
    final outbox = newOutbox();
    await outbox.requestSong(
      SongRequest.of(
        SearchHit.youTubeOnly(
          title: 'Mix',
          artistLabel: 'cinemArt',
          videoId: 'm1',
          duration: const Duration(minutes: 32, seconds: 19),
        ),
      )!,
    );
    final [file] = await outbox.pending();
    final db = await databaseFactoryFfi.openDatabase(file.path);
    try {
      final [row] = await db.query('song_requests');
      expect(row['duration_s'], 1939);
    } finally {
      await db.close();
    }
    final [waiting] = await outbox.waitingSongRequests();
    expect(waiting.duration, const Duration(seconds: 1939));
  });

  test('a song is asked for once, by name or by its video', () async {
    final outbox = newOutbox();

    expect(
      await outbox.requestSong(
        SongRequest.of(video('Unseen', 'Elise Trouw', 'v1'))!,
      ),
      isTrue,
    );
    expect(
      await outbox.requestSong(
        SongRequest.of(video('UNSEEN', 'elise trouw', 'v2'))!,
      ),
      isFalse,
    );
    expect(
      await outbox.requestSong(
        SongRequest.of(
          video('Unseen (Official Video)', 'EliseTrouwVEVO', 'v1'),
        )!,
      ),
      isFalse,
    );
    expect(
      await outbox.requestSong(
        SongRequest.of(video('Chromatic', 'Elise Trouw', 'v3'))!,
      ),
      isTrue,
    );

    final [file] = await outbox.pending();
    final db = await databaseFactoryFfi.openDatabase(file.path);
    try {
      final rows = await db.query('song_requests', orderBy: 'rowid');
      expect([for (final r in rows) r['title']], ['Unseen', 'Chromatic']);
      expect(rows.first['duration_s'], isNull);
      expect(rows.first['source'], 'youtube');
      expect(rows.first['requested_at'], startsWith('2026-10-18T09:30:00'));
    } finally {
      await db.close();
    }
    expect(
      [for (final r in await outbox.waitingSongRequests()) r.title],
      ['Unseen', 'Chromatic'],
    );
  });

  test('songs to add go into request files of their own', () async {
    final outbox = newOutbox();
    await outbox.reportDeadYouTubeLink(
      CatalogSong(id: 1, title: 'Chromatic', artistLabel: 'Elise Trouw'),
      'dead1',
    );
    await outbox.requestSong(
      SongRequest.of(video('Unseen', 'Elise Trouw', 'v1'))!,
    );

    expect(await outbox.pending(), hasLength(2));
  });

  test(
    'rejected_song_requests turns down a song by name, video or Spotify track',
    () async {
      final db = sql.sqlite3.open('${root.path}/music.db');
      expect(RejectedSongRequests.read(db), same(RejectedSongRequests.none));
      db.execute(
        '''
      CREATE TABLE rejected_song_requests (
        id INTEGER PRIMARY KEY, artist TEXT, title TEXT NOT NULL,
        youtube_video_id TEXT, spotify_track_id TEXT, rejected_at TEXT NOT NULL)''',
      );
      db.execute(
        'INSERT INTO rejected_song_requests '
        '(artist, title, youtube_video_id, rejected_at) VALUES (?, ?, ?, ?)',
        ['Elise Trouw', 'Unseen', 'v1', '2026-10-18T10:00:00+02:00'],
      );
      db.execute(
        'INSERT INTO rejected_song_requests '
        '(title, spotify_track_id, rejected_at) VALUES (?, ?, ?)',
        ['Some track', 'sp9', '2026-10-18T10:00:00+02:00'],
      );
      final rejected = RejectedSongRequests.read(db);
      db.close();

      bool rejects(SearchHit hit) => rejected.rejects(SongRequest.of(hit)!);
      expect(rejects(video('UNSEEN', 'elise trouw', 'other')), isTrue);
      expect(rejects(video('Unseen (live)', 'Someone', 'v1')), isTrue);
      expect(
        rejects(
          SearchHit.youTubeOnly(
            title: 'Another name',
            artistLabel: 'X',
            videoId: null,
            spotifyTrackId: 'sp9',
          ),
        ),
        isTrue,
      );
      expect(rejects(video('Chromatic', 'Elise Trouw', 'v3')), isFalse);
    },
  );
}
