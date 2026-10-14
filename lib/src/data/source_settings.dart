import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spotify_playlist.dart';

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

/// Where an album cover can come from; the user switches them on and orders them in
/// "Ustawienia › Źródła okładek". The first one that has a cover wins.
enum CoverSource {
  /// MusicDatabase's server — it has no covers yet (dummy).
  server('Serwer'),

  /// The cover inside the music file on the phone.
  file('Plik na telefonie'),
  itunes('iTunes'),
  deezer('Deezer'),

  /// The YouTube video's thumbnail, cropped to a square.
  youtube('Miniatura z YouTube');

  const CoverSource(this.label);

  final String label;

  static const defaults = {file, itunes, deezer, youtube};

  /// Not usable yet; shown switched off.
  bool get available => this != server;
}

/// "Ustawienia › Źródła muzyki": the YouTube settings and the playback order. Saved in
/// `shared_preferences`.
class SourceSettings extends ChangeNotifier {
  static const _searchEnabledKey = 'youtube.search_enabled';
  static const _playlistSearchKey = 'search.playlists';
  static const _youTubePlaylistSearchKey = 'youtube.search_playlists';
  static const _spotifyPlaylistSearchKey = 'spotify.search_playlists';
  static const _spotifyClientIdKey = 'spotify.client_id';
  static const _spotifyClientSecretKey = 'spotify.client_secret';
  static const _apiKeyKey = 'youtube.api_key';
  static const _playbackOrderKey = 'sources.playback_order';
  static const _cacheLimitKey = 'youtube.cache_limit';
  static String _methodKey(YouTubeMethod m) => 'youtube.method.${m.name}';
  static String _playbackKey(YouTubePlaybackMethod m) =>
      'youtube.playback.${m.name}';
  static const _playbackMethodOrderKey = 'youtube.playback_order';

  static const defaultCacheLimit = 25;
  static const _queuePrefetchKey = 'sources.queue_prefetch';
  static const defaultQueuePrefetch = 3;
  static const maxQueuePrefetch = 10;
  static const _queuePrefetchEnabledKey = 'sources.queue_prefetch_enabled';
  static const _queuePrefetchWifiOnlyKey =
      'data_saver.queue_prefetch_wifi_only';

  static String _coverKey(CoverSource s) => 'covers.source.${s.name}';
  static const _coverOrderKey = 'covers.order';
  static const _coverCacheLimitKey = 'covers.cache_limit_mb';
  static const defaultCoverCacheLimitMb = 100;
  static const _coverWifiOnlyKey = 'data_saver.covers_wifi_only';
  static const _crossfadeKey = 'playback.crossfade_seconds';

  /// The longest "Przenikanie utworów", as in the reference app.
  static const maxCrossfadeSeconds = 12;

  bool _youTubeSearchEnabled = false;
  bool _playlistSearch = true;
  bool _youTubePlaylistSearch = true;
  bool _spotifyPlaylistSearch = true;
  String? _spotifyClientId;
  String? _spotifyClientSecret;
  Set<YouTubeMethod> _methods = {YouTubeMethod.newPipe, YouTubeMethod.explode};
  String? _apiKey;
  List<PlaybackSource> _playbackOrder = PlaybackSource.values;
  Set<YouTubePlaybackMethod> _playbackMethods = YouTubePlaybackMethod.defaults;
  List<YouTubePlaybackMethod> _playbackMethodOrder =
      YouTubePlaybackMethod.values;
  int _cacheLimit = defaultCacheLimit;
  int _queuePrefetch = defaultQueuePrefetch;
  bool _queuePrefetchEnabled = true;
  bool _queuePrefetchWifiOnly = false;
  List<CoverSource> _coverOrder = CoverSource.values;
  Set<CoverSource> _coverSources = CoverSource.defaults;
  int _coverCacheLimitMb = defaultCoverCacheLimitMb;
  bool _coverWifiOnly = false;
  int _crossfadeSeconds = 0;

  /// "Włącz szukanie w serwisie YouTube".
  bool get youTubeSearchEnabled => _youTubeSearchEnabled;

  /// "Wyszukuj playlisty" (search filters): Biblioteka playlists while typing, and YouTube /
  /// Spotify ones with the online search, as their own switches allow.
  bool get playlistSearch => _playlistSearch;

  /// "Wyszukuj playlisty na YouTube" (YouTube settings).
  bool get youTubePlaylistSearch => _youTubePlaylistSearch;

  /// "Wyszukuj playlisty na Spotify" (Spotify settings).
  bool get spotifyPlaylistSearch => _spotifyPlaylistSearch;

  /// What the search button looks for on YouTube right now.
  bool get searchesYouTubePlaylists =>
      _youTubeSearchEnabled && _playlistSearch && _youTubePlaylistSearch;

  bool get searchesSpotifyPlaylists =>
      _playlistSearch && _spotifyPlaylistSearch;

  /// The user's own Spotify app, `null` until both halves are set.
  SpotifyApiKey? get spotifyApiKey =>
      _spotifyClientId == null || _spotifyClientSecret == null
      ? null
      : (clientId: _spotifyClientId!, clientSecret: _spotifyClientSecret!);

  String? get spotifyClientId => _spotifyClientId;

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

  /// "Twórz cache dla przyszłych utworów w kolejce".
  bool get queuePrefetchEnabled => _queuePrefetchEnabled;

  /// How many of the queue's next songs get downloaded to the cache ahead of time (Pamięć
  /// podręczna › Kolejka).
  int get queuePrefetch => _queuePrefetch;

  /// Songs to cache ahead right now; 0 = none (switched off).
  int get activeQueuePrefetch => _queuePrefetchEnabled ? _queuePrefetch : 0;

