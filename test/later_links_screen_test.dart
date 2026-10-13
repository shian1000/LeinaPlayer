import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/incoming_links.dart';
import 'package:music_database_app/src/data/later_links.dart';
import 'package:music_database_app/src/screens/later_links_screen.dart';
import 'package:music_database_app/src/theme.dart';

void main() {
  late MemoryLaterStore store;
  late LaterLinks later;
  late List<String> opened;

  setUp(() async {
    store = MemoryLaterStore();
    later = LaterLinks(store);
    opened = [];
    final ola = await store.addPerson('Ola');
    final adam = await store.addPerson('Adam');
    store
      ..save(
        url: 'https://youtu.be/aaaaaaaaaaa',
        service: LinkService.youtube,
        kind: 'Film z YouTube',
        personId: ola,
      )
      ..save(
        url: 'https://open.spotify.com/track/bbbbbbbbbbbbbbbbbbbbbb',
        service: LinkService.spotify,
        kind: 'Utwór ze Spotify',
        personId: adam,
      );
    await later.load();
    // Described already, so the screen looks nothing up.
    for (final link in later.links) {
      await later.setDescription(
        link,
        link.service == LinkService.youtube ? 'Wideo Oli' : 'Utwór Adama',
        'Wykonawca',
      );
    }
  });

  tearDown(() => later.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      LaterLinksScope(
        notifier: later,
        child: MaterialApp(
          theme: buildAppTheme(dummifyTheme),
          home: LaterLinksScreen(onOpen: opened.add),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows everyone\'s links, filters by person, opens one', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Wideo Oli'), findsOneWidget);
    expect(find.text('Utwór Adama'), findsOneWidget);
    expect(find.textContaining('od: Ola'), findsOneWidget);

    await tester.tap(find.text('Adam (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Wideo Oli'), findsNothing);
    expect(find.text('Utwór Adama'), findsOneWidget);

    await tester.tap(find.text('Utwór Adama'));
    await tester.pumpAndSettle();
    expect(opened, ['https://open.spotify.com/track/bbbbbbbbbbbbbbbbbbbbbb']);
    expect(
      later.links.firstWhere((l) => l.title == 'Utwór Adama').opened,
      isTrue,
    );
  });

  testWidgets('the menu removes a link', (tester) async {
    await pump(tester);
    await tester.longPress(find.text('Wideo Oli'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń z „Na później”'));
    await tester.pumpAndSettle();
    expect(find.text('Wideo Oli'), findsNothing);
    expect(later.links, hasLength(1));
  });

  testWidgets('nothing saved: explains how to save', (tester) async {
    for (final person in [...later.people]) {
      await later.removePerson(person);
    }
    await pump(tester);
    expect(find.textContaining('Zapisz na później'), findsOneWidget);
  });
}
