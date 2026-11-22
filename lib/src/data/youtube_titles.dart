import 'dart:convert';
import 'dart:io';

import 'youtube_playlist.dart';
import 'youtube_video.dart';

/// The language a playlist is read in a second time, to find titles YouTube translated: the
/// first reading is in NewPipe's default, English.
const translationCheckLanguage = 'pl';

/// The videos whose titles differ between two readings of one playlist in two languages: YouTube
/// served at least one of them translated ("W związku z tym" by L.U.C. as "In relation to" in
/// English, "In Verbindung mit" in German) — it translates a title into the language asked for
/// whenever the uploader or YouTube has a translation, and a playlist's page never says which
/// title is the original.
Set<String> translatedTitleIds(
  YouTubePlaylistData first,
  YouTubePlaylistData second,
) {
  final other = {for (final v in second.videos) v.id: v.title};
  return {
    for (final v in first.videos)
      if (other[v.id] case final title? when title.trim() != v.title.trim())
        v.id,
  };
}

/// [data] with the titles of [originals] (by video id) in place of the ones read.
YouTubePlaylistData withTitles(
  YouTubePlaylistData data,
  Map<String, String> originals,
) => originals.isEmpty
    ? data
    : YouTubePlaylistData(
        id: data.id,
        name: data.name,
        owner: data.owner,
        videos: [
          for (final v in data.videos)
            originals[v.id] == null
                ? v
                : YouTubeVideo(
                    id: v.id,
                    title: originals[v.id]!,
                    channel: v.channel,
                    duration: v.duration,
                    viewCount: v.viewCount,
                  ),
        ],
      );

/// The title in a YouTube oEmbed answer (`{"title": …, "author_name": …}`), `null` without one.
/// oEmbed gives a video's own title, never a translation, whatever language is asked.
String? titleFromOEmbed(String body) {
  final json = jsonDecode(body);
  return json is Map && json['title'] is String && json['title'] != ''
      ? json['title'] as String
      : null;
}

/// The video's own, untranslated title from YouTube's oEmbed endpoint (the video id only, no
/// account), `null` when YouTube doesn't give one (a private or removed video).
Future<String?> oEmbedTitle(String videoId) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(
      Uri.https('www.youtube.com', '/oembed', {
        'url': 'https://www.youtube.com/watch?v=$videoId',
        'format': 'json',
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) return null;
    return titleFromOEmbed(body);
  } finally {
    client.close(force: true);
  }
}
