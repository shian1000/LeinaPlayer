import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/track_ref.dart';
import '../data/youtube_video.dart';
import 'player_controller.dart';
import 'track_player.dart';
import '../data/album_covers.dart';

/// A song that started playing from the queue, for the history; [playlistId] / [playlistName]
/// are set when it played as part of a playlist.
typedef QueuePlay = ({SearchHit hit, int? playlistId, String? playlistName});

/// Where songs in the queue were queued from as a whole: a playlist (played, or added with
/// "Odtwórz jako następny" / "Dodaj do kolejki") or a search. Entries queued together share
/// one origin; a single song added from its ⋮ has none, even when it's on a playlist.
class QueueOrigin {
  QueueOrigin({
    this.playlistId,
    this.youTubeListId,
    this.playlistName,
    this.moodKey,
    this.searchQuery,
  });

  factory QueueOrigin.fromJson(Map<String, Object?> json) => QueueOrigin(
    playlistId: json['playlist_id'] as int?,
    youTubeListId: json['youtube_list_id'] as String?,
    playlistName: json['playlist_name'] as String?,
    moodKey: json['mood_key'] as String?,
    searchQuery: json['search_query'] as String?,
  );

  /// The Biblioteka playlist (`playlists.id`), for the history.
  final int? playlistId;

  /// The YouTube playlist, so "Otwórz w YouTube" opens the video inside it.
  final String? youTubeListId;
  final String? playlistName;

  /// The mood ([Mood.key]), so Biblioteka can mark it while its songs play.
  final String? moodKey;
  final String? searchQuery;

  /// Biblioteka's playlist / mood these songs were queued from as a whole.
  bool isFrom({int? playlistId, String? moodKey}) =>
      (playlistId != null && this.playlistId == playlistId) ||
      (moodKey != null && this.moodKey == moodKey);

  Map<String, Object?> toJson() => {
    'playlist_id': playlistId,
    'youtube_list_id': youTubeListId,
    'playlist_name': playlistName,
    'mood_key': moodKey,
    'search_query': searchQuery,
  };
}

/// One song in the queue; [key] tells apart the same song queued twice.
class QueueEntry {
  QueueEntry._(this.hit, {this.origin, this.index, this.pinned = false})
    : key = _nextKey++;

  QueueEntry._pinnedFrom(QueueEntry entry)
    : hit = entry.hit,
      origin = entry.origin,
      index = entry.index,
      pinned = true,
      key = entry.key;

  static int _nextKey = 0;

  final SearchHit hit;
  final QueueOrigin? origin;

  /// Where the song is in its [origin]'s playlist / results.
  final int? index;

  /// Moved by hand: shuffle leaves it where the user put it.
  final bool pinned;
  final int key;
}

/// What's played, what's playing and what comes next. Tapping a song in a playlist / results
/// replaces the whole queue with them (the "main" songs, the only ones shuffle mixes); songs and
/// whole playlists added with "Odtwórz jako następny" (right after the current song) or "Dodaj do
/// kolejki" (after the ones added before, ahead of the rest of the main songs) keep where they
/// were queued from, for the player, the history and "Otwórz w YouTube".
/// When a song ends the next one starts; "Poprzedni" restarts the song, or within its first
/// [restartThreshold] goes back to the previous one in the queue. After each song starts, the
/// next [SourceSettings.activeQueuePrefetch] songs are downloaded to the cache.
///
/// Songs the [filter] doesn't allow stay in the queue but are hidden and passed over (a song
/// the user taps still plays); a filter change shows them again or hides others.
class PlaybackQueue extends ChangeNotifier {
  PlaybackQueue(
    this._tracks, {
    this.filter,
    Random? random,
    this.offlineRetries = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
    this.prefetchDelay = const Duration(seconds: 5),
  }) : _random = random ?? Random() {
    _completions = _tracks.player.completions.listen((_) => _advance());
    _skips = _tracks.player.skips.listen(
      (skip) => skip == MediaSkip.next ? next() : previous(),
    );
    filter?.addListener(_filterChanged);
    _tracks.player.onNearEnd = _nearEnd;
  }

  /// "Przenikanie utworów": the song is about to end, so the next one starts now and fades in.
  bool _nearEnd() {
    if (!hasNext) return false;
    unawaited(_advance());
    return true;
  }

  /// "Filtr nastrojów"; `null`: every song plays.
  final MoodFilter? filter;

