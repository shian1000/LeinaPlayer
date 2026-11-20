import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the phone syncs, each with its own sources (Ustawienia › Synchronizacja).
enum SyncFeature { database, library, requests, errorReports }

/// Where a [SyncFeature] can sync with. The phone's own data isn't one: it is always kept, shown
/// apart as "Dane na telefonie".
enum SyncSource { gitHub, leina, privateServer }

/// Which sources each [SyncFeature] uses and in what order they are tried — switched and moved
/// on Ustawienia › Synchronizacja, kept in `shared_preferences`.
class SyncSources extends ChangeNotifier {
  /// Each feature's sources in their default order: a private server first, as before the
  /// order could be changed (it is always the freshest).
  static const defaults = <SyncFeature, List<SyncSource>>{
    SyncFeature.database: [
      SyncSource.privateServer,
      SyncSource.gitHub,
      SyncSource.leina,
    ],
    SyncFeature.library: [SyncSource.privateServer, SyncSource.leina],
    SyncFeature.requests: [SyncSource.privateServer, SyncSource.leina],
    SyncFeature.errorReports: [SyncSource.privateServer, SyncSource.leina],
  };

  /// Whether [source] can do [feature] in this version: the Leina server doesn't exist yet, and
  /// MusicDatabase has no place for problem reports.
  static bool works(SyncFeature feature, SyncSource source) =>
      source != SyncSource.leina &&
      !(feature == SyncFeature.errorReports &&
          source == SyncSource.privateServer);

  // The catalog's GitHub switch keeps the key from before this screen, which also tells a fresh
  // install's first start whether it was answered (DatabaseSync.needsGitHubChoice).
  static String _onKey(SyncFeature feature, SyncSource source) =>
      feature == SyncFeature.database && source == SyncSource.gitHub
      ? 'database_sync.github_on'
      : 'sync_sources.${feature.name}.${source.name}_on';

  static String _orderKey(SyncFeature feature) =>
      'sync_sources.${feature.name}.order';

  final _order = {
    for (final MapEntry(:key, :value) in defaults.entries) key: [...value],
  };
  final _on = <(SyncFeature, SyncSource), bool>{};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final feature in SyncFeature.values) {
      final known = defaults[feature]!;
      final stored = [
        for (final name in prefs.getStringList(_orderKey(feature)) ?? [])
          ?known.where((s) => s.name == name).firstOrNull,
      ];
      // A source added in a later version goes where its default puts it relative to the end.
      _order[feature] = [...stored, ...known.where((s) => !stored.contains(s))];
      for (final source in known) {
        final on = prefs.getBool(_onKey(feature, source));
        if (on != null) _on[(feature, source)] = on;
      }
    }
    notifyListeners();
  }

  /// [feature]'s sources, in the order they are tried.
  List<SyncSource> order(SyncFeature feature) =>
      List.unmodifiable(_order[feature]!);

  /// The sources [feature] tries now, in order.
  List<SyncSource> enabled(SyncFeature feature) => [
    for (final source in _order[feature]!)
      if (isOn(feature, source)) source,
  ];

  /// Whether [source] is switched on for [feature]; one that doesn't [works] never is.
  bool isOn(SyncFeature feature, SyncSource source) =>
      works(feature, source) && (_on[(feature, source)] ?? true);

  Future<void> setOn(SyncFeature feature, SyncSource source, bool on) async {
    if (!works(feature, source)) return;
    await (await SharedPreferences.getInstance()).setBool(
      _onKey(feature, source),
      on,
    );
    _on[(feature, source)] = on;
    notifyListeners();
  }

  /// Moves [feature]'s source at [from] to [to] (counted once it is taken out).
  Future<void> move(SyncFeature feature, int from, int to) async {
    final order = _order[feature]!;
    if (from == to) return;
    order.insert(to, order.removeAt(from));
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _orderKey(feature),
      [for (final source in order) source.name],
    );
  }
}
