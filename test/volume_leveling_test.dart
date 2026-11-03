import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/recordings.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/volume_leveling.dart';
import 'package:music_database_app/src/screens/playback_settings_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('music_database_app/volume_leveling');
  late List<MethodCall> calls;
  var supported = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    supported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isSupported' ? supported : null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('the switch and its strength are remembered', () async {
    final settings = SourceSettings();
    await settings.load();
    expect(settings.activeLeveling, isNull);
    await settings.setLeveling(true);
    await settings.setLevelingPercent(300);

    final again = SourceSettings();
    await again.load();
    expect(again.leveling, isTrue);
    expect(again.levelingPercent, 100);
    expect(again.activeLeveling, 1.0);
    expect(
      again.activeLevelingMeasure,
      isTrue,
      reason: 'measuring is on by default',
    );
  });

  test(
    'each player\'s session gets the effect, and loses it when off',
    () async {
      final first = StreamController<int?>();
      final second = StreamController<int?>();
      final leveling = VolumeLeveling([first.stream, second.stream]);
      leveling.strength = 0.5;
      first.add(11);
      second.add(22);
      await pumpEventQueue();
      expect(calls.map((c) => '${c.method} ${c.arguments}'), [
        'apply {session: 11, gainDb: 0.0}',
        'apply {session: 22, gainDb: 0.0}',
      ]);

      calls.clear();
      first.add(33);
      await pumpEventQueue();
      expect(calls.map((c) => '${c.method} ${c.arguments}'), [
        'release {session: 11}',
        'apply {session: 33, gainDb: 0.0}',
      ]);

      calls.clear();
      leveling.strength = null;
      await pumpEventQueue();
      expect(calls.map((c) => '${c.method} ${c.arguments}'), [
        'release {session: 33}',
        'release {session: 22}',
      ]);
      await leveling.dispose();
    },
  );

  test('a song of known loudness gets its gain on its own player', () async {
    final first = StreamController<int?>();
    final second = StreamController<int?>();
    final leveling = VolumeLeveling(
      [first.stream, second.stream],
      (track) async => track.source == '/quiet.mp3'
          ? const Loudness(lufs: -20, peakDb: -10)
          : null,
    );
    leveling.strength = 0.5;
    first.add(11);
    second.add(22);
    await pumpEventQueue();
    calls.clear();

    NowPlaying song(String source) =>
        NowPlaying(title: 't', artist: 'a', source: source, coverSeed: 's');
    await leveling.trackLoading(1, song('/quiet.mp3'));
    expect(calls.map((c) => '${c.method} ${c.arguments}'), [
      'apply {session: 22, gainDb: 3.0}',
    ]);

    calls.clear();
    await leveling.trackLoading(0, song('/unknown.mp3'));
    expect(calls, isEmpty);
    await leveling.trackLoading(1, song('/unknown.mp3'));
    expect(calls.map((c) => '${c.method} ${c.arguments}'), [
      'apply {session: 22, gainDb: 0.0}',
    ]);
    await leveling.dispose();
  });

  Widget app(SourceSettings settings) => SourceSettingsScope(
    notifier: settings,
    child: MaterialApp(
      theme: buildAppTheme(dummifyTheme),
      home: const PlaybackSettingsScreen(),
    ),
  );

  Slider levelingSlider(WidgetTester tester) =>
      tester.widgetList<Slider>(find.byType(Slider)).last;

  testWidgets('Wyrównywanie głośności unlocks its strength slider', (
    tester,
  ) async {
    final settings = SourceSettings();
    await tester.runAsync(settings.load);
    await tester.pumpWidget(app(settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Wyrównywanie głośności'), 200);
    await tester.pump();
    expect(levelingSlider(tester).onChanged, isNull);

    await tester.tap(find.text('Wyrównywanie głośności'));
    await tester.pumpAndSettle();
    expect(settings.leveling, isTrue);
    expect(levelingSlider(tester).onChanged, isNotNull);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('Mierz głośność na telefonie goes with the leveling', (
    tester,
  ) async {
    final settings = SourceSettings();
    await tester.runAsync(settings.load);
    await tester.pumpWidget(app(settings));
    await tester.pumpAndSettle();
    final measure = find.widgetWithText(
      SwitchListTile,
      'Mierz głośność na telefonie',
    );
    await tester.scrollUntilVisible(measure, 200);
    await tester.pump();
    SwitchListTile tile() => tester.widget<SwitchListTile>(measure);
    expect(tile().onChanged, isNull);
    expect(tile().value, isFalse);

    await settings.setLeveling(true);
    await tester.pumpAndSettle();
    expect(tile().value, isTrue);
    await tester.tap(measure);
    await tester.pumpAndSettle();
    expect(settings.levelingMeasure, isFalse);
    expect(settings.activeLevelingMeasure, isFalse);
  });

  testWidgets('a phone without DynamicsProcessing says so', (tester) async {
    supported = false;
    final settings = SourceSettings();
    await tester.runAsync(settings.load);
    await tester.pumpWidget(app(settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ten telefon tego nie obsługuje'),
      200,
    );
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .map((t) => t.onChanged),
      everyElement(isNull),
    );
  });
}
