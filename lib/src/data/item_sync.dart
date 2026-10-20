import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_sync.dart';

/// What an item synced with MusicDatabase item by item ([ItemSync]) remembers about that.
class SyncFields {
  const SyncFields({
    required this.updatedAt,
    this.account,
    this.revision = 0,
    this.dirty = false,
    this.deletedAt,
  });

  factory SyncFields.fromJson(
    Map<String, Object?> json, {
    required DateTime fallbackTime,
  }) => SyncFields(
    updatedAt: _time(json['updatedAt']) ?? fallbackTime,
    account: json['account'] as String?,
    revision: json['revision'] as int? ?? 0,
    dirty: json['dirty'] == true,
    deletedAt: _time(json['deletedAt']),
  );

  /// When it was last changed, here or on another phone of the account.
  final DateTime updatedAt;

  /// The MusicDatabase user it's synced with; `null` = only on this phone (made while logged
  /// out, given to the next account that syncs).
  final String? account;

  /// MusicDatabase's revision of it, last seen.
  final int revision;

  /// Changed here, waiting to be sent.
  final bool dirty;

  /// Deleted here, waiting to be sent; it stays as a marker until MusicDatabase hears of it.
  final DateTime? deletedAt;

  bool visibleTo(String? user) =>
      deletedAt == null && (account == null || account == user);

  /// A change here not sent yet.
  bool get unsent => dirty || deletedAt != null;

  Map<String, Object?> toJson() => {
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'account': account,
    'revision': revision,
    'dirty': dirty,
    'deletedAt': deletedAt?.millisecondsSinceEpoch,
  };

  SyncFields copyWith({
    DateTime? updatedAt,
    String? account,
    int? revision,
    bool? dirty,
  }) => SyncFields(
    updatedAt: updatedAt ?? this.updatedAt,
    account: account ?? this.account,
    revision: revision ?? this.revision,
    dirty: dirty ?? this.dirty,
    deletedAt: deletedAt,
  );

  /// Changed at [at]: sent by the next sync when it's an account's.
  SyncFields changed(DateTime at) => SyncFields(
    updatedAt: at,
    account: account,
    revision: revision,
    dirty: account != null,
  );

  /// Deleted at [at]; `null`: a phone-only item, just dropped.
  SyncFields? deleted(DateTime at) => account == null
      ? null
      : SyncFields(
          updatedAt: at,
          account: account,
          revision: revision,
          deletedAt: at,
        );
}

DateTime? _time(Object? millis) => millis is num && millis > 0
    ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
    : null;

/// A deletion waiting to be sent.
typedef ItemDeletion = ({String uid, int revision, DateTime deletedAt});

/// What to do with MusicDatabase's [remote] item for the one the phone has as [local].
enum RemoteAnswer {
  /// Store MusicDatabase's version (or drop the item, for its deleted form).
  take,

  /// Changed here again while the answered change was on its way: keep the phone's version,
  /// based on the answer's revision, to be sent next time.
  rebase,
}

/// [RemoteAnswer] for MusicDatabase's [remote] answer to [sentUpdatedAt] (a PUT) or
/// [sentDeletedAt] (a DELETE), for the item the phone has now as [local].
RemoteAnswer answerFor(
  Map<String, Object?> remote,
  SyncFields? local, {
  DateTime? sentUpdatedAt,
  DateTime? sentDeletedAt,
}) {
  if (local == null) return RemoteAnswer.take;
  bool same(DateTime? a, DateTime? b) =>
      a?.millisecondsSinceEpoch == b?.millisecondsSinceEpoch;
  if (sentDeletedAt != null) {
    return same(local.deletedAt, sentDeletedAt)
        ? RemoteAnswer.take
        : RemoteAnswer.rebase;
  }
  if (sentUpdatedAt != null && remote['deleted'] != true) {
    return local.deletedAt == null && same(local.updatedAt, sentUpdatedAt)
        ? RemoteAnswer.take
        : RemoteAnswer.rebase;
  }
  return RemoteAnswer.take;
}

/// A list kept on the phone whose items sync one by one with the logged-in MusicDatabase
/// account, like Biblioteka's folders ([ADR 0011](../../../docs/decisions/0011-folder-sync.md);
/// these lists: [ADR 0013](../../../docs/decisions/0013-saved-songs-sync.md)): the server is
/// the hub, the newer `updated_at` wins, a deletion deletes everywhere. Unlike folders, items
/// made while logged out go to the next account that syncs without asking (user's decision),
/// so a reinstalled phone keeps what it had. Logging out hides the account's items.
///
/// The list keeps its items and their [SyncFields]; [sync] does the HTTP.
abstract class ItemSync extends ChangeNotifier {
  ItemSync({
    required this.collection,
    required this.field,
    required this.problemNoun,
    DateTime Function()? now,
    String? Function()? userName,
    String? Function()? authToken,
  }) : now = now ?? DateTime.now,
       userName = userName ?? (() => null),
       _authToken = authToken ?? (() => null);

  /// `/users/<name>/<collection>`.
  final String collection;

  /// The list's name in the answer of `GET` (`{"revision", "<field>": [...]}`).
  final String field;

  /// What the list is, in the genitive, for problems shown in Konto ("…nie obsługuje jeszcze
  /// polubionych i zapisanych utworów").
  final String problemNoun;

  final DateTime Function() now;

  /// The logged-in MusicDatabase user ([Account]); `null` while logged out.
  final String? Function() userName;
  final String? Function() _authToken;

  /// An item was changed here, e.g. to send it to MusicDatabase soon.
  VoidCallback? onChanged;

  /// The server didn't accept the token (HTTP 401): the user has to log in again.
  VoidCallback? onUnauthorized;

