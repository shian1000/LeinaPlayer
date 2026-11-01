import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/download_files.dart';

void main() {
  test(
    'a song\'s file name: "Artist - Title" without what storage refuses',
    () {
      expect(downloadBaseName('Кино', 'Группа крови'), 'Кино - Группа крови');
      expect(
        downloadBaseName('AC/DC', 'What? "Now": <1|2>'),
        'AC_DC - What_ _Now__ _1_2_',
      );
      expect(downloadBaseName('', 'Title'), 'Title');
      expect(downloadBaseName(' ', ' ..'), 'Utwór');
      expect(downloadBaseName('A', 'x' * 300).length, 120);
    },
  );

  test('extensions and folders', () {
    expect(fileExtension('/a/7.flac'), '.flac');
    expect(fileExtension('/a.b/7'), '');
    expect(isInFolder('/m/Music/a.mp3', '/m/Music'), isTrue);
    expect(isInFolder('/m/Music2/a.mp3', '/m/Music'), isFalse);
    expect(isInFolder('/m/Music/a.mp3', '/m/Music/'), isTrue);
  });
}
