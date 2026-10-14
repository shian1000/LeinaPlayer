import 'package:music_database_app/src/data/youtube_account.dart';
import 'package:music_database_app/src/data/youtube_api.dart';

/// YouTube's playlists as the API would keep them, with failures on demand.
class FakeYouTubeApi extends YouTubeApi {
  final playlists = <String, List<String>>{};
  var _made = 0;

  /// Video ids YouTube doesn't have.
  final missing = <String>{};

  /// Inserts accepted before the daily limit runs out; `null`: no limit.
  int? quotaLeft;

  /// The tokens that work; others get HTTP 401.
  final validTokens = {'t1'};

  void _check(String token) {
    if (!validTokens.contains(token)) {
      throw const YouTubeApiException('401', unauthorized: true);
    }
  }

  @override
  Future<String> createPlaylist(
    String token, {
    required String title,
    String description = '',
  }) async {
    _check(token);
    final id = 'PL${++_made}';
    playlists[id] = [];
    return id;
  }

  @override
  Future<bool> addVideo(String token, String playlistId, String videoId) async {
    _check(token);
    final playlist = playlists[playlistId];
    if (playlist == null) {
      throw const YouTubeApiException('gone', playlistGone: true);
    }
    if (quotaLeft != null) {
      if (quotaLeft == 0) {
        throw const YouTubeApiException('limit', quota: true);
      }
      quotaLeft = quotaLeft! - 1;
    }
    if (missing.contains(videoId)) return false;
    playlist.add(videoId);
    return true;
  }
}

/// Always signed in as [email] with token `t1`.
class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.email = 'ja@example.com'});
  final String email;
  var signIns = 0;

  @override
  Future<({String email, String token})?> signIn(
    List<String> scopes, {
    required bool interactive,
  }) async {
    signIns++;
    return (email: email, token: 't1');
  }

  @override
  Future<void> forgetToken(String token) async {}

  @override
  Future<void> signOut() async {}
}
