import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/custom_covers.dart';

void main() {
  late Directory root;

  Future<List<int>> picture(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF3060A0),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  Future<ui.Image> decode(File file) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  testWidgets(
    'a picked cover is kept square, replaced, read back and removed',
    (tester) async {
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('custom_covers_test');
        Future<Directory> dir() async => Directory('${root.path}/covers');
        final covers = CustomCovers(directory: dir);
        await covers.load();
        expect(covers.fileFor('playlist-1'), isNull);

        await covers.set('playlist-1', await picture(1600, 900));
        final first = covers.fileFor('playlist-1')!;
        final image = await decode(first);
        expect(
          (image.width, image.height),
          (CustomCovers.side, CustomCovers.side),
        );

        // A small picture isn't blown up; the old file goes.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await covers.set('playlist-1', await picture(100, 300));
        final second = covers.fileFor('playlist-1')!;
        expect(second.path, isNot(first.path));
        expect(await first.exists(), isFalse);
        expect(((await decode(second)).width), 100);

        final reloaded = CustomCovers(directory: dir);
        await reloaded.load();
        expect(reloaded.fileFor('playlist-1')?.path, second.path);

        await reloaded.remove('playlist-1');
        expect(reloaded.fileFor('playlist-1'), isNull);
        expect(await second.exists(), isFalse);

        await expectLater(covers.set('mood-u1', [1, 2, 3]), throwsA(anything));
        expect(covers.fileFor('mood-u1'), isNull);

        covers.dispose();
        reloaded.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
