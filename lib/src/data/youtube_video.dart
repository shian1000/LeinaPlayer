/// One video found on YouTube. Plain Dart (no Flutter), so `tool/` scripts can use it too.
class YouTubeVideo {
  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channel,
    this.duration,
    this.viewCount,
  });

  final String id;
  final String title;
  final String channel;

  /// Unknown for results from the Data API (its search doesn't return it).
  final Duration? duration;

  /// Unknown for results from the Data API.
  final int? viewCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'channel': channel,
    'duration': duration?.inSeconds,
    'views': viewCount,
  };

  factory YouTubeVideo.fromJson(Map<String, Object?> json) => YouTubeVideo(
    id: json['id']! as String,
    title: json['title']! as String,
    channel: json['channel']! as String,
    duration: json['duration'] == null
        ? null
        : Duration(seconds: json['duration']! as int),
    viewCount: json['views'] as int?,
  );
}
