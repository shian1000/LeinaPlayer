import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a song can be played from; the user orders them in "Ustawienia › Źródła muzyki ›
/// Kolejność odtwarzania".
enum PlaybackSource {
  phone('Telefon'),
  youtube('YouTube');

  const PlaybackSource(this.label);

  final String label;
}

/// Ways of searching YouTube, tried in this order when several are switched on.
enum YouTubeMethod {
  newPipe('Korzystaj z NewPipeExtractor'),
  explode('Korzystaj z pakietu youtube_explode'),
  ytDlpServer('Korzystaj z yt-dlp przez serwer'),
  api('Korzystaj z API');

  const YouTubeMethod(this.label);

  final String label;
}

/// Ways of playing a YouTube video. The user switches them on and orders them; the first one that
/// works is used.
enum YouTubePlaybackMethod {
  /// Audio already on the phone from an earlier play.
  cache('Pamięć podręczna'),
  newPipe('Korzystaj z NewPipeExtractor'),
  explode('Korzystaj z pakietu youtube_explode'),
  ytDlpServer('Korzystaj z yt-dlp przez serwer'),

  /// Hands the video to the YouTube app (or the browser) — plays outside this app.
  youtubeApp('Otwórz w aplikacji YouTube');

  const YouTubePlaybackMethod(this.label);

  final String label;

  static const defaults = {cache, newPipe, youtubeApp};

  /// Methods that give an audio stream this app plays itself.
  bool get streams => this == newPipe || this == explode || this == ytDlpServer;
}

/// "Ustawienia › Źródła muzyki": the YouTube settings and the playback order. Saved in
/// `shared_preferences`.
class SourceSettings extends ChangeNotifier {
  static const _searchEnabledKey = 'youtube.search_enabled';
  static const _apiKeyKey = 'youtube.api_key';
  static const _playbackOrderKey = 'sources.playback_order';
  static const _cacheLimitKey = 'youtube.cache_limit';
  static String _methodKey(YouTubeMethod m) => 'youtube.method.${m.name}';
  static String _playbackKey(YouTubePlaybackMethod m) =>
      'youtube.playback.${m.name}';
  static const _playbackMethodOrderKey = 'youtube.playback_order';

  static const defaultCacheLimit = 25;

  bool _youTubeSearchEnabled = false;
  Set<YouTubeMethod> _methods = {YouTubeMethod.newPipe, YouTubeMethod.explode};
  String? _apiKey;
  List<PlaybackSource> _playbackOrder = PlaybackSource.values;
  Set<YouTubePlaybackMethod> _playbackMethods = YouTubePlaybackMethod.defaults;
  List<YouTubePlaybackMethod> _playbackMethodOrder =
      YouTubePlaybackMethod.values;
  int _cacheLimit = defaultCacheLimit;

  /// "Włącz szukanie w serwisie YouTube".
  bool get youTubeSearchEnabled => _youTubeSearchEnabled;

  Set<YouTubeMethod> get methods => _methods;

  /// "Kod YouTube API", `null` when not set.
  String? get apiKey => _apiKey;

  /// Every [PlaybackSource], most preferred first.
  List<PlaybackSource> get playbackOrder => _playbackOrder;

  Set<YouTubePlaybackMethod> get playbackMethods => _playbackMethods;

  /// Every [YouTubePlaybackMethod], tried first to last (only the switched-on ones are used).
  List<YouTubePlaybackMethod> get playbackMethodOrder => _playbackMethodOrder;

  /// The switched-on methods, in the user's order.
  List<YouTubePlaybackMethod> get activePlaybackMethods => [
    for (final m in _playbackMethodOrder)
      if (_playbackMethods.contains(m)) m,
  ];

  /// How many YouTube songs the cache keeps.
  int get cacheLimit => _cacheLimit;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _youTubeSearchEnabled =
        prefs.getBool(_searchEnabledKey) ?? _youTubeSearchEnabled;
    _methods = {
      for (final m in YouTubeMethod.values)
        if (prefs.getBool(_methodKey(m)) ?? _methods.contains(m)) m,
    };
    _apiKey = prefs.getString(_apiKeyKey);
    _playbackMethods = {
      for (final m in YouTubePlaybackMethod.values)
        if (prefs.getBool(_playbackKey(m)) ?? _playbackMethods.contains(m)) m,
    };
    _cacheLimit = prefs.getInt(_cacheLimitKey) ?? _cacheLimit;
    _playbackMethodOrder = _withAll(
      YouTubePlaybackMethod.values,
      prefs.getStringList(_playbackMethodOrderKey),
    );
    _playbackOrder = _withAll(
      PlaybackSource.values,
      prefs.getStringList(_playbackOrderKey),
    );
    notifyListeners();
  }

  /// A saved order (enum names) with anything added in a later version appended at the end.
  static List<T> _withAll<T extends Enum>(List<T> all, List<String>? saved) {
    final order = [
      for (final name in saved ?? const <String>[])
        ...all.where((e) => e.name == name),
    ];
    return List.unmodifiable([
      ...order.toSet(),
      ...all.where((e) => !order.contains(e)),
    ]);
  }

  Future<void> setYouTubeSearchEnabled(bool value) async {
    _youTubeSearchEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _searchEnabledKey,
      value,
    );
  }

  Future<void> setMethod(YouTubeMethod method, bool enabled) async {
    _methods = Set.unmodifiable(
      enabled ? {..._methods, method} : _methods.difference({method}),
    );
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _methodKey(method),
      enabled,
    );
  }

  Future<void> setPlaybackMethod(
    YouTubePlaybackMethod method,
    bool enabled,
  ) async {
    _playbackMethods = Set.unmodifiable(
      enabled
          ? {..._playbackMethods, method}
          : _playbackMethods.difference({method}),
    );
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _playbackKey(method),
      enabled,
    );
  }

  Future<void> setPlaybackMethodOrder(List<YouTubePlaybackMethod> order) async {
    _playbackMethodOrder = List.unmodifiable(order);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _playbackMethodOrderKey,
      [for (final m in order) m.name],
    );
  }

  /// Values below 1 are stored as 1; switch [YouTubePlaybackMethod.cache] off to keep nothing.
  Future<void> setCacheLimit(int limit) async {
    _cacheLimit = limit < 1 ? 1 : limit;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(
      _cacheLimitKey,
      _cacheLimit,
    );
  }

  /// Saves the key; blank text clears it.
  Future<void> setApiKey(String text) async {
    final key = text.trim();
    _apiKey = key.isEmpty ? null : key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_apiKey == null) {
      await prefs.remove(_apiKeyKey);
    } else {
      await prefs.setString(_apiKeyKey, _apiKey!);
    }
  }

  Future<void> setPlaybackOrder(List<PlaybackSource> order) async {
    _playbackOrder = List.unmodifiable(order);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _playbackOrderKey,
      [for (final s in order) s.name],
    );
  }
}

/// Makes the [SourceSettings] reachable from any screen.
class SourceSettingsScope extends InheritedNotifier<SourceSettings> {
  const SourceSettingsScope({
    super.key,
    required SourceSettings super.notifier,
    required super.child,
  });

  static SourceSettings of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SourceSettingsScope>()!
      .notifier!;
}
