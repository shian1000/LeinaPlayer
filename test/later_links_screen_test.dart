import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/incoming_links.dart';
import 'package:music_database_app/src/data/later_links.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/screens/later_links_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MemoryLaterStore store;
  late LaterLinks later;
  late List<String> opened;
  late SourceSettings settings;
  late List<(String, bool)> queued;
  late bool queueWorks;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SourceSettings();
    await settings.load();
    queued = [];
    queueWorks = true;
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
      SourceSettingsScope(
        notifier: settings,
        child: LaterLinksScope(
          notifier: later,
          child: MaterialApp(
            theme: buildAppTheme(dummifyTheme),
            home: LaterLinksScreen(
              onOpen: opened.add,
              onQueue: (link, {required next}) async {
                queued.add((link.title!, next));
                return queueWorks;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  LaterLink wideo() => later.links.firstWhere((l) => l.title == 'Wideo Oli');

  Future<void> queueFromMenu(WidgetTester tester) async {
    await tester.longPress(find.text('Wideo Oli'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj do kolejki'));
    await tester.pumpAndSettle();
  }

  group('a queued link', () {
    testWidgets('counts as listened to by default', (tester) async {
      await pump(tester);
      expect(settings.laterQueuedListened, isTrue);
      await queueFromMenu(tester);
      expect(queued, [('Wideo Oli', false)]);
      expect(wideo().opened, isTrue);
    });

    testWidgets('dragged right: too, as Odtwarzanie says', (tester) async {
      await pump(tester);
      await tester.drag(find.text('Wideo Oli'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(queued, [('Wideo Oli', true)]);
      expect(wideo().opened, isTrue);
    });

    testWidgets('stays as it was when it could not be queued', (tester) async {
      queueWorks = false;
      await pump(tester);
      await queueFromMenu(tester);
      expect(queued, hasLength(1));
      expect(wideo().opened, isFalse);
    });

    testWidgets('stays unlistened with the setting switched off, remembered', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Ustawienia „Na później”'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Po dodaniu do kolejki, oznacz jako odsłuchane'),
      );
      await tester.pumpAndSettle();
      expect(settings.laterQueuedListened, isFalse);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await queueFromMenu(tester);
      expect(queued, hasLength(1));
      expect(wideo().opened, isFalse);

      final again = SourceSettings();
      await tester.runAsync(again.load);
      expect(again.laterQueuedListened, isFalse);
    });
  });

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
    expect(find.text('Dodaj do kolejki'), findsOneWidget);
    expect(find.text('Odtwórz jako następny'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Usuń z „Na później”'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    await tester.tap(find.text('Usuń z „Na później”'));
    await tester.pumpAndSettle();
    expect(find.text('Wideo Oli'), findsNothing);
    expect(later.links, hasLength(1));
  });

  testWidgets('dragging a row left removes the link', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Wideo Oli'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Wideo Oli'), findsNothing);
    expect(later.links, hasLength(1));
    expect(find.textContaining('Usunięto z „Na później”'), findsOneWidget);
  });

  testWidgets('nothing saved: explains how to save', (tester) async {
    for (final person in [...later.people]) {
      await later.removePerson(person);
    }
    await pump(tester);
    expect(find.textContaining('Zapisz na później'), findsOneWidget);
  });
}
