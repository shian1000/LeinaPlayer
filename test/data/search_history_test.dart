import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/search_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'newest first, one entry per query whatever its case and accents',
    () async {
      final history = SearchHistory();
      await history.load();
      await history.add('  Kino ');
      await history.add('California');
      await history.add('');
      await history.add('kinó');
      expect(history.queries, ['kinó', 'California']);

      final again = SearchHistory();
      await again.load();
      expect(again.queries, ['kinó', 'California']);
    },
  );

  test('keeps only the last ones; remove and clear forget them', () async {
    final history = SearchHistory();
    await history.load();
    for (var i = 0; i < SearchHistory.limit + 3; i++) {
      await history.add('query $i');
    }
    expect(history.queries, hasLength(SearchHistory.limit));
    expect(history.queries.first, 'query ${SearchHistory.limit + 2}');

    await history.remove('query 5');
    expect(history.queries, isNot(contains('query 5')));
    await history.clear();
    expect(history.queries, isEmpty);
  });
}
