import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/album_covers.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/collection_cover.dart';
import 'package:music_database_app/src/widgets/cover_art.dart';
import 'package:music_database_app/src/widgets/song_cover.dart';

void main() {
  CoverRequest song(String title, String? album) =>
      CoverRequest(artist: 'Lain', title: title, album: album, seed: title);

  Future<void> show(WidgetTester tester, List<CoverRequest> songs) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(dummifyTheme),
          home: Scaffold(
            body: Center(
              child: CollectionCover(songs: songs, seed: 'Moja', size: 200),
            ),
          ),
        ),
      );

  testWidgets('a collage of four different albums', (tester) async {
    await show(tester, [
      song('1', 'A'),
      song('2', 'A'),
      song('3', 'B'),
      song('4', null),
      song('5', 'C'),
      song('6', 'D'),
    ]);
    final covers = tester
        .widgetList<SongCover>(find.byType(SongCover))
        .map((c) => c.cover.title);
    expect(covers, ['1', '3', '4', '5']);
    expect(tester.getSize(find.byType(SongCover).first), const Size(100, 100));
  });

  testWidgets('fewer albums: the first song\'s cover; none: the placeholder', (
    tester,
  ) async {
    await show(tester, [song('1', 'A'), song('2', 'B'), song('3', 'A')]);
    expect(find.byType(SongCover), findsOneWidget);
    expect(tester.getSize(find.byType(SongCover)), const Size(200, 200));

    await show(tester, const []);
    expect(find.byType(SongCover), findsNothing);
    expect(find.byType(CoverArt), findsOneWidget);
  });
}
