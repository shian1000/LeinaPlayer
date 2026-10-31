import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/spotify_playlist.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';
import 'package:music_database_app/src/data/youtube_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary youTube;
  late PlaylistLibrary playlists;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('playlist_library_test');
    sync = DatabaseSync(storageRoot: () async => root);
    await writeMusicDb((await sync.localFile('music.db')).path);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    youTube = YouTubeLibrary(local.database, storageRoot: () async => root);
    await youTube.load();
    playlists = PlaylistLibrary(local.database, catalog, youTube);
    await playlists.load();
  });

  tearDown(() async {
    playlists.dispose();
    youTube.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  YouTubeVideo v(
    String id,
    String title,
    String channel, [
    int seconds = 200,
  ]) => YouTubeVideo(
    id: id,
    title: title,
    channel: channel,
    duration: Duration(seconds: seconds),
  );

  YouTubePlaylistData data(List<YouTubeVideo> videos, {String name = 'Moja'}) =>
      YouTubePlaylistData(
        id: 'PL1',
        name: name,
        owner: 'Shian',
        videos: videos,
      );

  test('imports in order, recognising songs by video first, then by name', () async {
    // Phone-matched earlier: "Going to California" (songs.id 2) is video "gtc".
    await youTube.saveMatch(
      2,
      const YouTubeVideo(id: 'gtc', title: 't', channel: 'c'),
    );
    final result = await playlists.importYouTube(
      data([
        // music.db links song 1 to X2XWBcd5jn0, whatever the title says.
        v('X2XWBcd5jn0', 'Jakiś zupełnie inny tytuł', 'Kanał'),
        v('gtc', 'Led Zeppelin - Going To California (Remaster)', 'x'),
        v('p1', 'Pusty', 'Artur Rojek - Topic'),
        v('zz', 'Nieznany - Utwór (Official Video)', 'Nieznany', 100),
      ]),
    );

    expect(result.updated, isFalse);
    expect(result.recognised, 3);
    expect(result.playlist.trackCount, 4);
    expect(result.playlist.duration, const Duration(seconds: 700));
    expect(playlists.playlists.single.name, 'Moja');

    final tracks = await playlists.tracks(result.playlist.id);
    expect([for (final t in tracks) t.position], [0, 1, 2, 3]);
    expect([for (final t in tracks) t.mainDbId], [1, 2, 4, null]);
    expect(
      [for (final t in tracks) t.youtubeVideoId],
      ['X2XWBcd5jn0', 'gtc', 'p1', 'zz'],
    );
    // Recognised songs keep MusicDatabase's spelling; the rest what the title gave.
    expect(tracks[0].title, 'Małomiasteczkowy');
    expect((tracks[3].artist, tracks[3].title), ('Nieznany', 'Utwór'));
  });

  test(
    'a track saved without its MusicDatabase song is recognised by title and '
    'artist, and the song is written into the playlist to sync',
    () async {
      final result = await playlists.importYouTube(
        data([
          v('X2XWBcd5jn0', 'Jakiś zupełnie inny tytuł', 'Kanał'),
          v('gtc', 'Led Zeppelin - Going To California', 'x'),
          v('p1', 'Pusty', 'Artur Rojek - Topic'),
        ]),
      );
      final id = result.playlist.id;
      final db = await local.database();
      // As saved before music.db had the songs; "gtc" lost its artist too.
      await db.update('playlist_tracks', {'main_db_id': null});
      await db.update('playlist_tracks', {
        'artist': null,
      }, where: 'position = 1');
      await db.update('playlists', {'dirty': 0});
      final updatedAt = (await db.query('playlists')).single['updated_at'];

      final saved = await playlists.tracks(id);
      expect(
        [
          for (final t in saved)
            playlistHit(t, catalog, local, youTube).mainSong?.id,
        ],
        [1, null, 4],
      );

      await playlists.load();
      expect(
        [for (final t in await playlists.tracks(id)) t.mainDbId],
        [
          // Found by its video: music.db's link is enough, nothing to write.
          null,
          // No artist, no guess.
          null,
          4,
        ],
      );
      final row = (await db.query('playlists')).single;
      expect(row['dirty'], 1);
      expect(row['updated_at'], updatedAt);

      // MusicDatabase sent it back without the song: not written (and sent) again this run.
      await db.update('playlist_tracks', {'main_db_id': null});
      await db.update('playlists', {'dirty': 0});
      await playlists.load();
      expect((await playlists.tracks(id))[2].mainDbId, isNull);
      expect((await db.query('playlists')).single['dirty'], 0);
      expect(
        playlistHit(
          (await playlists.tracks(id))[2],
          catalog,
          local,
          youTube,
        ).mainSong?.id,
        4,
      );
    },
  );

  test('a track without its own length takes its video\'s from music.db, '
      'else its library file\'s; the rest count as unknown', () async {
    await addVideoDurations((await sync.localFile('music.db')).path, {
      'X2XWBcd5jn0': 245,
      'own12345678': 100,
    });
    await writeFilesDb(
      (await sync.localFile('files.db')).path,
      [(10, 'Led Zeppelin/Going to California.mp3', 6000, 2)],
      durations: {10: 211},
    );
    await catalog.ensureLoaded();

    final saved = await playlists.create('Mieszana', [
      // music.db's video.
      SearchHit.main(catalog.byId(1)!, const []),
      // No video in music.db: its library file.
      SearchHit.main(catalog.byId(2)!, const []),
      // "N/A": no video, no file.
      SearchHit.main(catalog.byId(3)!, const []),
      // Its own video.
      SearchHit.youTubeOnly(
        title: 'Klip',
        artistLabel: 'Ktoś',
        videoId: 'own12345678',
        playlistVideoId: 'own12345678',
      ),
    ]);
    expect(saved.duration, const Duration(seconds: 245 + 211 + 100));
    expect(saved.unknownLengths, 1);
    // Worked out when reading, never written back (the rows sync).
    final tracks = await playlists.tracks(saved.id);
    expect([for (final t in tracks) t.duration], everyElement(isNull));

    // A track's own length goes first.
    final imported = await playlists.importYouTube(
      data([v('X2XWBcd5jn0', 'Dawid Podsiadło - Małomiasteczkowy', 'x', 250)]),
    );
    expect(imported.playlist.duration, const Duration(seconds: 250));
    expect(imported.playlist.unknownLengths, 0);
  });

  test(
    'keeps the first tracks of each playlist for its cover collage',
    () async {
      final result = await playlists.importYouTube(
        data([
          for (var i = 0; i < PlaylistLibrary.leadTrackCount + 3; i++)
            v('v$i', 'A - $i', 'x'),
        ]),
      );
      final lead = playlists.leadTracks(result.playlist.id);
      expect(lead, hasLength(PlaylistLibrary.leadTrackCount));
      expect(lead.first.youtubeVideoId, 'v0');
      expect(lead.last.position, PlaylistLibrary.leadTrackCount - 1);

      await playlists.delete(result.playlist.id);
      expect(playlists.leadTracks(result.playlist.id), isEmpty);
    },
  );

  test('importing the same playlist again replaces it', () async {
    await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x')]),
    );
    final again = await playlists.importYouTube(
      data([v('c', 'C - 3', 'x')], name: 'Nowa nazwa'),
    );
    expect(again.updated, isTrue);
    expect(playlists.playlists, hasLength(1));
    // The name the phone has stays (the user may have renamed it).
    expect(playlists.playlists.single.name, 'Moja');
    expect((await playlists.tracks(again.playlist.id)).single.title, '3');

    await playlists.delete(again.playlist.id);
    expect(playlists.playlists, isEmpty);
  });

  test(
    'a Spotify album is a playlist of its own, linking to the album',
    () async {
      await playlists.importSpotify(
        const SpotifyPlaylistData(
          id: '1DFixLWuPkv3KT3TnV35m3',
          name: 'Emotion',
          owner: 'Carly Rae Jepsen',
          album: true,
          tracks: [
            SpotifyTrack(id: 't1', title: 'Run Away With Me', artists: ['X']),
          ],
        ),
      );
      final album = playlists.playlists.single;
      expect(album.source, PlaylistSource.spotifyAlbum);
      expect(
        album.link.toString(),
        'https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3',
      );
      expect(
        playlists.saved(PlaylistSource.spotify, '1DFixLWuPkv3KT3TnV35m3'),
        isNull,
      );
    },
  );

  test(
    'imports a Spotify playlist, recognising songs by title and artist',
    () async {
      final result = await playlists.importSpotify(
        const SpotifyPlaylistData(
          id: '37i9dQZF1DX4UtSsGT1Sbe',
          name: 'Ze Spotify',
          owner: null,
          tracks: [
            SpotifyTrack(
              id: 't1',
              title: 'Going to California - Remaster',
              artists: ['Led Zeppelin'],
              duration: Duration(seconds: 211),
            ),
            // Any one of the artists will do.
            SpotifyTrack(
              id: 't2',
              title: 'Pusty',
              artists: ['Ktoś', 'Artur Rojek'],
            ),
            SpotifyTrack(
              id: 't3',
              title: 'Nowa - Radio Edit',
              artists: ['A', 'B'],
            ),
          ],
        ),
      );
      expect(result.recognised, 2);
      final playlist = playlists.playlists.single;
      expect(playlist.source, PlaylistSource.spotify);
      expect(playlist.youTubeId, isNull);
      expect(
        playlist.link.toString(),
        'https://open.spotify.com/playlist/37i9dQZF1DX4UtSsGT1Sbe',
      );
      final tracks = await playlists.tracks(playlist.id);
      expect([for (final t in tracks) t.mainDbId], [2, 4, null]);
      expect([for (final t in tracks) t.youtubeVideoId], [null, null, null]);
      expect([for (final t in tracks) t.spotifyTrackId], ['t1', 't2', 't3']);
      // Shared as the Spotify track, recognised or not.
      final hit = playlistHit(tracks[2], catalog, local, youTube);
      expect(hit.spotifyUri.toString(), 'https://open.spotify.com/track/t3');
      expect(
        playlistHit(tracks[0], catalog, local, youTube).spotifyUri.toString(),
        'https://open.spotify.com/track/t1',
      );
      // A video found later keeps the Spotify track.
      await youTube.saveTrackMatch(
        'A, B',
        'Nowa',
        const YouTubeVideo(id: 'nowa', title: 't', channel: 'c'),
      );
      final found = playlistHit(tracks[2], catalog, local, youTube);
      expect((found.youtubeVideoId, found.spotifyTrackId), ('nowa', 't3'));
      final ref = TrackRef.fromJson(TrackRef.of(found).toJson());
      expect(
        resolveTrack(ref, catalog, local, youTube).spotifyUri.toString(),
        'https://open.spotify.com/track/t3',
      );
      expect((tracks[2].artist, tracks[2].title), ('A, B', 'Nowa'));
    },
  );

  test('a YouTube playlist links to its YouTube page', () async {
    await playlists.importYouTube(data([v('a', 'A - 1', 'x')]));
    expect(
      playlists.playlists.single.link.toString(),
      'https://www.youtube.com/playlist?list=PL1',
    );
  });

  test(
    're-importing keeps tracks whose video YouTube removed, marked',
    () async {
      await playlists.importYouTube(
        data([
          v('a', 'A - 1', 'x'),
          v('b', 'B - 2', 'x'),
          v('c', 'C - 3', 'x'),
          v('d', 'D - 4', 'x'),
        ]),
      );
      final checked = <String>[];
      // b: gone from YouTube; d, e: still there, so the owner took them out of the playlist.
      Future<bool?> exists(String id) async {
        checked.add(id);
        return id != 'b';
      }

      final again = await playlists.importYouTube(
        data([
          v('a', 'A - 1', 'x'),
          v('zz', '[Deleted video]', ''),
          v('c', 'C - 3', 'x'),
          v('e', 'E - 5', 'x'),
        ]),
        videoExists: exists,
      );
      expect(checked, ['b', 'd']);
      expect(again.removedVideos, 1);
      var tracks = await playlists.tracks(again.playlist.id);
      expect([for (final t in tracks) t.title], ['1', '2', '3', '5']);
      expect(
        [for (final t in tracks) t.videoRemoved],
        [false, true, false, false],
      );
      expect(tracks[1].youtubeVideoId, 'b');
      expect(tracks[1].playableVideoId, isNull);

      // Shown with a dimmed icon: no video, to be searched.
      final hit = playlistHit(tracks[1], catalog, local, youTube);
      expect(hit.youtubeVideoId, isNull);
      expect(hit.youTube, YouTubeLink.unknown);

      // Still missing next time: not checked again, still kept.
      checked.clear();
      await playlists.importYouTube(
        data([v('a', 'A - 1', 'x'), v('c', 'C - 3', 'x')]),
        videoExists: exists,
      );
      tracks = await playlists.tracks(again.playlist.id);
      expect(checked, ['e']);
      expect([for (final t in tracks) t.title], ['1', '2', '3']);

      // Back in the playlist: an ordinary track again.
      await playlists.importYouTube(
        data([
          v('a', 'A - 1', 'x'),
          v('b', 'B - 2', 'x'),
          v('c', 'C - 3', 'x'),
        ]),
        videoExists: exists,
      );
      tracks = await playlists.tracks(again.playlist.id);
      expect([for (final t in tracks) t.videoRemoved], [false, false, false]);
    },
  );

  test(
    'when a missing video can\'t be checked, its track stays as it was',
    () async {
      await playlists.importYouTube(
        data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x')]),
      );
      final again = await playlists.importYouTube(
        data([v('a', 'A - 1', 'x')]),
        videoExists: (_) async => null,
      );
      expect(again.removedVideos, 0);
      final tracks = await playlists.tracks(again.playlist.id);
      expect(
        [for (final t in tracks) (t.title, t.videoRemoved)],
        [('1', false), ('2', false)],
      );
    },
  );

  test(
    'a video found removed while playing marks its playlist tracks',
    () async {
      final result = await playlists.importYouTube(
        data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x')]),
      );
      await youTube.markVideoRemoved('b');
      var tracks = await playlists.tracks(result.playlist.id);
      expect([for (final t in tracks) t.videoRemoved], [false, true]);
      expect(
        playlistHit(tracks[1], catalog, local, youTube).youtubeVideoId,
        isNull,
      );

      // Missing from the playlist next time: kept without asking YouTube again.
      final checked = <String>[];
      await playlists.importYouTube(
        data([v('a', 'A - 1', 'x')]),
        videoExists: (id) async {
          checked.add(id);
          return true;
        },
      );
      expect(checked, isEmpty);
      expect((await playlists.tracks(result.playlist.id)).length, 2);

      // Listed again: it's back.
      await playlists.importYouTube(
        data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x')]),
        videoExists: (_) async => true,
      );
      tracks = await playlists.tracks(result.playlist.id);
      expect([for (final t in tracks) t.videoRemoved], [false, false]);
      expect(youTube.isVideoRemoved('b'), isFalse);
    },
  );

  test('a playlist made from songs (the queue saved) keeps them in order; a phone-only file is '
      'found again by title and artist', () async {
    final music = await Directory('${root.path}/Music').create();
    // An empty file has no tags: artist and title come from its name.
    await File('${music.path}/Nieznany Zespół - Nowość.mp3').create();
    await local.addFolder(music.path);
    await local.scan();
    await catalog.ensureLoaded();
    final file = (await local.pendingSongs()).single;

    final saved = await playlists.create('Z kolejki', [
      // music.db links it to a video: that stays music.db's.
      SearchHit.main(catalog.byId(1)!, const []),
      // Played through a video the phone found.
      SearchHit.main(catalog.byId(2)!, const [], phoneMatch: 'gtc'),
      SearchHit.youTubeOnly(
        title: 'Klip',
        artistLabel: 'Ktoś',
        videoId: 'yt1',
        playlistVideoId: 'yt1',
      ),
      SearchHit.phoneOnly(file),
    ]);

    expect(saved.name, 'Z kolejki');
    expect(saved.source, isNull);
    expect(saved.trackCount, 4);
    expect(playlists.playlists.single.id, saved.id);
    final tracks = await playlists.tracks(saved.id);
    expect(
      [
        for (final t in tracks)
          (t.mainDbId, t.title, t.artist, t.youtubeVideoId),
      ],
      [
        (1, 'Małomiasteczkowy', 'Dawid Podsiadło', null),
        (2, 'Going to California', 'Led Zeppelin', null),
        (null, 'Klip', 'Ktoś', 'yt1'),
        (null, 'Nowość', 'Nieznany Zespół', null),
      ],
    );

    final phoneHit = playlistHit(tracks[3], catalog, local, youTube);
    expect(phoneHit.onPhone, isTrue);
    expect(phoneHit.phoneFiles.single.filePath, file.filePath);
    expect(
      playlistHit(tracks[2], catalog, local, youTube).youtubeVideoId,
      'yt1',
    );
  });

  test('songs added to a playlist made on the phone go at its end', () async {
    await catalog.ensureLoaded();
    final saved = await playlists.create('Pusta', const []);
    expect(saved.trackCount, 0);

    await playlists.addSongs(saved.id, [
      SearchHit.main(catalog.byId(2)!, const []),
    ]);
    await playlists.addSongs(saved.id, [
      SearchHit.main(catalog.byId(1)!, const []),
    ]);

    final tracks = await playlists.tracks(saved.id);
    expect(
      [for (final t in tracks) (t.position, t.mainDbId)],
      [(0, 2), (1, 1)],
    );
    expect(playlists.byId(saved.id)!.trackCount, 2);
  });

  test('a renamed playlist keeps its name when imported again and is sent '
      'to MusicDatabase', () async {
    final first = await playlists.importYouTube(data([v('a', 'A - 1', 'x')]));
    var changed = 0;
    playlists.onChanged = () => changed++;

    await playlists.rename(first.playlist.id, '  Po zmianie ');
    expect(playlists.byId(first.playlist.id)!.name, 'Po zmianie');
    expect(changed, 1);

    await playlists.rename(first.playlist.id, '   ');
    expect(playlists.byId(first.playlist.id)!.name, 'Po zmianie');

    await playlists.importYouTube(data([v('a', 'A - 1', 'x')]));
    expect(playlists.byId(first.playlist.id)!.name, 'Po zmianie');
  });

  test('"Edytuj": tracks reordered and taken out in one go', () async {
    await catalog.ensureLoaded();
    final saved = await playlists.create('Cztery', [
      for (final id in [1, 2, 4, 5])
        SearchHit.main(catalog.byId(id)!, const []),
    ]);
    var changed = 0;
    playlists.onChanged = () => changed++;

    await playlists.rearrange(saved.id, [3, 0, 2]);

    final tracks = await playlists.tracks(saved.id);
    expect(
      [for (final t in tracks) (t.position, t.mainDbId)],
      [(0, 5), (1, 1), (2, 4)],
    );
    expect(playlists.byId(saved.id)!.trackCount, 3);
    expect(changed, 1);
  });

  test('a track removed from a playlist leaves no gap', () async {
    await catalog.ensureLoaded();
    final saved = await playlists.create('Trzy', [
      SearchHit.main(catalog.byId(1)!, const []),
      SearchHit.main(catalog.byId(2)!, const []),
      SearchHit.main(catalog.byId(1)!, const []),
    ]);

    await playlists.removeTrack(saved.id, 0);

    final tracks = await playlists.tracks(saved.id);
    expect(
      [for (final t in tracks) (t.position, t.mainDbId)],
      [(0, 2), (1, 1)],
    );
    expect(playlists.byId(saved.id)!.trackCount, 2);
  });

  test('a track removed from an imported playlist stays out when it is imported again', () async {
    final first = await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x'), v('c', 'C - 3', 'x')]),
    );
    await playlists.removeTrack(first.playlist.id, 1);

    final again = await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x'), v('c', 'C - 3', 'x')]),
    );
    expect(
      [
        for (final t in await playlists.tracks(again.playlist.id))
          t.youtubeVideoId,
      ],
      ['a', 'c'],
    );

    // Deleted and imported anew, it's whole again.
    await playlists.delete(again.playlist.id);
    final fresh = await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x')]),
    );
    expect(await playlists.tracks(fresh.playlist.id), hasLength(2));
  });

  test('songs added to an imported playlist stay when it is imported again, '
      'after the track they followed', () async {
    await catalog.ensureLoaded();
    final first = await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x'), v('c', 'C - 3', 'x')]),
    );
    final id = first.playlist.id;
    await playlists.addSongs(id, [SearchHit.main(catalog.byId(2)!, const [])]);
    expect((await playlists.tracks(id)).last.added, isTrue);

    Future<List<Object?>> order() async => [
      for (final t in await playlists.tracks(id))
        t.added ? t.mainDbId : t.youtubeVideoId,
    ];

    await playlists.importYouTube(
      data([
        v('a', 'A - 1', 'x'),
        v('b', 'B - 2', 'x'),
        v('c', 'C - 3', 'x'),
        v('d', 'D - 4', 'x'),
      ]),
    );
    expect(await order(), ['a', 'b', 'c', 2, 'd']);

    // Its track gone from the source, it moves up to the one before.
    await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x'), v('d', 'D - 4', 'x')]),
    );
    expect(await order(), ['a', 'b', 2, 'd']);
    expect(playlists.byId(id)!.trackCount, 4);

    // Taken out again, it's simply gone: nothing at the source to leave out.
    await playlists.removeTrack(id, 2);
    await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x'), v('d', 'D - 4', 'x')]),
    );
    expect(await order(), ['a', 'b', 'd']);
  });

  test(
    'a song added to a playlist made on the phone is not marked as added',
    () async {
      await catalog.ensureLoaded();
      final saved = await playlists.create('Pusta', const []);
      await playlists.addSongs(saved.id, [
        SearchHit.main(catalog.byId(2)!, const []),
      ]);
      expect((await playlists.tracks(saved.id)).single.added, isFalse);
    },
  );
}