  /// Moving on by itself with no connection, the queue tries the same song again after each of
  /// these waits instead of skipping it — otherwise it raced through dozens of songs in a
  /// second, each "unplayable" — then stops on it.
  final List<Duration> offlineRetries;

  /// Caching ahead starts this long after the queue last changed: songs added quickly one after
  /// another would each start a download, most of them pushed out of the songs cached ahead
  /// by the next one, and the finished downloads would push useful songs out of the cache.
  final Duration prefetchDelay;

  /// Within this much of a song's start, "Poprzedni" goes to the previous song; later it
  /// restarts the current one.
  static const restartThreshold = Duration(seconds: 5);

  final TrackPlayer _tracks;

  /// The best YouTube video for [hit], found and remembered the way playing it would
  /// ([TrackPlayer.findVideo]).
  Future<YouTubeVideo?> findVideo(SearchHit hit) => _tracks.findVideo(hit);
  final Random _random;
  late final StreamSubscription<void> _completions;
  late final StreamSubscription<MediaSkip> _skips;
  final _played = StreamController<QueuePlay>.broadcast();

  /// Played songs, oldest first.
  final List<QueueEntry> _history = [];
  QueueEntry? _current;
  final List<QueueEntry> _upcoming = [];

  /// What the queue was last filled with by a tap ([start]).
  QueueOrigin? _mainOrigin;
  bool _shuffle = false;

  /// Bumped by every user action, so an automatic move (or caching ahead) started earlier gives
  /// up.
  int _generation = 0;
  int _prefetchRun = 0;
  Timer? _prefetchTimer;

  SearchHit? get current => _current?.hit;
  QueueEntry? get currentEntry => _current;

  /// Each song that starts playing (for the history).
  Stream<QueuePlay> get played => _played.stream;

  /// What the queue was filled with by tapping a song or "Odtwórz"; the songs after the ones
  /// added by hand.
  QueueOrigin? get mainOrigin => _mainOrigin;

  /// One of the songs the queue was filled with, rather than added to it.
  bool isMain(QueueEntry entry) =>
      entry.origin != null && identical(entry.origin, _mainOrigin);

  /// "Otwórz w YouTube" for the current song: inside its YouTube playlist when it's playing as
  /// part of one; `null` when no video is known.
  Uri? get currentYouTubeUri {
    final entry = _current;
    if (entry == null) return null;
    return _tracks.youTubeUri(entry.hit, listId: entry.origin?.youTubeListId);
  }

  bool get shuffle => _shuffle;

  bool _shown(QueueEntry entry) => filter?.allows(entry.hit) ?? true;

  /// Everything that plays after the current song, in order (without the songs [filter] hides).
  List<QueueEntry> get upcoming => List.unmodifiable(_upcoming.where(_shown));

  /// What "Poprzedni" goes back through, oldest first: the songs played before the current one,
  /// and the main songs listed before the tapped one (without the songs [filter] hides).
  List<QueueEntry> get history => List.unmodifiable(_history.where(_shown));

  bool get hasNext => _upcoming.any(_shown);
  bool get hasPrevious => _history.any(_shown);

  /// Replaces the whole queue with [entries] and plays the one at [index] (with [shuffle] on,
  /// the rest follow in random order). Only a user's tap gets here, so the YouTube app may be
  /// the last resort.
  Future<PlayOutcome> start(
    List<SearchHit> entries,
    int index, {
    int? playlistId,
    String? youTubeListId,
    String? playlistName,
    String? moodKey,
    String? searchQuery,
    bool? shuffle,
    void Function(String status)? onStatus,
  }) {
    _generation++;
    final origin = QueueOrigin(
      playlistId: playlistId,
      youTubeListId: youTubeListId,
      playlistName: playlistName,
      moodKey: moodKey,
      searchQuery: searchQuery,
    );
    _mainOrigin = origin;
    if (shuffle != null) _shuffle = shuffle;
    final all = [
      for (final (i, hit) in entries.indexed)
        QueueEntry._(hit, origin: origin, index: i),
    ];
    _history.clear();
    _upcoming.clear();
    if (_shuffle) {
      _upcoming.addAll([...all]..removeAt(index));
      _upcoming.shuffle(_random);
    } else {
      _history.addAll(all.take(index));
      _upcoming.addAll(all.skip(index + 1));
    }
    return _play(all[index], allowExternal: true, onStatus: onStatus);
  }

