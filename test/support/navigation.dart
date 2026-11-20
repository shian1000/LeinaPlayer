import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `tester.pageBack()` finds the button by its English tooltip "Back"; the whole app's
/// Material texts are Polish ("Wstecz"), so tap the top screen's [BackButton] instead.
Future<void> tapBack(WidgetTester tester) =>
    tester.tap(find.byType(BackButton).hitTestable().last);
