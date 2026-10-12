import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/combined_search.dart';
import '../data/track_ref.dart';
import 'player_controller.dart';
import 'track_player.dart';
import '../data/album_covers.dart';

/// A song that started playing from the queue, for the history; [playlistId] / [playlistName]
/// are set when it played as part of a playlist.
typedef QueuePlay = ({SearchHit hit, int? playlistId, String? playlistName});

/// One song waiting in the queue; [key] tells apart the same song queued twice.
class QueueEntry {
  QueueEntry._(this.hit, {required this.added}) : key = _nextKey++;

  static int _nextKey = 0;

  final SearchHit hit;

  /// Added with "Dodaj do kolejki" — plays before the rest of the playlist / results.
  final bool added;
  final int key;
}

/// What's playing and what comes next — not a playlist: tapping a playlist track fills the
/// queue with that playlist (the "context"), tapping a search result with just that song. Like
/// the reference app, songs added with "Dodaj do kolejki" play next, before the rest of the
/// context; shuffle mixes the context's songs that haven't played yet.
/// When a song ends the next one starts; "Poprzedni" restarts the song, or within its first
/// [restartThreshold] goes back to the previous one. After each song starts, the next
/// [SourceSettings.activeQueuePrefetch] songs are downloaded to the cache ("Cachowanie kolejki").
class PlaybackQueue extends ChangeNotifier {
  PlaybackQueue(
    this._tracks, {
    Random? random,
    this.offlineRetries = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
  }) : _random = random ?? Random() {
    _completions = _tracks.player.completions.listen((_) => _advance());
    _skips = _tracks.player.skips.listen(
      (skip) => skip == MediaSkip.next ? next() : previous(),
    );
  }

  /// Moving on by itself with no connection, the queue tries the same song again after each of
  /// these waits instead of skipping it — otherwise it raced through dozens of songs in a
  /// second, each "unplayable" — then stops on it.
  final List<Duration> offlineRetries;

  /// Within this much of a song's start, "Poprzedni" goes to the previous song; later it
  /// restarts the current one.
  static const restartThreshold = Duration(seconds: 5);

  final TrackPlayer _tracks;
  final Random _random;
  late final StreamSubscription<void> _completions;
  late final StreamSubscription<MediaSkip> _skips;
  final _played = StreamController<QueuePlay>.broadcast();

  /// The playlist / results the queue was filled from, in their own order.
  List<QueueEntry> _context = const [];

  /// [_context] positions in play order: as listed, or shuffled.
  List<int> _order = const [];

  /// Where in [_order] the context has got to; -1 before the first song.
  int _pos = -1;

  /// [_context] positions taken out of the queue, so turning shuffle off doesn't bring them back.
  final Set<int> _removed = {};

  final List<QueueEntry> _added = [];
  QueueEntry? _current;
  bool _shuffle = false;
  int? _playlistId;
  String? _youTubeListId;
  String? _playlistName;
  String? _searchQuery;

  /// Bumped by every user action, so an automatic move (or caching ahead) started earlier gives
  /// up.
  int _generation = 0;
  int _prefetchRun = 0;

  SearchHit? get current => _current?.hit;

  /// Where the song playing is in the playlist / results the queue was filled from (their own
  /// order, not the shuffled one); `null` for a song added with "Dodaj do kolejki".
  int? get currentContextIndex =>
      _current == null || _current!.added || _pos < 0 ? null : _order[_pos];

  /// Each song that starts playing (for the history).
  Stream<QueuePlay> get played => _played.stream;
  int? get playlistId => _playlistId;

  /// "Otwórz w YouTube" for the current song: inside its YouTube playlist when it's playing as
  /// part of one; `null` when no video is known.
  Uri? get currentYouTubeUri {
    final entry = _current;
    if (entry == null) return null;
    return _tracks.youTubeUri(
      entry.hit,
      listId: entry.added ? null : _youTubeListId,
    );
  }

  bool get shuffle => _shuffle;
  String? get playlistName => _playlistName;
  String? get searchQuery => _searchQuery;

  /// Songs added with "Dodaj do kolejki", in the order they'll play.
  List<QueueEntry> get added => List.unmodifiable(_added);

  /// The rest of the context, in play order.
  List<QueueEntry> get contextUpcoming => [
    for (final i in _order.skip(_pos + 1)) _context[i],
  ];