  /// Starts [entries] shuffled, from a random song ("Odtwarzanie losowe").
  Future<PlayOutcome> startShuffled(
    List<SearchHit> entries, {
    int? playlistId,
    String? youTubeListId,
    String? playlistName,
    String? moodKey,
    void Function(String status)? onStatus,
  }) => start(
    entries,
    _random.nextInt(entries.length),
    playlistId: playlistId,
    youTubeListId: youTubeListId,
    playlistName: playlistName,
    moodKey: moodKey,
    shuffle: true,
    onStatus: onStatus,
  );

  /// Shuffle on: the main songs not played yet — like the reference app, also the ones listed
  /// before the tapped song — take the main songs' places after the current one in random
  /// order. Off: back to their own order, continuing after the main song played last. Songs
  /// added or moved by hand stay where they are.
  void setShuffle(bool value) {
    if (value == _shuffle) return;
    _shuffle = value;
    bool mixed(QueueEntry e) => isMain(e) && !e.pinned;
    final current = _current;
    final List<QueueEntry> next;
    if (value) {
      next = [..._history.where(mixed), ..._upcoming.where(mixed)]
        ..shuffle(_random);
      _history.removeWhere(mixed);
    } else {
      final played = _history.where(isMain);
      final at = current != null && isMain(current)
          ? current.index!
          : played.isEmpty
          ? -1
          : played.last.index!;
      final pool = [..._history.where(mixed), ..._upcoming.where(mixed)]
        ..sort((a, b) => a.index!.compareTo(b.index!));
      _history
        ..removeWhere(mixed)
        ..addAll(pool.where((e) => e.index! < at));
      next = [
        for (final e in pool)
          if (e.index! > at) e,
      ];
    }
    _refill(next);
    notifyListeners();
    _prefetchAhead();
  }

  /// Puts [mainSongs] in the places of the main songs in [_upcoming], in order; the rest go at
  /// the end.
  void _refill(List<QueueEntry> mainSongs) {
    final songs = mainSongs.iterator;
    final refilled = <QueueEntry>[];
    for (final e in _upcoming) {
      if (!isMain(e) || e.pinned) {
        refilled.add(e);
      } else if (songs.moveNext()) {
        refilled.add(songs.current);
      }
    }
    while (songs.moveNext()) {
      refilled.add(songs.current);
    }
    _upcoming
      ..clear()
      ..addAll(refilled);
  }

  /// "Dodaj do kolejki": [hits] play after the current song and the songs added (or moved)
  /// before them, ahead of the rest of the main songs. [origin]: the playlist they were added from as a
  /// whole. With nothing playing the first one starts right away.
  Future<PlayOutcome?> add(
    List<SearchHit> hits, {
    QueueOrigin? origin,
    void Function(String status)? onStatus,
  }) {
    final at = _upcoming.indexWhere((e) => isMain(e) && !e.pinned);
    return _insert(
      at < 0 ? _upcoming.length : at,
      hits,
      origin: origin,
      onStatus: onStatus,
    );
  }

  /// "Odtwórz jako następny": [hits] play right after the current song.
  Future<PlayOutcome?> playNext(
    List<SearchHit> hits, {
    QueueOrigin? origin,
    void Function(String status)? onStatus,
  }) => _insert(0, hits, origin: origin, onStatus: onStatus);

  Future<PlayOutcome?> _insert(
    int at,
    List<SearchHit> hits, {
    QueueOrigin? origin,
    void Function(String status)? onStatus,
  }) async {
    if (hits.isEmpty) return null;
    final entries = [
      for (final (i, hit) in hits.indexed)
        QueueEntry._(hit, origin: origin, index: origin == null ? null : i),
    ];
    if (_current == null) {
      _generation++;
      _upcoming.insertAll(0, entries.skip(1));
      return _play(entries.first, allowExternal: true, onStatus: onStatus);
    }
    _upcoming.insertAll(at, entries);
    notifyListeners();
    _prefetchAhead();
    return null;
  }

  /// Plays [entry] from [upcoming]; the songs before it are skipped: added ones dropped, the
  /// main ones count as played.
  Future<PlayOutcome?> jumpTo(
    QueueEntry entry, {
    void Function(String status)? onStatus,
  }) async {
    final at = _upcoming.indexOf(entry);
    if (at < 0) return null;
    final skipped = _upcoming.sublist(0, at);
    _upcoming.removeRange(0, at + 1);
    final current = _current;
    if (current != null) _history.add(current);
    // Hidden ones too: switching the filter off brings them back as played.
    _history.addAll(skipped.where((e) => isMain(e) || !_shown(e)));
    _generation++;
    return _play(entry, allowExternal: true, onStatus: onStatus);
  }

