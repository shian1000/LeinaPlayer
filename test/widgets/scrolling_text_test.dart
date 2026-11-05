import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/widgets/scrolling_text.dart';

const _long = 'A very long title that does not fit in the narrow box at all';

Widget _boxed(Widget child, {double width = 100, bool still = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

double _left(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

void main() {
  testWidgets('a text that fits stays still', (tester) async {
    await tester.pumpWidget(_boxed(const ScrollingText('Hi')));
    await tester.pump(const Duration(seconds: 10));
    expect(_left(tester, 'Hi'), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a long text waits, slides to its end, and comes back', (
    tester,
  ) async {
    await tester.pumpWidget(_boxed(const ScrollingText(_long)));
    await tester.pump();
    final overflow = tester.getSize(find.text(_long)).width - 100;
    expect(overflow, greaterThan(0));
    expect(tester.getSize(find.byType(ScrollingText)).width, 100);

    await tester.pump(ScrollingText.pauseAtStart);
    expect(_left(tester, _long), 0);

    await tester.pump(const Duration(seconds: 1));
    expect(_left(tester, _long), closeTo(-ScrollingText.pixelsPerSecond, 2));

    // Settles at the end: no frames are asked for during a pause.
    await tester.pumpAndSettle();
    expect(_left(tester, _long), closeTo(-overflow, 0.01));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pump(ScrollingText.pauseAtEnd);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(_left(tester, _long), 0);
  });

  testWidgets('another text starts from the beginning', (tester) async {
    await tester.pumpWidget(_boxed(const ScrollingText(_long)));
    await tester.pump();
    await tester.pump(ScrollingText.pauseAtStart);
    await tester.pump(const Duration(seconds: 1));
    expect(_left(tester, _long), lessThan(0));

    const other = '$_long, and it goes on';
    await tester.pumpWidget(_boxed(const ScrollingText(other)));
    await tester.pump();
    expect(_left(tester, other), 0);
  });

  testWidgets('tapping a row works while its text is sliding', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _boxed(
        GestureDetector(
          onTap: () => taps++,
          child: const ScrollingText(_long),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(ScrollingText.pauseAtStart);
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(const Offset(50, 5));
    expect(taps, 1);
  });

  testWidgets('with animations turned off the text ends in an ellipsis', (
    tester,
  ) async {
    await tester.pumpWidget(_boxed(const ScrollingText(_long), still: true));
    await tester.pump(const Duration(seconds: 10));
    final text = tester.widget<Text>(find.text(_long));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text(_long)).width, 100);
  });

  group('allowed several lines', () {
    testWidgets('wraps while it fits in them', (tester) async {
      const text = 'Two words';
      await tester.pumpWidget(
        _boxed(const ScrollingText(text, maxLines: 2), width: 80),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(tester.widget<Text>(find.text(text)).softWrap, isNot(false));
      expect(_left(tester, text), 0);
    });

    testWidgets('scrolls on one line when it does not', (tester) async {
      await tester.pumpWidget(
        _boxed(const ScrollingText(_long, maxLines: 2), width: 80),
      );
      await tester.pump();
      expect(tester.widget<Text>(find.text(_long)).softWrap, isFalse);
      await tester.pump(ScrollingText.pauseAtStart);
      await tester.pump(const Duration(seconds: 1));
      expect(_left(tester, _long), lessThan(0));
    });
  });

  testWidgets('a removed text leaves no timer behind', (tester) async {
    await tester.pumpWidget(_boxed(const ScrollingText(_long)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
