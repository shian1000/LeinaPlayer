import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The test machine's language is English; the app follows the phone's, and the tests look for
/// the Polish texts (docs/agent-notes/localization.md). Only where a test binding is already
/// up: starting one here would also fake every HttpClient of the plain unit tests (HTTP 400).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    final TestWidgetsFlutterBinding binding;
    try {
      binding = TestWidgetsFlutterBinding.instance;
    } on FlutterError {
      return;
    }
    binding.platformDispatcher.localesTestValue = const [Locale('pl', 'PL')];
    binding.platformDispatcher.localeTestValue = const Locale('pl', 'PL');
  });
  await testMain();
}
