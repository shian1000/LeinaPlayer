import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/startup_covers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  late StartupCovers covers;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('startup_covers_test');
    covers = StartupCovers(storageRoot: () async => root);
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> cached(String name) async =>
      File('${root.path}/$name')..writeAsBytesSync([1, 2, 3]);

  List<String> ownFiles() => [
    for (final f in Directory(
      '${root.path}/startup_covers',
    ).listSync().whereType<File>())
      f.path,
  ];

  test('a cache file is remembered by its path, for the same song only, '
      'across starts', () async {
    final file = await cached('a.img');
    await covers.remember(
      'home:lib:recent#0',
      'Over You|Jacob Collier',
      FileImage(file),
      '42',
    );
    await covers.flush();

    final next = StartupCovers(storageRoot: () async => root);
    await next.load();
    final shown = next.of('home:lib:recent#0', 'Over You|Jacob Collier');
    expect(shown?.file.path, file.path);
    expect(shown?.seed, '42');
    expect(next.of('home:lib:recent#0', 'Kukushka|Kino'), isNull);
    expect(next.of('home:lib:recent#1', 'Over You|Jacob Collier'), isNull);
  });

  test("a song file's own cover is kept as a file of its own, deleted once "
      'replaced', () async {
    await covers.remember(
      'mini',
      'a',
      MemoryImage(Uint8List.fromList([9, 9])),
      's',
    );
    final own = covers.of('mini', 'a')!.file;
    expect(own.readAsBytesSync(), [9, 9]);
    expect(ownFiles(), [own.path]);

    // The same song again: not written twice.
    await covers.remember(
      'mini',
      'a',
      MemoryImage(Uint8List.fromList([9, 9])),
      's',
    );
    expect(ownFiles(), [own.path]);

    final file = await cached('b.img');
    await covers.remember('mini', 'b', FileImage(file), 's');
    expect(covers.of('mini', 'b')?.file.path, file.path);
    expect(ownFiles(), isEmpty);
  });

  test('a colour that comes before its cover is kept with it; clearing '
      'forgets everything', () async {
    const color = Color(0xFF336699);
    covers.rememberColor('mini', 'a', color);
    await covers.remember('mini', 'a', FileImage(await cached('a.img')), 's');
    expect(covers.of('mini', 'a')?.color, color);

    await covers.remember(
      'home:x#0',
      'b',
      MemoryImage(Uint8List.fromList([1])),
      's',
    );
    await covers.clear();
    expect(covers.of('mini', 'a'), isNull);
    expect(ownFiles(), isEmpty);
    final next = StartupCovers(storageRoot: () async => root);
    await next.load();
    expect(next.of('mini', 'a'), isNull);
  });

  test("a card's texts are kept with its cover, and shown for its place "
      'whichever song comes', () async {
    covers.rememberTexts('home:r#0', 'a', 'Люди (Lyudi)', 'Злінi');
    await covers.remember(
      'home:r#0',
      'a',
      FileImage(await cached('a.img')),
      's',
    );
    covers.rememberTexts('home:r#0', 'b', 'Inna', 'Ktoś');
    await covers.flush();

    final next = StartupCovers(storageRoot: () async => root);
    await next.load();
    final shown = next.at('home:r#0');
    expect(shown?.title, 'Люди (Lyudi)');
    expect(shown?.subtitle, 'Злінi');
    expect(next.of('home:r#0', 'b'), isNull);
  });
}
