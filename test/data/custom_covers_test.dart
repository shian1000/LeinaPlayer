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

  testWidgets('a picked cover is kept square under its hash and read back', (
    tester,
  ) async {
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('custom_covers_test');
      Future<Directory> dir() async => Directory('${root.path}/covers');
      final covers = CustomCovers(directory: dir);
      await covers.load();
      expect(covers.fileFor(null), isNull);

      final wide = await covers.add(await picture(1600, 900));
      final file = covers.fileFor(wide)!;
      expect(CustomCovers.hashOf(await file.readAsBytes()), wide);
      final image = await decode(file);
      expect(
        (image.width, image.height),
        (CustomCovers.side, CustomCovers.side),
      );

      // A small picture isn't blown up.
      final tall = await covers.add(await picture(100, 300));
      expect((await decode(covers.fileFor(tall)!)).width, 100);

      final reloaded = CustomCovers(directory: dir);
      await reloaded.load();
      expect(reloaded.fileFor(wide)?.path, file.path);
      expect((await reloaded.read(tall))!.jpeg, isFalse);

      await expectLater(covers.add([1, 2, 3]), throwsA(anything));

      covers.dispose();
      reloaded.dispose();
      await root.delete(recursive: true);
    });
  });

  test(
    'a downloaded cover must match its hash; unused ones go after a day',
    () async {
      root = await Directory.systemTemp.createTemp('custom_covers_test');
      final covers = CustomCovers(
        directory: () async => Directory('${root.path}/covers'),
      );
      await covers.load();
      final used = [1, 2, 3];
      final unused = [4, 5, 6];
      final usedHash = CustomCovers.hashOf(used);
      final unusedHash = CustomCovers.hashOf(unused);
      await expectLater(
        covers.store(usedHash, unused, jpeg: false),
        throwsArgumentError,
      );
      await covers.store(usedHash, used, jpeg: true);
      await covers.store(unusedHash, unused, jpeg: false);
      expect((await covers.read(usedHash))!.jpeg, isTrue);

      // Picked moments ago: kept although nothing refers to it yet.
      await covers.prune({usedHash});
      expect(covers.fileFor(unusedHash), isNotNull);

      await covers.prune({
        usedHash,
      }, now: DateTime.now().add(const Duration(days: 2)));
      expect(covers.fileFor(unusedHash), isNull);
      expect(covers.fileFor(usedHash), isNotNull);

      covers.dispose();
      await root.delete(recursive: true);
    },
  );
}
