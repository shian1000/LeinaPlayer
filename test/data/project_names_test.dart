import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/project_names.dart';

void main() {
  final projects = [
    Project('Kaunas Acoustics'),
    Project(
      'Tiny Desk',
      aliases: 'NPR Music Tiny Desk Concert, Tiny Desk Concert',
      channels: 'NPR Music',
    ),
    Project('Like a Version', channels: 'triple j'),
    Project('Męskie Granie'),
  ];

  (String, String, String)? read(String artist, String title) {
    final reading = readProject(artist, title, projects);
    return reading == null
        ? null
        : (reading.project.name, reading.artist, reading.title);
  }

  test('the dictionary\'s spellings are split by commas', () {
    expect(projects[1].spellings, [
      'Tiny Desk',
      'NPR Music Tiny Desk Concert',
      'Tiny Desk Concert',
    ]);
    expect(projects[1].channels, ['NPR Music']);
    expect(projects[0].aliases, isEmpty);
  });

  test('a title naming a project loses it, with its bracket', () {
    expect(read('Wolf Alice', 'Boys (Like a Version)'), (
      'Like a Version',
      'Wolf Alice',
      'Boys',
    ));
    expect(read('Nosowska', 'Sobie i Wam (Męskie Granie 2018)'), (
      'Męskie Granie',
      'Nosowska',
      'Sobie i Wam',
    ));
    expect(read('Nosowska', 'Boję się - Live at Męskie Granie'), (
      'Męskie Granie',
      'Nosowska',
      'Boję się',
    ));
    // Something else in the bracket keeps it.
    expect(read('Nosowska', 'Boję się (Męskie Granie, Żywiec)'), (
      'Męskie Granie',
      'Nosowska',
      'Boję się (Żywiec)',
    ));
  });

  test('a channel as the artist leaves who plays in the title', () {
    expect(read('triple j', 'Wolf Alice - Boys | Like a Version'), (
      'Like a Version',
      'Wolf Alice',
      'Boys',
    ));
    expect(read('NPR Music', 'Daughter: Tiny Desk Concert'), (
      'Tiny Desk',
      'Daughter',
      'Tiny Desk Concert',
    ));
    expect(read('Daughter', 'NPR Music Tiny Desk Concert'), (
      'Tiny Desk',
      'Daughter',
      'Tiny Desk Concert',
    ));
  });

  test('an artist naming a project: set apart it goes, part of a name it '
      'stays', () {
    expect(read('Kaunas Acoustics : Liūdni slibinai', 'Pieno Fabrikėlis'), (
      'Kaunas Acoustics',
      'Liūdni slibinai',
      'Pieno Fabrikėlis',
    ));
    expect(read('Męskie Granie Orkiestra 2016', 'Wojenka'), (
      'Męskie Granie',
      'Męskie Granie Orkiestra 2016',
      'Wojenka',
    ));
    expect(read('Męskie Granie', 'Sobie i Wam'), (
      'Męskie Granie',
      'Męskie Granie',
      'Sobie i Wam',
    ));
  });

  test('only whole spellings count', () {
    expect(read('Nosowska', 'Sobie i Wam'), isNull);
    expect(read('Kaunas', 'Acoustics Session'), isNull);
    expect(read('Wolf Alice', 'Boys (Version)'), isNull);
    expect(read('Tiny Desks', 'Song'), isNull);
    expect(
      readProject('Wolf Alice', 'Boys (Like a Version)', const []),
      isNull,
    );
  });

  test(
    'a capital "I" next to the project is typed for "|"; a show is a whole set',
    () {
      // MusicDatabase's test_a_take_away_show_with_an_i_typed_for_the_bar.
      final shows = [
        Project(
          'Take Away Show',
          aliases: 'A Take Away Show',
          channels: 'Blogothèque, La Blogothèque',
        ),
      ];
      (String, String)? readShow(String artist, String title) {
        final reading = readProject(artist, title, shows);
        return reading == null ? null : (reading.artist, reading.title);
      }

      expect(readShow('Blogothèque', 'The Dø I A Take Away Show'), (
        'The Dø',
        'A Take Away Show',
      ));
      expect(readShow('The Dø', 'A Take Away Show'), (
        'The Dø',
        'A Take Away Show',
      ));
      // An "I" not next to the project is a word.
      expect(
        readShow('Blogothèque', 'Phoenix - I Wanna Be | A Take Away Show'),
        ('Phoenix', 'I Wanna Be'),
      );
      // The project as the artist and a show in the title: who plays is the rest, playing the
      // whole set — not a song "Phoenix".
      expect(readShow('A Take Away Show', 'Phoenix | A Take Away Show'), (
        'Phoenix',
        'A Take Away Show',
      ));
    },
  );
}
