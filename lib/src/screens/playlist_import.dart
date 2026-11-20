import 'package:flutter/material.dart';

import '../data/playlist_library.dart';
import '../data/source_settings.dart';
import '../data/spotify_playlist.dart';
import '../data/youtube_playlist.dart';
import '../data/youtube_search.dart';
import '../l10n.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/playlist_picker.dart';

/// "Utwórz › Playlista": make a new, empty playlist or import one from YouTube or Spotify.
Future<void> showPlaylistSheet(
  BuildContext context, {
  required String idPrefix,
}) {
  return showMenuSheet(
    context,
    idPrefix: idPrefix,
    largeIcons: true,
    entries: [
      MenuSheetEntry(
        Icons.add,
        l10n.playlistImportCreateNew,
        subtitle: l10n.playlistImportCreateNewSubtitle,
        onTap: () => createEmptyPlaylist(context),
      ),
      MenuSheetEntry(
        Icons.smart_display_outlined,
        l10n.playlistImportImport,
        subtitle: l10n.playlistImportImportSubtitle,
        onTap: () => importPlaylist(context),
      ),
    ],
  );
}

/// Asks for a name and makes an empty Biblioteka playlist, to fill from songs' menus.
Future<void> createEmptyPlaylist(BuildContext context) async {
  final library = PlaylistLibraryScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final name = await askPlaylistName(context);
  if (name == null) return;
  await library.create(name, const []);
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.playlistImportCreated(name))),
  );
}

/// A playlist to import: where from and its id there.
typedef PlaylistRef = ({PlaylistSource source, String id});

/// The playlist in a pasted or shared [text]: a Spotify playlist or album link, else a YouTube
/// link or bare YouTube id. A `spotify.link/…` short link isn't one yet ([runPlaylistImport]
/// follows it).
PlaylistRef? parsePlaylistLink(String text) {
  if (text.contains('spotify.') || text.contains('spotify:')) {
    return spotifyPlaylistRef(parseSpotifyLink(text));
  }
  final youTube = extractPlaylistId(text);
  return youTube == null ? null : (source: PlaylistSource.youtube, id: youTube);
}

/// The Biblioteka playlist a Spotify [link] imports as — none for a track.
PlaylistRef? spotifyPlaylistRef(SpotifyLink? link) => switch (link?.kind) {
  SpotifyLinkKind.playlist => (source: PlaylistSource.spotify, id: link!.id),
  SpotifyLinkKind.album => (source: PlaylistSource.spotifyAlbum, id: link!.id),
  SpotifyLinkKind.track || null => null,
};

/// Asks for a playlist link, fetches the playlist and saves it to Biblioteka.
Future<void> importPlaylist(BuildContext context) async {
  final link = await showDialog<String>(
    context: context,
    builder: (_) => const _LinkDialog(),
  );
  if (link == null || !context.mounted) return;
  await runPlaylistImport(context, link);
}

/// Fetches the playlist [link] points at (YouTube or Spotify, see [parsePlaylistLink]) and saves
/// it to Biblioteka, with a progress dialog and a message about how it went; returns the playlist
/// when it worked. Also used for a playlist shared to the app.
Future<PlaylistSummary?> runPlaylistImport(
  BuildContext context,
  String link,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final playlists = PlaylistLibraryScope.of(context);
  final fetcher = YouTubeScope.playlistsOf(context);
  final youTubeSearch = YouTubeScope.searchOf(context);
  final spotify = YouTubeScope.spotifyOf(context);
  final settings = SourceSettingsScope.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  var progressOpen = true;
  // Not awaited: closed below once the import is done.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(l10n.playlistImportImporting)),
          ],
        ),
      ),
    ),
  ).whenComplete(() => progressOpen = false);

  String message;
  PlaylistSummary? imported;
  try {
    var ref = parsePlaylistLink(link);
    final shortLink = ref == null ? findSpotifyShortLink(link) : null;
    if (shortLink != null) {
      ref = spotifyPlaylistRef(await spotify.resolveShortLink(shortLink));
    }
    switch (ref?.source) {
      case null || PlaylistSource.folder:
        message = l10n.playlistImportNotALink;
      case PlaylistSource.youtube:
        final result = await playlists.importYouTube(
          await fetcher.fetch(ref!.id, settings),
          videoExists: (id) => youTubeSearch.videoExists(id, settings),
        );
        imported = result.playlist;
        final removed = result.removedVideos;
        message = [
          _summary(result),
          if (removed > 0) l10n.playlistImportRemovedVideos(removed),
        ].join(' ');
      case PlaylistSource.spotify || PlaylistSource.spotifyAlbum:
        final data = ref!.source == PlaylistSource.spotifyAlbum
            ? await spotify.fetchAlbum(ref.id)
            : await spotify.fetch(ref.id);
        final result = await playlists.importSpotify(data);
        imported = result.playlist;
        final total = data.totalTracks;
        message = [
          _summary(result),
          if (total != null && total > data.tracks.length)
            l10n.playlistImportSpotifyLimit(data.tracks.length, total),
        ].join(' ');
    }
  } on YouTubeSearchException catch (e) {
    message = e.message;
  } on SpotifyException catch (e) {
    message = e.message;
  } catch (e) {
    debugPrint('Importing playlist $link failed: $e');
    message = l10n.playlistImportFailed;
  }
  if (progressOpen) navigator.pop();
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );
  return imported;
}

String _summary(PlaylistImportResult result) {
  final p = result.playlist;
  return result.updated
      ? l10n.playlistImportUpdated(p.name, p.trackCount, result.recognised)
      : l10n.playlistImportImported(p.name, p.trackCount, result.recognised);
}

/// Link field; returns the link, and won't close on text that isn't a playlist link.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (parsePlaylistLink(text) == null && findSpotifyShortLink(text) == null) {
      setState(() => _error = l10n.playlistImportNotALinkHelp);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n.playlistImportImport),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: l10n.playlistImportLinkHint,
          helperText: l10n.playlistImportLinkHelper,
          helperMaxLines: 2,
          errorText: _error,
          errorMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(l10n.playlistImportImportButton),
        ),
      ],
    );
  }
}
