import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A YouTube link the app was given.
sealed class YouTubeLinkTarget {
  const YouTubeLinkTarget();
}

/// A video (`watch?v=`, `youtu.be/`, `shorts/`); [listId] when it was opened inside a playlist.
class YouTubeVideoLink extends YouTubeLinkTarget {
  const YouTubeVideoLink(this.videoId, {this.listId});

  final String videoId;
  final String? listId;
}

/// A whole playlist (`playlist?list=`).
class YouTubePlaylistLink extends YouTubeLinkTarget {
  const YouTubePlaylistLink(this.listId);

  final String listId;
}

final _url = RegExp(r'https?://\S+');
final _videoId = RegExp(r'^[\w-]{11}$');

/// The YouTube link in [text] — shared text may have words around the address ("Obejrzyj …:
/// https://youtu.be/…"); `null` when there's none.
YouTubeLinkTarget? parseYouTubeLink(String text) {
  final match = _url.firstMatch(text);
  final uri = match == null ? null : Uri.tryParse(match.group(0)!);
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(
    RegExp(r'^(www|m|music)\.'),
    '',
  );
  final list = uri.queryParameters['list'];
  final listId = list != null && list.isNotEmpty ? list : null;
  String? videoId;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (host == 'youtu.be') {
    videoId = segments.firstOrNull;
  } else if (host == 'youtube.com') {
    final first = segments.firstOrNull;
    if (first == 'watch') {
      videoId = uri.queryParameters['v'];
    } else if (const {'shorts', 'live', 'embed'}.contains(first)) {
      videoId = segments.elementAtOrNull(1);
    } else if (first != 'playlist') {
      return null;
    }
  } else {
    return null;
  }
  if (videoId != null && _videoId.hasMatch(videoId)) {
    return YouTubeVideoLink(videoId, listId: listId);
  }
  return listId == null ? null : YouTubePlaylistLink(listId);
}

/// Native side: `MainActivity.kt` (`LinksBridge`).
const _channel = MethodChannel('music_database_app/links');

/// Links given to the app on Android: shared to it ("Udostępnij") or opened with it (after the
/// native chooser, `LinkChooserActivity.kt`). The one that started the app comes first, once
/// [start] is called.
class IncomingLinks {
  final _links = StreamController<String>.broadcast();

  Stream<String> get links => _links.stream;

  Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link') _links.add(call.arguments as String);
    });
    try {
      final initial = await _channel.invokeMethod<String>('initialLink');
      if (initial != null) _links.add(initial);
    } on PlatformException catch (e) {
      debugPrint('Reading the link the app was opened with failed: $e');
    }
  }

  void dispose() {
    if (!kIsWeb && Platform.isAndroid) _channel.setMethodCallHandler(null);
    _links.close();
  }
}

/// Opens [uri] in the YouTube app itself (else a browser), never in this app — which may be
/// the phone's choice for YouTube links. `null` off Android, where the caller uses url_launcher.
Future<bool?> openInYouTubeApp(Uri uri) async {
  if (kIsWeb || !Platform.isAndroid) return null;
  return await _channel.invokeMethod<bool>('openYouTube', {
        'url': uri.toString(),
      }) ??
      false;
}

/// The phone's "Otwieraj domyślnie" settings for this app, where YouTube links can be given to
/// it; `false` when they couldn't be opened (or off Android).
Future<bool> openLinkSettings() async {
  if (kIsWeb || !Platform.isAndroid) return false;
  return await _channel.invokeMethod<bool>('openLinkSettings') ?? false;
}

/// A service whose tapped links the app takes over.
enum LinkService {
  youtube('YouTube'),
  spotify('Spotify');

  const LinkService(this.label);

  final String label;
}

/// What a tapped link of a [LinkService] does; the native chooser keeps it
/// (`LinkTargets.kt`), its `key`s are these names.
enum LinkChoice { ask, leina, app, browser }

/// The remembered choice for each service — [LinkChoice.ask] off Android or when unknown.
Future<Map<LinkService, LinkChoice>> readLinkChoices() async {
  final ask = {for (final s in LinkService.values) s: LinkChoice.ask};
  if (kIsWeb || !Platform.isAndroid) return ask;
  try {
    final raw = await _channel.invokeMapMethod<String, String>('linkChoices');
    return {
      for (final s in LinkService.values)
        s: LinkChoice.values.asNameMap()[raw?[s.name]] ?? LinkChoice.ask,
    };
  } on PlatformException catch (e) {
    debugPrint('Reading link choices failed: $e');
    return ask;
  }
}

Future<void> saveLinkChoice(LinkService service, LinkChoice choice) async {
  if (kIsWeb || !Platform.isAndroid) return;
  await _channel.invokeMethod<void>('setLinkChoice', {
    'service': service.name,
    'choice': choice.name,
  });
}

/// Colours of the app's light and dark theme and which one shows ('system', 'light', 'dark'),
/// for the native chooser to look like the app; each theme as colour name → ARGB, plus
/// `fontFamily`.
Future<void> setLinkChooserLook({
  required String mode,
  required Map<String, Object?> light,
  required Map<String, Object?> dark,
}) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>(
      'setChooserLook',
      jsonEncode({'mode': mode, 'light': light, 'dark': dark}),
    );
  } on PlatformException catch (e) {
    debugPrint('Saving the link chooser look failed: $e');
  }
}