  /// Everything that plays after the current song, in order.
  List<QueueEntry> get upcoming => [..._added, ...contextUpcoming];

  bool get hasNext => _added.isNotEmpty || _pos + 1 < _order.length;

  /// The current song was added by the user, so "previous" is the context song before it.
  bool get _playingAdded => _current != null && _current!.added;
  bool get hasPrevious => _playingAdded ? _pos >= 0 : _pos > 0;

  /// Replaces the queue with [entries] and plays the one at [index] (with [shuffle] on, the rest
  /// follow in random order). Only a user's tap gets here, so the YouTube app may be the last
  /// resort. Songs added with "Dodaj do kolejki" stay queued.
  Future<PlayOutcome> start(
    List<SearchHit> entries,
    int index, {
    int? playlistId,
    String? youTubeListId,
    String? playlistName,
    String? searchQuery,
    bool? shuffle,
    void Function(String status)? onStatus,
  }) {
    _generation++;
    _context = [for (final hit in entries) QueueEntry._(hit, added: false)];
    _removed.clear();
    _playlistId = playlistId;
    _youTubeListId = youTubeListId;
    _playlistName = playlistName;
    _searchQuery = searchQuery;
    if (shuffle != null) _shuffle = shuffle;
    _order = _shuffle
        ? _shuffledFrom(index)
        : List.generate(entries.length, (i) => i);
    _pos = _order.indexOf(index);
    return _play(_context[index], allowExternal: true, onStatus: onStatus);
  }

  /// Starts [entries] shuffled, from a random song ("Odtwarzanie losowe").
  Future<PlayOutcome> startShuffled(
    List<SearchHit> entries, {
    int? playlistId,
    String? youTubeListId,
    String? playlistName,
    void Function(String status)? onStatus,
  }) => start(
    entries,
    _random.nextInt(entries.length),
    playlistId: playlistId,
    youTubeListId: youTubeListId,
    playlistName: playlistName,
    shuffle: true,
    onStatus: onStatus,
  );

  /// [first], then every other context song in random order.
  List<int> _shuffledFrom(int first) => [
    first,
    ...(List.generate(_context.length, (i) => i)..remove(first))
      ..shuffle(_random),
  ];

  /// Shuffle on: every other song of the context follows the current one in random order (like
  /// the reference app, also the ones listed before the tapped song). Off: back to the context's
  /// own order, continuing after the current song.
  void setShuffle(bool value) {
    if (value == _shuffle) return;
    _shuffle = value;
    if (_context.isNotEmpty) {
      final at = _pos >= 0 ? _order[_pos] : null;
      final kept = [
        for (var i = 0; i < _context.length; i++)
          if (!_removed.contains(i) || i == at) i,
      ];
      if (value) {
        final rest = [...kept]
          ..remove(at)
          ..shuffle(_random);
        _order = [?at, ...rest];
        _pos = at == null ? -1 : 0;
      } else {
        _order = kept;
        _pos = at == null ? -1 : _order.indexOf(at);
      }
    }
    notifyListeners();
    _prefetchAhead();
  }

  /// "Dodaj do kolejki": plays after the current song and anything added before it. With nothing
  /// playing it starts right away.
  Future<PlayOutcome?> add(
    SearchHit hit, {
    void Function(String status)? onStatus,
  }) async {
    final entry = QueueEntry._(hit, added: true);
    if (_current == null) {
      _generation++;
      return _play(entry, allowExternal: true, onStatus: onStatus);
    }
    _added.add(entry);
    notifyListeners();
    _prefetchAhead();
    return null;
  }

  /// Plays [entry] from [upcoming]; the songs before it are skipped (added ones dropped, the
  /// context ones count as played).
  Future<PlayOutcome?> jumpTo(
    QueueEntry entry, {
    void Function(String status)? onStatus,
  }) async {
    final addedAt = _added.indexOf(entry);
    if (addedAt >= 0) {
      _added.removeRange(0, addedAt + 1);
    } else {
      final at = _order.indexWhere(
        (i) => identical(_context[i], entry),
        _pos + 1,
      );
      if (at < 0) return null;
      _pos = at;
    }
    _generation++;
    return _play(entry, allowExternal: true, onStatus: onStatus);
  }

