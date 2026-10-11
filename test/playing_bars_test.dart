import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/widgets/playing_bars.dart';

void main() {
  testWidgets('the bars move while playing and stand still while paused', (
    tester,
  ) async {
    Future<void> show(bool playing) => tester.pumpWidget(
      Center(
        child: PlayingBars(playing: playing, color: const Color(0xFF1ED760)),
      ),
    );

    await show(true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    await show(false);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);

    await show(true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });
}
