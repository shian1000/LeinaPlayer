import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';

/// "Filtr nastrojów": while it's on, the queue passes over (and hides) songs in none of the
/// ticked moods. "Bez nastroju" lets through songs in no mood at all — on its own it passes
/// over every song with a mood, except those in a mood ticked too. Songs not in music.db
/// can't be in a mood, so they count as having none. Nothing ticked: nothing is passed over.
class MoodFilter extends ChangeNotifier {
  /// [moodsOf]: the [Mood.key]s of a music.db song; [knownMoods]: of every mood shown now, so
  /// a ticked mood that's gone (deleted, another account's) doesn't count; [moodChanges]
  /// notifies when either may have changed.
  MoodFilter({
    required this._moodsOf,
    required this._knownMoods,
    this._moodChanges,
  }) {
    _moodChanges?.addListener(_onMoodsChanged);
  }

  static const _enabledKey = 'mood_filter.enabled';
  static const _moodsKey = 'mood_filter.moods';
  static const _untaggedKey = 'mood_filter.untagged';
  static const _offWhenAddedKey = 'mood_filter.off_when_added';

  final Set<String> Function(int songId) _moodsOf;
  final Set<String> Function() _knownMoods;
  final Listenable? _moodChanges;

  bool _enabled = false;
  Set<String> _moods = const {};
  bool _untagged = false;
  bool _offWhenAdded = true;

  /// The switch; the ticks are kept while it's off.
  bool get enabled => _enabled;

  /// The ticked moods' [Mood.key]s, including ones no longer shown.
  Set<String> get moods => _moods;

  /// "Bez nastroju" is ticked.
  bool get untagged => _untagged;

  /// A song added to the queue by hand that the filter would pass over switches it off and
  /// clears the ticks (the default; user's choice); otherwise it's added, hidden and passed over.
  bool get offWhenAdded => _offWhenAdded;

  /// Songs are being passed over: switched on, with something ticked.
  bool get active =>
      _enabled && (_untagged || _moods.any(_knownMoods().contains));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _moods = {...?prefs.getStringList(_moodsKey)};
    _untagged = prefs.getBool(_untaggedKey) ?? false;
    _offWhenAdded = prefs.getBool(_offWhenAddedKey) ?? true;
    notifyListeners();
  }

  /// Whether the queue plays [hit]; always while the filter isn't [active].
  bool allows(SearchHit hit) {
    if (!active) return true;
    final id = hit.mainSong?.id;
    final moods = id == null ? const <String>{} : _moodsOf(id);
    if (moods.isEmpty) return _untagged;
    return moods.any(_moods.contains);
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, value);
  }

  /// Ticks [moodKey] or unticks it; ticking switches the filter on.
  Future<void> setMood(String moodKey, bool ticked) async {
    _moods = ticked ? {..._moods, moodKey} : ({..._moods}..remove(moodKey));
    if (ticked) _enabled = true;
    notifyListeners();
    await _save();
  }

  /// Ticks "Bez nastroju" or unticks it; ticking switches the filter on.
  Future<void> setUntagged(bool ticked) async {
    _untagged = ticked;
    if (ticked) _enabled = true;
    notifyListeners();
    await _save();
  }

  /// Switches the filter off and clears the ticks.
  Future<void> reset() async {
    _enabled = false;
    _moods = const {};
    _untagged = false;
    notifyListeners();
    await _save();
  }

  Future<void> setOffWhenAdded(bool value) async {
    _offWhenAdded = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _offWhenAddedKey,
      value,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, _enabled);
    await prefs.setStringList(_moodsKey, [..._moods]);
    await prefs.setBool(_untaggedKey, _untagged);
  }

  /// A song put into a mood or taken out changes what's passed over — only while it's on.
  void _onMoodsChanged() {
    if (_enabled) notifyListeners();
  }

  @override
  void dispose() {
    _moodChanges?.removeListener(_onMoodsChanged);
    super.dispose();
  }
}

/// Makes the [MoodFilter] reachable from any screen.
class MoodFilterScope extends InheritedNotifier<MoodFilter> {
  const MoodFilterScope({
    super.key,
    required MoodFilter super.notifier,
    required super.child,
  });

  static MoodFilter? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoodFilterScope>()?.notifier;
}