  /// Takes [entry] out of [upcoming].
  void remove(QueueEntry entry) {
    if (!_added.remove(entry)) {
      final at = _order.indexWhere(
        (i) => identical(_context[i], entry),
        _pos + 1,
      );
      if (at < 0) return;
      _removed.add(_order[at]);
      _order = [..._order]..removeAt(at);
    }
    notifyListeners();
    _prefetchAhead();
  }

  /// "Wyczyść kolejkę": drops every song added with "Dodaj do kolejki".
  void clearAdded() {
    _added.clear();
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

  QueueEntry? _moveNext() {
    if (_added.isNotEmpty) return _added.removeAt(0);
    if (_pos + 1 >= _order.length) return null;
    return _context[_order[++_pos]];
  }

  /// Restarts the song, or — within its first [restartThreshold], when there is one — plays the
  /// previous song. `null` when it only restarted.
  Future<PlayOutcome?> previous({
    void Function(String status)? onStatus,
  }) async {
    final player = _tracks.player;
    if (!hasPrevious || player.currentPosition > restartThreshold) {
      await player.seek(Duration.zero);
      return null;
    }
    // From an added song, back to the context song that played before it.
    if (!_playingAdded) _pos--;
    _generation++;
    return _play(
      _context[_order[_pos]],
      allowExternal: true,
      onStatus: onStatus,
    );
  }

  Future<PlayOutcome> _play(
    QueueEntry entry, {
    required bool allowExternal,
    void Function(String status)? onStatus,
  }) async {
    _current = entry;
    notifyListeners();
    final generation = _generation;
    final outcome = await _tracks.play(
      entry.hit,
      playlistName: _playlistName,
      youTubeListId: entry.added ? null : _youTubeListId,
      searchQuery: _searchQuery,
      allowExternal: allowExternal,
      onStatus: onStatus,
    );
    if (outcome.played) {
      _played.add((
        hit: entry.hit,
        playlistId: entry.added ? null : _playlistId,
        playlistName: entry.added ? null : _playlistName,
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

  /// Caches the next songs one at a time, so they play from the phone even if the connection
  /// drops; a run gives up when a newer one starts (the queue changed, so its order did).
  Future<void> _prefetchAhead() async {
    final run = ++_prefetchRun;
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
      source: hit.onPhone ? hit.phoneFiles.first.filePath : '',
      youtubeVideoId: hit.onPhone ? null : hit.youtubeVideoId,
      coverSeed: hit.coverSeed,
      cover: CoverRequest.of(hit),
      playlistName: entry.added ? null : _playlistName,
      searchQuery: entry.added ? null : _searchQuery,
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
    List<Map<String, Object?>> refs(Iterable<QueueEntry> entries) => [
      for (final e in entries) TrackRef.of(e.hit).toJson(),
    ];
    return {
      'context': refs(_context),
      'order': _order,
      'pos': _pos,
      'removed': _removed.toList(),
      'added': refs(_added),
      'current': TrackRef.of(current.hit).toJson(),
      'current_added': current.added,
      'shuffle': _shuffle,
      'playlist_id': _playlistId,
      'youtube_list_id': _youTubeListId,
      'playlist_name': _playlistName,
      'search_query': _searchQuery,
    };
  }

  /// Puts back a [snapshot] without playing anything; [resolve] finds each song again.
  void restore(
    Map<String, Object?> json,
    SearchHit Function(TrackRef) resolve,
  ) {
    List<QueueEntry> entries(Object? list, {required bool added}) => [
      for (final item in list as List)
        QueueEntry._(
          resolve(TrackRef.fromJson((item as Map).cast())),
          added: added,
        ),
    ];
    _generation++;
    _context = entries(json['context'], added: false);
    _order = (json['order'] as List).cast<int>();
    _pos = json['pos'] as int;
    _removed
      ..clear()
      ..addAll((json['removed'] as List).cast<int>());
    _added
      ..clear()
      ..addAll(entries(json['added'], added: true));
    _shuffle = json['shuffle'] as bool;
    _playlistId = json['playlist_id'] as int?;
    _youTubeListId = json['youtube_list_id'] as String?;
    _playlistName = json['playlist_name'] as String?;
    _searchQuery = json['search_query'] as String?;
    _current = json['current_added'] as bool || _pos < 0
        ? entries([json['current']], added: true).single
        : _context[_order[_pos]];
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _prefetchRun++;
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
}