  /// Plays [entry] from [history] again; the songs after it, the current one too, go back to
  /// the front of [upcoming] — as if "Poprzedni" was pressed that many times.
  Future<PlayOutcome?> jumpBack(
    QueueEntry entry, {
    void Function(String status)? onStatus,
  }) async {
    final at = _history.indexOf(entry);
    if (at < 0) return null;
    final later = _history.sublist(at + 1);
    _history.removeRange(at, _history.length);
    _upcoming.insertAll(0, [...later, ?_current]);
    _generation++;
    return _play(entry, allowExternal: true, onStatus: onStatus);
  }

  /// Takes [entry] out of [upcoming]; returns where it was, for [reinsert].
  int remove(QueueEntry entry) {
    final at = _upcoming.indexOf(entry);
    if (at < 0) return -1;
    _upcoming.removeAt(at);
    notifyListeners();
    _prefetchAhead();
    return at;
  }

  /// Puts back an entry taken out with [remove] ("Cofnij").
  void reinsert(QueueEntry entry, int at) {
    if (_upcoming.contains(entry)) return;
    _upcoming.insert(at.clamp(0, _upcoming.length), entry);
    notifyListeners();
    _prefetchAhead();
  }

  /// Moves [entry] to [to] in [upcoming] (an index after it's taken out) — right after the song
  /// shown before it, songs hidden by [filter] don't count. It keeps where it was queued from,
  /// and shuffle no longer moves it.
  void move(QueueEntry entry, int to) {
    final at = _upcoming.indexOf(entry);
    if (at < 0) return;
    _upcoming.removeAt(at);
    final shown = _upcoming.where(_shown).toList();
    final index = to <= 0
        ? 0
        : to >= shown.length
        ? _upcoming.length
        : _upcoming.indexOf(shown[to - 1]) + 1;
    _upcoming.insert(index, QueueEntry._pinnedFrom(entry));
    notifyListeners();
    _prefetchAhead();
  }

  /// "Wyczyść kolejkę": drops every song added by hand.
  void clearAdded() {
    _upcoming.removeWhere((e) => !isMain(e));
    notifyListeners();
    _prefetchAhead();
  }

  /// The next song; `null` when there's none.
  Future<PlayOutcome?> next({void Function(String status)? onStatus}) async {
    final entry = _moveNext();
    if (entry == null) return null;
    _generation++;
    return _play(entry, allowExternal: true, onStatus: onStatus);
  }

  /// Takes the next song [filter] allows out of [_upcoming]; the hidden ones before it go to
  /// the history, as passed.
  QueueEntry? _moveNext() {
    final at = _upcoming.indexWhere(_shown);
    if (at < 0) return null;
    final current = _current;
    if (current != null) _history.add(current);
    _history.addAll(_upcoming.take(at));
    _upcoming.removeRange(0, at);
    return _upcoming.removeAt(0);
  }

  /// Restarts the song, or — within its first [restartThreshold], when there is one — plays the
  /// previous song in the queue. `null` when it only restarted. [restart] false (swiping the
  /// mini player) always goes back when there's a song to go back to.
  Future<PlayOutcome?> previous({
    bool restart = true,
    void Function(String status)? onStatus,
  }) async {
    final player = _tracks.player;
    if (!hasPrevious ||
        (restart && player.currentPosition > restartThreshold)) {
      await player.seek(Duration.zero);
      return null;
    }
    final at = _history.lastIndexWhere(_shown);
    final passed = _history.sublist(at + 1);
    _history.removeRange(at + 1, _history.length);
    _upcoming.insertAll(0, [...passed, ?_current]);
    _generation++;
    return _play(
      _history.removeLast(),
      allowExternal: true,
      onStatus: onStatus,
    );
  }

