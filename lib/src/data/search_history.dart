import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_normalizer.dart';

/// The last few queries of song search, newest first, shown under its empty field as Spotify
/// and YouTube do. Only on this phone, not synced.
class SearchHistory extends ChangeNotifier {
  static const _key = 'search_history';
  static const limit = 10;

  List<String> _queries = const [];

  List<String> get queries => _queries;

  Future<void> load() async {
    _queries =
        (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];
    notifyListeners();
  }

  /// Puts [query] on top; the same query typed with other case or accents replaces the old one.
  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final key = normalizeForSearch(trimmed);
    if (key.isEmpty) return;
    if (_queries.isNotEmpty && _queries.first == trimmed) return;
    await _save(
      [
        trimmed,
        for (final old in _queries)
          if (normalizeForSearch(old) != key) old,
      ].take(limit).toList(),
    );
  }

  Future<void> remove(String query) => _save([
    for (final old in _queries)
      if (old != query) old,
  ]);

  Future<void> clear() => _save(const []);

  Future<void> _save(List<String> queries) async {
    _queries = queries;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(_key, queries);
  }
}

class SearchHistoryScope extends InheritedNotifier<SearchHistory> {
  const SearchHistoryScope({
    super.key,
    required SearchHistory super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static SearchHistory? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SearchHistoryScope>()
      ?.notifier;
}
