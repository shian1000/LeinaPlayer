import 'package:flutter_test/flutter_test.dart';

/// How long to wait for background work a test can't await directly (the file system, SQLite,
/// an isolate, a local HTTP server). Generous: with the whole suite running in parallel on the
/// development machine, work that takes milliseconds alone can take seconds. Waiting stops as
/// soon as the condition holds, so a passing test doesn't wait this long.
const backgroundWorkTimeout = Duration(seconds: 30);

/// Polls [done] in real time until it holds or [timeout] passes; the caller's `expect`
/// reports a timeout.
Future<void> waitUntil(
  bool Function() done, {
  Duration timeout = backgroundWorkTimeout,
}) async {
  final clock = Stopwatch()..start();
  while (!done() && clock.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// [waitUntil] inside `testWidgets`: lets real time pass (`runAsync`) and pumps frames between
/// checks, so work started by a tap can finish and show.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = backgroundWorkTimeout,
}) async {
  final clock = Stopwatch()..start();
  while (!done() && clock.elapsed < timeout) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
