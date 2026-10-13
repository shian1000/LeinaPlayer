import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/incoming_links.dart';
import 'package:music_database_app/src/data/later_links.dart';

void main() {
  late MemoryLaterStore store;
  late LaterLinks later;

  setUp(() {
    store = MemoryLaterStore();
    later = LaterLinks(store);
  });

  tearDown(() => later.dispose());

  test('links come newest first, people alphabetically', () async {
    final ola = await store.addPerson('Ola');
    final adam = await store.addPerson('adam');
    store
      ..save(
        url: 'https://youtu.be/aaaaaaaaaaa',
        service: LinkService.youtube,
        kind: 'Film z YouTube',
        personId: ola,
        at: DateTime(2026, 10, 1),
      )
      ..save(
        url: 'https://open.spotify.com/track/x',
        service: LinkService.spotify,
        kind: 'Utwór ze Spotify',
        personId: adam,
        at: DateTime(2026, 10, 2),
      );
    await later.load();

    expect(later.people.map((p) => p.name), ['adam', 'Ola']);
    expect(later.links.map((l) => l.service), [
      LinkService.spotify,
      LinkService.youtube,
    ]);
    expect(later.personOf(later.links.first)!.name, 'adam');
    expect(later.unopenedCount, 2);
  });

  test('a person with the same name is not added twice', () async {
    final first = await later.addPerson('Ola');
    final again = await later.addPerson('  ola ');
    expect(again, first);
    expect(later.people, hasLength(1));
  });

  test('opening, describing and moving a link are kept', () async {
    final ola = await later.addPerson('Ola');
    final ania = await later.addPerson('Ania');
    store.save(
      url: 'https://youtu.be/aaaaaaaaaaa',
      service: LinkService.youtube,
      kind: 'Film z YouTube',
      personId: ola,
    );
    await later.load();

    await later.setOpened(later.links.single, true);
    await later.setDescription(later.links.single, 'Song', 'Artist');
    await later.setPerson(later.links.single, ania);
    final link = later.links.single;
    expect(link.opened, isTrue);
    expect(later.unopenedCount, 0);
    expect((link.title, link.artist), ('Song', 'Artist'));
    expect(link.personId, ania);

    await later.setOpened(link, false);
    expect(later.links.single.opened, isFalse);
  });

  test('removing a person removes the links from them', () async {
    final ola = await later.addPerson('Ola');
    final ania = await later.addPerson('Ania');
    for (final person in [ola, ania]) {
      store.save(
        url: 'https://youtu.be/aaaaaaaaaaa',
        service: LinkService.youtube,
        kind: 'Film z YouTube',
        personId: person,
      );
    }
    await later.load();

    await later.removePerson(later.people.firstWhere((p) => p.id == ola));
    expect(later.people.map((p) => p.name), ['Ania']);
    expect(later.links.single.personId, ania);

    await later.remove(later.links.single);
    expect(later.links, isEmpty);
  });

  test('stored JSON from the native side is read', () {
    final link = LaterLink.fromJson({
      'id': '1',
      'url': 'https://open.spotify.com/album/x',
      'service': 'spotify',
      'kind': 'Album ze Spotify',
      'personId': 'p',
      'savedAt': 1760000000000,
    });
    expect(link.service, LinkService.spotify);
    expect(link.savedAt, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    expect(link.opened, isFalse);
    expect(link.title, isNull);
  });
}