  Future<PlayOutcome> _play(
    QueueEntry entry, {
    required bool allowExternal,
    void Function(String status)? onStatus,
  }) async {
    // A user's pick (allowExternal) starts at once, even over a song already fading out.
    if (allowExternal) _tracks.player.cancelFade();
    _current = entry;
    notifyListeners();
    final generation = _generation;
    final outcome = await _tracks.play(
      entry.hit,
      playlistName: entry.origin?.playlistName,
      youTubeListId: entry.origin?.youTubeListId,
      searchQuery: entry.origin?.searchQuery,
      allowExternal: allowExternal,
      onStatus: onStatus,
    );
    if (outcome.played) {
      _played.add((
        hit: entry.hit,
        playlistId: entry.origin?.playlistId,
        playlistName: entry.origin?.playlistName,
      ));
      if (generation == _generation) _prefetchAhead();
    }
    return outcome;
  }

  /// A song ended: play the next one that can be played, skipping the ones that can't (no app
  /// switching — this may happen with the screen off).
  Future<void> _advance() async {
    final generation = ++_generation;
    while (generation == _generation) {
      final entry = _moveNext();
      if (entry == null) break;
      var outcome = await _play(entry, allowExternal: false);
      for (final wait in offlineRetries) {
        if (outcome.played || !outcome.offline) break;
        debugPrint(
          'Queue: no connection for "${entry.hit.title}", '
          'trying again in ${wait.inSeconds} s',
        );
        await Future<void>.delayed(wait);
        if (generation != _generation) return;
        outcome = await _play(entry, allowExternal: false);
      }
      if (outcome.played || generation != _generation) return;
      if (outcome.offline) {
        await _tracks.player.park(shown(entry), () => playCurrent());
        return;
      }
      debugPrint('Queue skips "${entry.hit.title}": ${outcome.message}');
    }
    // The end of the queue (or nothing left could play): only now does the player pause.
    if (generation == _generation) await _tracks.player.stopAtEnd();
  }

  /// The songs [_cacheAhead] would cache, to tell whether a [filter] change changed them.
  List<int> _ahead() => [
    for (final e in upcoming.take(_tracks.settings.activeQueuePrefetch)) e.key,
  ];

  List<int> _aheadPlanned = const [];

  /// The filter changed, or the moods it looks at: other songs may be hidden now. Caching ahead
  /// is planned again only when the songs to cache changed — moods change often while syncing.
  void _filterChanged() {
    notifyListeners();
    if (_current != null && !listEquals(_ahead(), _aheadPlanned)) {
      _prefetchAhead();
    }
  }

  /// Caches the next songs one at a time, so they play from the phone even if the connection
  /// drops, [prefetchDelay] after the queue last changed. A change makes the run under way give
  /// up (the order changed), but only after the download it's on: that one isn't broken off.
  void _prefetchAhead() {
    _aheadPlanned = _ahead();
    final run = ++_prefetchRun;
    _prefetchTimer?.cancel();
    if (prefetchDelay == Duration.zero) {
      _cacheAhead(run);
      return;
    }
    _prefetchTimer = Timer(prefetchDelay, () => _cacheAhead(run));
  }

  Future<void> _cacheAhead(int run) async {
    final count = _tracks.settings.activeQueuePrefetch;
    if (count == 0) return;
    for (final entry in upcoming.take(count)) {
      if (run != _prefetchRun) return;
      try {
        await _tracks.prefetch(entry.hit);
      } catch (e) {
        debugPrint('Caching ahead "${entry.hit.title}" failed: $e');
      }
    }
  }

  /// What the player shows for [entry] before it's loaded (after a restart, or stopped on for
  /// want of a connection).
  NowPlaying shown(QueueEntry entry) {
    final hit = entry.hit;
    return NowPlaying(
      title: hit.title,
      artist: hit.artistLabel,
      titleLatin: hit.titleLatin,
      artistLatin: hit.artistLatin,
      source: hit.onPhone ? hit.phoneFiles.first.filePath : '',
      youtubeVideoId: hit.onPhone ? null : hit.youtubeVideoId,
      coverSeed: hit.coverSeed,
      cover: CoverRequest.of(hit),
      playlistName: entry.origin?.playlistName,
      searchQuery: entry.origin?.searchQuery,
    );
  }

  /// The current song as the player shows it before it's loaded; `null` when there's none.
  NowPlaying? get currentShown => _current == null ? null : shown(_current!);

  /// Plays the current song again — the one shown after a restart ([restore]).
  Future<PlayOutcome?> playCurrent({void Function(String status)? onStatus}) {
    final entry = _current;
    if (entry == null) return Future.value();
    _generation++;
    return _play(entry, allowExternal: true, onStatus: onStatus);
  }

