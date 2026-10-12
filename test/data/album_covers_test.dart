import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/album_covers.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _itunesAlbum(String artist, String album) => {
  'artistName': artist,
  'collectionName': album,
  'artworkUrl100': 'https://is1.mzstatic.com/$album/100x100bb.jpg',
};

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late SourceSettings settings;
  late List<Uri> asked;
  late List<Uri> downloaded;
  late Map<String, Object?> Function(Uri) answer;
  late Set<String> missingImages;
  late int imageSize;
  late bool onWifi;

  AlbumCovers newCovers({Map<String, Uint8List> embedded = const {}}) =>
      AlbumCovers(
        local.database,
        settings,
        storageRoot: () async => root,
        getJson: (uri) async {
          asked.add(uri);
          return answer(uri);
        },
        getBytes: (uri) async {
          downloaded.add(uri);
          if (missingImages.contains(uri.toString())) return null;
          return Uint8List(imageSize);
        },
        onWifi: () async => onWifi,
        readEmbedded: (path) async => embedded[path],
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('album_covers_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    settings = SourceSettings();
    await settings.load();
    asked = [];
    downloaded = [];
    answer = (_) => {'results': <Object?>[]};
    missingImages = {};
    imageSize = 1000;
    onWifi = true;
  });

  tearDown(() async {
    settings.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  CoverRequest song(
    String title, {
    String artist = 'Hey',
    String? album = 'Karma',
    String? videoId,
    String? filePath,
  }) => CoverRequest(
    artist: artist,
    title: title,
    album: album,
    videoId: videoId,
    filePath: filePath,
    seed: title,
  );

  group('lookUpItunes', () {
    test(
      'takes the album whose title and artist match, at both sizes',
      () async {
        final urls = await lookUpItunes(song('Moja i twoja nadzieja'), (
          uri,
        ) async {
          expect(uri.queryParameters['entity'], 'album');
          expect(uri.queryParameters['term'], 'Hey Karma');
          return {
            'results': [
              _itunesAlbum('Hey Violet', 'Karma'),
              _itunesAlbum('Hey', 'Karmageddon'),
              _itunesAlbum('Hey', 'Karma (Remastered)'),
            ],
          };
        });
        expect(urls!.small, contains('250x250bb'));
        expect(urls.large, contains('600x600bb'));
        expect(urls.small, contains('Karma (Remastered)'));
      },
    );

    test('a song without an album is looked up as a song', () async {
      final urls = await lookUpItunes(song('Teksański', album: 'Singles'), (
        uri,
      ) async {
        expect(uri.queryParameters['entity'], 'song');
        return {
          'results': [
            {
              'artistName': 'Hey',
              'trackName': 'Teksański',
              'artworkUrl100': 'https://x/100x100bb.jpg',
            },
          ],
        };
      });
      expect(urls?.large, 'https://x/600x600bb.jpg');
    });

    test('"<album> - Single" is that album', () async {
      final urls = await lookUpItunes(
        song('A'),
        (_) async => {
          'results': [_itunesAlbum('Hey', 'Karma - Single')],
        },
      );
      expect(urls, isNotNull);
    });
  });

  group('lookUpDeezer', () {
    test(
      'falls back to a plain query when the exact one finds nothing',
      () async {
        final queries = <String>[];
        final urls = await lookUpDeezer(song('Teksański'), (uri) async {
          queries.add(uri.queryParameters['q']!);
          if (queries.length == 1) return {'data': <Object?>[]};
          return {
            'data': [
              {
                'title': 'Karma',
                'artist': {'name': 'Hey'},
                'cover_medium': 'https://d/250.jpg',
                'cover_big': 'https://d/500.jpg',
              },
            ],
          };
        });
        expect(queries, ['artist:"Hey" album:"Karma"', 'Hey Karma']);
        expect(urls?.small, 'https://d/250.jpg');
        expect(urls?.large, 'https://d/500.jpg');
      },
    );

    test('an over-quota answer is a failure, not "no cover"', () {
      expect(
        lookUpDeezer(
          song('Teksański'),
          (_) async => {
            'error': {'code': 4},
          },
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });

  test('a cover inside the phone file wins and needs no internet', () async {
    final covers = newCovers(embedded: {'/m/a.mp3': Uint8List(10)});
    final image = await covers.resolve(song('A', filePath: '/m/a.mp3'));
    expect(image, isA<MemoryImage>());
    expect(asked, isEmpty);
    expect(downloaded, isEmpty);
  });

  test(
    'songs of one album share one lookup and one image, also after a restart',
    () async {
      answer = (_) => {
        'results': [_itunesAlbum('Hey', 'Karma')],
      };
      final covers = newCovers();
      final first = await covers.resolve(song('A'));
      final second = await covers.resolve(song('B'));
      expect(first, isA<FileImage>());
      expect((second! as FileImage).file.path, (first! as FileImage).file.path);
      expect(asked, hasLength(1));
      expect(downloaded, hasLength(1));
      expect(covers.cachedCount, 1);

      // The full player wants the large one.
      await covers.resolve(song('A'), large: true);
      expect(downloaded.last.toString(), contains('600x600bb'));

      final restarted = newCovers();
      await restarted.load();
      expect(await restarted.resolve(song('C')), isA<FileImage>());
      expect(asked, hasLength(1));
      expect(downloaded, hasLength(2));
    },
  );

  test('no cover anywhere falls through to the YouTube thumbnail', () async {
    final covers = newCovers();
    missingImages = {'https://i.ytimg.com/vi/vid/maxresdefault.jpg'};
    final small = await covers.resolve(song('A', videoId: 'vid'));
    expect(small, isA<FileImage>());
    // iTunes and Deezer (exact + plain query) said no.
    expect(asked, hasLength(3));
    expect(downloaded.last.toString(), endsWith('/vid/mqdefault.jpg'));

    // "No cover" is remembered: not asked again.
    await covers.resolve(song('B', videoId: 'vid'), large: true);
    expect(asked, hasLength(3));
    // No high-resolution thumbnail → the small one.
    expect(downloaded.map((u) => u.pathSegments.last), [
      'mqdefault.jpg',
      'maxresdefault.jpg',
    ]);
  });

  test('switched-off sources are skipped, in the user\'s order', () async {
    await settings.setCoverSource(CoverSource.itunes, false);
    await settings.setCoverSource(CoverSource.deezer, false);
    await settings.setCoverOrder([
      CoverSource.youtube,
      ...CoverSource.values.where((s) => s != CoverSource.youtube),
    ]);
    final covers = newCovers(embedded: {'/m/a.mp3': Uint8List(10)});
    final image = await covers.resolve(
      song('A', videoId: 'vid', filePath: '/m/a.mp3'),
    );
    expect(image, isA<FileImage>());
    expect(asked, isEmpty);
  });

  test(
    'the cache keeps to the MB limit, dropping the least recently shown',
    () async {
      await settings.setCoverCacheLimitMb(1);
      await settings.setCoverSource(CoverSource.itunes, false);
      await settings.setCoverSource(CoverSource.deezer, false);
      imageSize = 600 * 1024;
      final covers = newCovers();
      final a = await covers.resolve(song('A', videoId: 'a')) as FileImage;
      await covers.resolve(song('B', videoId: 'b'));
      expect(covers.cachedCount, 1);
      expect(a.file.existsSync(), isFalse);

      await covers.clear();
      expect(covers.cachedCount, 0);
    },
  );

  test(
    '"only on Wi-Fi" shows cached covers but downloads nothing new',
    () async {
      await settings.setCoverSource(CoverSource.itunes, false);
      await settings.setCoverSource(CoverSource.deezer, false);
      final covers = newCovers();
      await covers.resolve(song('A', videoId: 'a'));
      await settings.setCoverWifiOnly(true);
      onWifi = false;
      expect(await covers.resolve(song('A', videoId: 'a')), isA<FileImage>());
      expect(await covers.resolve(song('B', videoId: 'b')), isNull);
      expect(downloaded, hasLength(1));
    },
  );

  test(
    'the notification gets the cover as a file, also a phone file\'s own',
    () async {
      await settings.setCoverSource(CoverSource.itunes, false);
      await settings.setCoverSource(CoverSource.deezer, false);
      final covers = newCovers(
        embedded: {
          '/m/a.mp3': Uint8List.fromList([1, 2, 3]),
        },
      );
      final fromFile = await covers.artFile(song('A', filePath: '/m/a.mp3'));
      expect(File.fromUri(fromFile!).readAsBytesSync(), [1, 2, 3]);

      final fromYouTube = await covers.artFile(song('B', videoId: 'v'));
      expect(fromYouTube!.scheme, 'file');
      expect(downloaded.single.pathSegments.last, 'maxresdefault.jpg');

      expect(await covers.artFile(song('C')), isNull);
    },
  );

  test('a resolved cover is known at once next time', () async {
    final covers = newCovers(embedded: {'/m/a.mp3': Uint8List(10)});
    final request = song('A', filePath: '/m/a.mp3');
    expect(covers.known(request), isNull);
    final image = await covers.resolve(request);
    expect(covers.known(request), same(image));
    expect(covers.known(request, large: true), isNull);
    await covers.clear();
    expect(covers.known(request), isNull);
  });

  test('a missing high-resolution thumbnail is asked for once, also after a restart', () async {
    await settings.setCoverSource(CoverSource.itunes, false);
    await settings.setCoverSource(CoverSource.deezer, false);
    missingImages = {'https://i.ytimg.com/vi/vid/maxresdefault.jpg'};
    final covers = newCovers();
    await covers.resolve(song('A', videoId: 'vid'), large: true);
    await covers.resolve(song('A', videoId: 'vid'), large: true);
    final restarted = newCovers();
    await restarted.load();
    await restarted.resolve(song('A', videoId: 'vid'), large: true);
    expect(downloaded.map((u) => u.pathSegments.last), [
      'maxresdefault.jpg',
      'mqdefault.jpg',
    ]);
  });

  testWidgets('the notification gets the filtered cover as a picture file', (
    tester,
  ) async {
    final png = await tester.runAsync(() => _png(const ui.Color(0xFFD02020)));
    final covers = newCovers(embedded: {'/m/a.mp3': png!});
    final art = await tester.runAsync(
      () => covers.artFile(
        song('A', filePath: '/m/a.mp3'),
        filter: CoverFilter.lain,
      ),
    );
    final bytes = File.fromUri(art!).readAsBytesSync();
    // A PNG of the filtered cover, not the file's own picture.
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
    expect(bytes, isNot(png));
  });

  testWidgets('the player\'s colour comes from the cover', (tester) async {
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // A red cover with a black frame: the frame mustn't darken the colour much.
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 40, 40),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(8, 8, 24, 24),
        ui.Paint()..color = const ui.Color(0xFFD02020),
      );
      final image = await recorder.endRecording().toImage(40, 40);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final covers = newCovers(embedded: {'/m/a.mp3': png!});
    final color = await tester.runAsync(
      () => covers.colorOf(song('A', filePath: '/m/a.mp3')),
    );
    expect((color!.r * 255).round(), greaterThan(150));
    expect((color.g * 255).round(), lessThan(70));
  });

  test('"Singles" is not an album', () {
    expect(song('A', album: 'Singles').lookupKey, startsWith('song:'));
    expect(song('A').lookupKey, 'album:hey|karma');
    expect(song('A').lookupKey, song('B').lookupKey);
  });
}

Future<Uint8List> _png(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 40, 40), ui.Paint()..color = color);
  final image = await recorder.endRecording().toImage(40, 40);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
