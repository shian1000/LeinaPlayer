import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/cover_credit.dart';
import 'package:music_database_app/src/data/version_names.dart';

void main() {
  test('reads a version from its bracket or a spaced-dash suffix', () {
    expect(readVersion('Boję się (Live)'), (
      title: 'Boję się',
      kind: VersionKind.live,
      label: null,
    ));
    expect(readVersion('Recover (Cid Rim Remix)'), (
      title: 'Recover',
      kind: VersionKind.remix,
      label: 'Cid Rim Remix',
    ));
    expect(
      readVersion('Matylda (na żywo, akustycznie)')?.kind,
      VersionKind.live,
    );
    expect(readVersion('Engel (extended version)')?.kind, VersionKind.extended);
    expect(readVersion('Song [Demo]')?.kind, VersionKind.demo);
    expect(readVersion('Song（Acoustic）')?.kind, VersionKind.acoustic);
    expect(readVersion('Song - Acoustic Version'), (
      title: 'Song',
      kind: VersionKind.acoustic,
      label: 'Acoustic Version',
    ));
    expect(readVersion('Song (Live) (Remastered)')?.kind, VersionKind.live);
    expect(readVersion('Creep (Live) (Radiohead cover)'), (
      title: 'Creep (Radiohead cover)',
      kind: VersionKind.live,
      label: null,
    ));
  });

  test(
    'a release of the same recording, a credit or no marker: no version',
    () {
      for (final title in [
        'Song (Radio Edit)',
        'Song (Album Version)',
        'Song (2011 Remastered)',
        'Dziwny jest ten świat (Bonus track)',
        'Creep (Radiohead cover)',
        'Song (feat. Mix Master)',
        'Live Forever',
        'Best Version Ever',
        '(Live)',
        '',
        null,
      ]) {
        expect(readVersion(title), isNull, reason: title);
      }
    },
  );

  test('kinds by value and their labels', () {
    expect(VersionKind.of('live'), VersionKind.live);
    expect(VersionKind.of('something new'), VersionKind.other);
    expect(const SongVersion(VersionKind.live).marker, 'Live');
    expect(
      titleWithVersion(
        'Recover',
        const SongVersion(VersionKind.remix, label: 'Cid Rim Remix'),
      ),
      'Recover (Cid Rim Remix)',
    );
    expect(titleWithVersion('Recover', null), 'Recover');
    // As song_names.dart shows a cover's version, and readVersion reads it back.
    final shown = titleWithCover(
      titleWithVersion('Creep', const SongVersion(VersionKind.live)),
      const CoverOf('Radiohead'),
    );
    expect(shown, 'Creep (Live) (Radiohead cover)');
    expect(readVersion(shown)?.kind, VersionKind.live);
  });
}
