import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home's sections the way the user arranged them — "your homepage, your rules" from
/// Juxtopposed's Spotify redesign: pinned ones first, the rest in the user's order, hidden ones
/// left out, rows added from Biblioteka, and the recommendations (Home's sample rows) on or off.
/// Only on this phone. Section ids: `sample:<title>`, `lib:<what>`, `playlist:<id>`,
/// `mood:<key>`.
class HomeLayout extends ChangeNotifier {
  HomeLayout({required this.defaults});

  static const _key = 'home_layout';

  /// Built-in sections in their first order.
  final List<String> defaults;

  List<String> _order = const [];
  List<String> _added = const [];
  Set<String> _hidden = const {};
  Set<String> _pinned = const {};
  bool _recommendations = true;

  bool get recommendations => _recommendations;
  bool isPinned(String id) => _pinned.contains(id);
  bool isHidden(String id) => _hidden.contains(id);
  bool isAdded(String id) => _added.contains(id);

  /// Every section, shown or not, in the user's order (pinned first).
  List<String> get all {
    final known = {...defaults, ..._added};
    final ordered = [
      for (final id in _order)
        if (known.contains(id)) id,
      for (final id in [...defaults, ..._added])
        if (!_order.contains(id)) id,
    ];
    return [
      for (final id in ordered)
        if (_pinned.contains(id)) id,
      for (final id in ordered)
        if (!_pinned.contains(id)) id,
    ];
  }

  /// What Home shows.
  List<String> get visible => [
    for (final id in all)
      if (!_hidden.contains(id) &&
          (_recommendations || !id.startsWith('sample:')))
        id,
  ];

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    List<String> strings(String key) => [...?(json[key] as List?)?.cast()];
    _order = strings('order');
    _added = strings('added');
    _hidden = strings('hidden').toSet();
    _pinned = strings('pinned').toSet();
    _recommendations = json['recommendations'] as bool? ?? true;
    notifyListeners();
  }

  Future<void> setPinned(String id, bool pinned) => _change(() {
    _pinned = pinned ? {..._pinned, id} : ({..._pinned}..remove(id));
  });

  Future<void> setHidden(String id, bool hidden) => _change(() {
    _hidden = hidden ? {..._hidden, id} : ({..._hidden}..remove(id));
  });

  Future<void> setRecommendations(bool on) =>
      _change(() => _recommendations = on);

  /// Moves [id] one place up (`-1`) or down (`1`) among the shown sections of its kind (pinned
  /// or not).
  Future<void> move(String id, int by) => _change(() {
    final order = all;
    final group = [
      for (final other in visible)
        if (_pinned.contains(other) == _pinned.contains(id)) other,
    ];
    final at = group.indexOf(id);
    final to = at + by;
    if (at < 0 || to < 0 || to >= group.length) return;
    final target = group[to];
    order.remove(id);
    order.insert(order.indexOf(target) + (by > 0 ? 1 : 0), id);
    _order = order;
  });

  /// `onReorderItem`'s indices over [all] ([to] counted without the moved one).
  Future<void> reorder(int from, int to) => _change(() {
    final order = all;
    final id = order.removeAt(from);
    order.insert(to, id);
    _order = order;
  });

  /// A row from Biblioteka (`playlist:<id>`, `mood:<key>`), added at the top.
  Future<void> add(String id) => _change(() {
    if (_added.contains(id)) {
      _hidden = {..._hidden}..remove(id);
      return;
    }
    _added = [..._added, id];
    _order = [id, ...all.where((other) => other != id)];
  });

  Future<void> remove(String id) => _change(() {
    _added = [..._added]..remove(id);
    _order = [..._order]..remove(id);
    _pinned = {..._pinned}..remove(id);
    _hidden = {..._hidden}..remove(id);
  });

  Future<void> _change(void Function() change) async {
    change();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        'order': _order,
        'added': _added,
        'hidden': [..._hidden],
        'pinned': [..._pinned],
        'recommendations': _recommendations,
      }),
    );
  }
}

class HomeLayoutScope extends InheritedNotifier<HomeLayout> {
  const HomeLayoutScope({
    super.key,
    required HomeLayout super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static HomeLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeLayoutScope>()?.notifier;
}