  /// Everything needed to rebuild the queue after the app restarts; `null` when empty.
  Map<String, Object?>? snapshot() {
    final current = _current;
    if (current == null) return null;
    final origins = <QueueOrigin>[];
    int? originAt(QueueOrigin? origin) {
      if (origin == null) return null;
      final at = origins.indexWhere((o) => identical(o, origin));
      if (at >= 0) return at;
      origins.add(origin);
      return origins.length - 1;
    }

    Map<String, Object?> json(QueueEntry e) => {
      'track': TrackRef.of(e.hit).toJson(),
      'origin': originAt(e.origin),
      'index': e.index,
      if (e.pinned) 'pinned': true,
    };
    final mainOrigin = _mainOrigin;
    return {
      'version': 2,
      'main_origin': mainOrigin == null ? null : originAt(mainOrigin),
      'history': [for (final e in _history) json(e)],
      'current': json(current),
      'upcoming': [for (final e in _upcoming) json(e)],
      'shuffle': _shuffle,
      'origins': [for (final o in origins) o.toJson()],
    };
  }

  /// Puts back a [snapshot] without playing anything; [resolve] finds each song again.
  void restore(
    Map<String, Object?> json,
    SearchHit Function(TrackRef) resolve,
  ) {
    if (json['version'] != 2) json = _upgradedSnapshot(json);
    final origins = [
      for (final o in json['origins'] as List)
        QueueOrigin.fromJson((o as Map).cast()),
    ];
    QueueEntry entry(Object? item) {
      final map = (item as Map).cast<String, Object?>();
      final origin = map['origin'] as int?;
      return QueueEntry._(
        resolve(TrackRef.fromJson((map['track'] as Map).cast())),
        origin: origin == null ? null : origins[origin],
        index: map['index'] as int?,
        pinned: map['pinned'] as bool? ?? false,
      );
    }

    _generation++;
    final mainOrigin = json['main_origin'] as int?;
    _mainOrigin = mainOrigin == null ? null : origins[mainOrigin];
    _history
      ..clear()
      ..addAll((json['history'] as List).map(entry));
    _current = entry(json['current']);
    _upcoming
      ..clear()
      ..addAll((json['upcoming'] as List).map(entry));
    _shuffle = json['shuffle'] as bool;
    notifyListeners();
  }

  /// A queue saved before songs remembered where they were queued from: one playlist / results
  /// ("context") played in `order` up to `pos`, with the songs added by hand in front.
  static Map<String, Object?> _upgradedSnapshot(Map<String, Object?> old) {
    final context = old['context'] as List;
    final order = (old['order'] as List).cast<int>();
    final pos = old['pos'] as int;
    final currentAdded = old['current_added'] as bool || pos < 0;
    Map<String, Object?> main(int i) => {
      'track': context[i],
      'origin': 0,
      'index': i,
    };
    Map<String, Object?> added(Object? track) => {'track': track};
    return {
      'version': 2,
      'main_origin': 0,
      'history': [
        for (final i in order.take(currentAdded ? pos + 1 : pos)) main(i),
      ],
      'current': currentAdded ? added(old['current']) : main(order[pos]),
      'upcoming': [
        for (final track in old['added'] as List) added(track),
        for (final i in order.skip(pos + 1)) main(i),
      ],
      'shuffle': old['shuffle'],
      'origins': [
        {
          'playlist_id': old['playlist_id'],
          'youtube_list_id': old['youtube_list_id'],
          'playlist_name': old['playlist_name'],
          'search_query': old['search_query'],
        },
      ],
    };
  }

  @override
  void dispose() {
    _generation++;
    _prefetchRun++;
    _prefetchTimer?.cancel();
    filter?.removeListener(_filterChanged);
    if (_tracks.player.onNearEnd == _nearEnd) _tracks.player.onNearEnd = null;
    _completions.cancel();
    _skips.cancel();
    _played.close();
    super.dispose();
  }
}

/// Makes the [PlaybackQueue] reachable from any screen.
class PlaybackQueueScope extends InheritedNotifier<PlaybackQueue> {
  const PlaybackQueueScope({
    super.key,
    required PlaybackQueue super.notifier,
    required super.child,
  });

  static PlaybackQueue of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlaybackQueueScope>()!
      .notifier!;

  static PlaybackQueue? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlaybackQueueScope>()
      ?.notifier;
}