  /// Phone-only items become [user]'s.
  @protected
  Future<void> adoptPhoneOnly(String user);

  /// [uid] of [user] has a change here not sent yet.
  @protected
  bool changedHere(String uid, String user);

  @protected
  List<ItemDeletion> deletionsOf(String user);

  /// [user]'s items changed here, as PUT bodies with `uid`, `base_revision` and `updated_at`.
  @protected
  List<Map<String, Object?>> changesOf(String user);

  /// Stores MusicDatabase's [remote] item (or its deleted form) as [user]'s; [sentUpdatedAt] or
  /// [sentDeletedAt]: what it answers — see [answerFor].
  @protected
  Future<void> applyRemote(
    Map<String, Object?> remote,
    String user, {
    DateTime? sentUpdatedAt,
    DateTime? sentDeletedAt,
  });

  /// Writes the items where they're kept.
  @protected
  Future<void> saveItems();

  bool _syncing = false;
  bool _syncAgain = false;
  PlaylistSyncResult? _lastSync;

  bool get syncing => _syncing;

  /// How the last [sync] went; `null` before the first one.
  PlaylistSyncResult? get lastSync => _lastSync;

  String _revisionKey(String user) => '$collection.sync_revision.$user';

  /// Exchanges the logged-in account's items with MusicDatabase on the first of [servers] that
  /// answers: phone-only items join the account, then what changed there comes (an item
  /// changed here too waits — sending it settles which version stays), then deletions and
  /// changes made here go.
  Future<void> sync(List<Uri> servers) async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    final user = userName();
    final token = _authToken();
    if (user == null || token == null || servers.isEmpty) return;
    _syncing = true;
    notifyListeners();
    try {
      do {
        _syncAgain = false;
        _lastSync = PlaylistSyncResult(
          at: now(),
          problem: await _syncWith(servers, user, token),
        );
      } while (_syncAgain && userName() == user && _authToken() == token);
    } finally {
      _syncing = false;
      notifyListeners();
      await saveItems();
    }
  }

  Future<String?> _syncWith(
    List<Uri> servers,
    String user,
    String token,
  ) async {
    await adoptPhoneOnly(user);
    String? problem;
    for (final server in servers) {
      final client = PlaylistSyncClient(
        server,
        user,
        token,
        collection: collection,
      );
      try {
        return await _syncOn(client, user);
      } on _SyncStopped catch (e) {
        return e.problem;
      } catch (e) {
        debugPrint('Syncing $collection on $server failed: $e');
        problem = 'Brak połączenia z serwerem MusicDatabase';
      } finally {
        client.close();
      }
    }
    return problem;
  }

  Future<String?> _syncOn(PlaylistSyncClient client, String user) async {
    final prefs = await SharedPreferences.getInstance();
    final since = prefs.getInt(_revisionKey(user)) ?? 0;
    var answer = await client.changedSince(since);
    _check(answer);
    var changes = answer.body! as Map<String, Object?>;
    // The counter went back (the account's data was restored or made again): fetch it all.
    if ((changes['revision']! as int) < since) {
      answer = await client.changedSince(0);
      _check(answer);
      changes = answer.body! as Map<String, Object?>;
    }
    for (final item in changes[field]! as List) {
      final remote = (item as Map).cast<String, Object?>();
      if (changedHere(remote['uid']! as String, user)) continue;
      await applyRemote(remote, user);
    }
    await saveItems();
    notifyListeners();
    await prefs.setInt(_revisionKey(user), changes['revision']! as int);

    String? problem;
    for (final deletion in deletionsOf(user)) {
      final answer = await client.delete(
        deletion.uid,
        deletion.revision,
        deletion.deletedAt.millisecondsSinceEpoch,
      );
      problem ??= _check(answer, keepGoing: true);
      if (answer.body is! Map) continue;
      await applyRemote(
        (answer.body! as Map).cast<String, Object?>(),
        user,
        sentDeletedAt: deletion.deletedAt,
      );
    }
    for (final body in changesOf(user)) {
      final answer = await client.put(body['uid']! as String, body);
      problem ??= _check(answer, keepGoing: true);
      if (answer.body is! Map) continue;
      await applyRemote(
        (answer.body! as Map).cast<String, Object?>(),
        user,
        sentUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
          body['updated_at']! as int,
        ),
      );
    }
    notifyListeners();
    return problem;
  }

  /// Throws [_SyncStopped] for answers that end this sync and returns the problem of one
  /// item's answer otherwise; `null` when it went.
  String? _check(SyncAnswer answer, {bool keepGoing = false}) {
    switch (answer.status) {
      case HttpStatus.ok || HttpStatus.conflict when answer.body is Map:
        return null;
      case HttpStatus.unauthorized:
        onUnauthorized?.call();
        throw const _SyncStopped(
          'Serwer nie przyjął logowania — zaloguj się ponownie (Ustawienia › Konto)',
        );
      case HttpStatus.serviceUnavailable:
        throw _SyncStopped(
          'Serwer MusicDatabase nie może teraz zapisać $problemNoun (dysk niepodłączony '
          'lub baza użytkownika jeszcze nieprzygotowana)',
        );
      case HttpStatus.notFound when !keepGoing:
        throw _SyncStopped(
          'Serwer MusicDatabase nie obsługuje jeszcze $problemNoun',
        );
    }
    final problem = 'Serwer odrzucił zmianę (HTTP ${answer.status})';
    if (keepGoing) return problem;
    throw _SyncStopped(problem);
  }
}

/// An answer that ends an [ItemSync.sync] early, with why (Polish, for display).
class _SyncStopped implements Exception {
  const _SyncStopped(this.problem);

  final String problem;
}