  /// "Przenikanie utworów" (Ustawienia › Odtwarzanie), 0 = off.
  int get crossfadeSeconds => _crossfadeSeconds;

  /// Cache ahead only on Wi-Fi (Oszczędzanie danych i tryb offline).
  bool get queuePrefetchWifiOnly => _queuePrefetchWifiOnly;

  /// Every [CoverSource], tried first to last (only the switched-on ones are used).
  List<CoverSource> get coverOrder => _coverOrder;

  Set<CoverSource> get coverSources => _coverSources;

  /// The switched-on, usable cover sources in the user's order.
  List<CoverSource> get activeCoverSources => [
    for (final s in _coverOrder)
      if (s.available && _coverSources.contains(s)) s,
  ];

  /// Size limit of the cover cache, in MB.
  int get coverCacheLimitMb => _coverCacheLimitMb;

  /// Download covers only on Wi-Fi (Oszczędzanie danych i tryb offline); cached ones still show.
  bool get coverWifiOnly => _coverWifiOnly;

  /// How many files the cache really keeps: never so few that songs cached ahead for the queue
  /// push out the one playing (or each other) before they're played.
  int get cacheKeep => activeQueuePrefetch == 0
      ? _cacheLimit
      : max(_cacheLimit, activeQueuePrefetch + 2);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _youTubeSearchEnabled =
        prefs.getBool(_searchEnabledKey) ?? _youTubeSearchEnabled;
    _playlistSearch = prefs.getBool(_playlistSearchKey) ?? _playlistSearch;
    _youTubePlaylistSearch =
        prefs.getBool(_youTubePlaylistSearchKey) ?? _youTubePlaylistSearch;
    _spotifyPlaylistSearch =
        prefs.getBool(_spotifyPlaylistSearchKey) ?? _spotifyPlaylistSearch;
    _spotifyClientId = prefs.getString(_spotifyClientIdKey);
    _spotifyClientSecret = prefs.getString(_spotifyClientSecretKey);
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
    _queuePrefetch = prefs.getInt(_queuePrefetchKey) ?? _queuePrefetch;
    _queuePrefetchEnabled =
        prefs.getBool(_queuePrefetchEnabledKey) ?? _queuePrefetchEnabled;
    _queuePrefetchWifiOnly =
        prefs.getBool(_queuePrefetchWifiOnlyKey) ?? _queuePrefetchWifiOnly;
    _coverSources = {
      for (final s in CoverSource.values)
        if (prefs.getBool(_coverKey(s)) ?? _coverSources.contains(s)) s,
    };
    _coverOrder = _withAll(
      CoverSource.values,
      prefs.getStringList(_coverOrderKey),
    );
    _coverCacheLimitMb =
        prefs.getInt(_coverCacheLimitKey) ?? _coverCacheLimitMb;
    _coverWifiOnly = prefs.getBool(_coverWifiOnlyKey) ?? _coverWifiOnly;
    _crossfadeSeconds = (prefs.getInt(_crossfadeKey) ?? _crossfadeSeconds)
        .clamp(0, maxCrossfadeSeconds);
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

  Future<void> setPlaylistSearch(bool value) async {
    _playlistSearch = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _playlistSearchKey,
      value,
    );
  }

  Future<void> setYouTubePlaylistSearch(bool value) async {
    _youTubePlaylistSearch = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _youTubePlaylistSearchKey,
      value,
    );
  }

  Future<void> setSpotifyPlaylistSearch(bool value) async {
    _spotifyPlaylistSearch = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _spotifyPlaylistSearchKey,
      value,
    );
  }

  /// Saves the Spotify app's Client ID and Client Secret; blank text clears them.
  Future<void> setSpotifyApiKey(String clientId, String clientSecret) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    _spotifyClientId = id.isEmpty ? null : id;
    _spotifyClientSecret = secret.isEmpty ? null : secret;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    for (final (key, value) in [
      (_spotifyClientIdKey, _spotifyClientId),
      (_spotifyClientSecretKey, _spotifyClientSecret),
    ]) {
      value == null
          ? await prefs.remove(key)
          : await prefs.setString(key, value);
    }
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

  Future<void> setQueuePrefetch(int count) async {
    _queuePrefetch = count.clamp(1, maxQueuePrefetch);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(
      _queuePrefetchKey,
      _queuePrefetch,
    );
  }

  Future<void> setQueuePrefetchEnabled(bool value) async {
    _queuePrefetchEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _queuePrefetchEnabledKey,
      value,
    );
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    _crossfadeSeconds = seconds.clamp(0, maxCrossfadeSeconds);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(
      _crossfadeKey,
      _crossfadeSeconds,
    );
  }

  Future<void> setQueuePrefetchWifiOnly(bool value) async {
    _queuePrefetchWifiOnly = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _queuePrefetchWifiOnlyKey,
      value,
    );
  }

  Future<void> setCoverSource(CoverSource source, bool enabled) async {
    _coverSources = Set.unmodifiable(
      enabled ? {..._coverSources, source} : _coverSources.difference({source}),
    );
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _coverKey(source),
      enabled,
    );
  }

  Future<void> setCoverOrder(List<CoverSource> order) async {
    _coverOrder = List.unmodifiable(order);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _coverOrderKey,
      [for (final s in order) s.name],
    );
  }

  Future<void> setCoverCacheLimitMb(int mb) async {
    _coverCacheLimitMb = mb < 1 ? 1 : mb;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(
      _coverCacheLimitKey,
      _coverCacheLimitMb,
    );
  }

  Future<void> setCoverWifiOnly(bool value) async {
    _coverWifiOnly = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      _coverWifiOnlyKey,
      value,
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
