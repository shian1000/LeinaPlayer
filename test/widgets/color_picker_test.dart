import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/color_picker.dart';

void main() {
  Future<Color?> pick(
    WidgetTester tester,
    Future<void> Function() interact,
  ) async {
    Color? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(dummifyTheme),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showColorPicker(
              context,
              initial: const Color(0xFF33FF66),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('a typed hex code is the picked colour', (tester) async {
    final color = await pick(tester, () async {
      await tester.enterText(find.byType(TextField), 'ffb000');
      await tester.pump();
    });
    expect(color, const Color(0xFFFFB000));
  });

  testWidgets('dragging along the hue bar changes the hue, the hex follows', (
    tester,
  ) async {
    final color = await pick(tester, () async {
      final bar = tester.getRect(find.byKey(const Key('colorPicker.hue')));
      // A third of the way along is hue 120°; saturation and brightness stay.
      await tester.tapAt(Offset(bar.left + bar.width / 3, bar.center.dy));
      await tester.pump();
      expect(
        find.text(colorHex(HSVColor.fromAHSV(1, 120, 0.8, 1).toColor())),
        findsOneWidget,
      );
    });
    expect(HSVColor.fromColor(color!).hue, closeTo(120, 2));
  });
}
