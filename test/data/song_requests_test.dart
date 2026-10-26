import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/song_requests.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      final path = '${root.path}/music.db';
      final db = await databaseFactoryFfi.openDatabase(path);
      expect(
        await RejectedSongRequests.read(db),
        same(RejectedSongRequests.none),
      );
      await db.execute(
        '''
      CREATE TABLE rejected_song_requests (
        id INTEGER PRIMARY KEY, artist TEXT, title TEXT NOT NULL,
        youtube_video_id TEXT, spotify_track_id TEXT, rejected_at TEXT NOT NULL)''',
      );
      await db.insert('rejected_song_requests', {
        'artist': 'Elise Trouw',
        'title': 'Unseen',
        'youtube_video_id': 'v1',
        'rejected_at': '2026-10-18T10:00:00+02:00',
      });
      await db.insert('rejected_song_requests', {
        'title': 'Some track',
        'spotify_track_id': 'sp9',
        'rejected_at': '2026-10-18T10:00:00+02:00',
      });
      final rejected = await RejectedSongRequests.read(db);
      await db.close();

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
