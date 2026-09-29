import 'package:flutter_test/flutter_test.dart';

import 'package:music_database_app/main.dart';

void main() {
  testWidgets('shows Hello World', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    expect(find.text('Hello World'), findsOneWidget);
  });
}
