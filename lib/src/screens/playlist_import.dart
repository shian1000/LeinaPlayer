import 'package:flutter/material.dart';

import '../data/playlist_library.dart';
import '../data/source_settings.dart';
import '../data/youtube_playlist.dart';
import '../data/youtube_search.dart';
import '../dummy.dart';
import '../widgets/menu_sheet.dart';

/// "Utwórz › Playlista": make a new playlist (not built yet) or import one from YouTube.
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
        'Utwórz nową playlistę',
        subtitle: 'Pusta playlista do uzupełnienia utworami',
        onTap: () => showDummy(context, '$idPrefix › Utwórz nową playlistę'),
      ),
      MenuSheetEntry(
        Icons.smart_display_outlined,
        'Importuj playlistę',
        subtitle: 'Z linku do playlisty na YouTube',
        onTap: () => importYouTubePlaylist(context),
      ),
    ],
  );
}

/// Asks for a YouTube playlist link, fetches the playlist and saves it to Biblioteka.
Future<void> importYouTubePlaylist(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final playlists = PlaylistLibraryScope.of(context);
  final fetcher = YouTubeScope.playlistsOf(context);
  final settings = SourceSettingsScope.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  final playlistId = await showDialog<String>(
    context: context,
    builder: (_) => const _LinkDialog(),
  );
  if (playlistId == null || !context.mounted) return;

  var progressOpen = true;
  // Not awaited: closed below once the import is done.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 20),
            Expanded(child: Text('Importuję playlistę…')),
          ],
        ),
      ),
    ),
  ).whenComplete(() => progressOpen = false);

  String message;
  try {
    final data = await fetcher.fetch(playlistId, settings);
    final result = await playlists.importYouTube(data);
    final p = result.playlist;
    message =
        '${result.updated ? 'Zaktualizowano' : 'Zaimportowano'} „${p.name}”: '
        '${p.trackCount} utw., w bazie danych ${result.recognised}.';
  } on YouTubeSearchException catch (e) {
    message = e.message;
  } catch (e) {
    debugPrint('Importing playlist $playlistId failed: $e');
    message = 'Nie udało się zaimportować playlisty.';
  }
  if (progressOpen) navigator.pop();
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );
}

/// Link field; returns the playlist id, and won't close on a link without one.
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
    final id = extractPlaylistId(_controller.text);
    if (id == null) {
      setState(
        () => _error =
            'To nie jest link do playlisty (szukam „list=…” w adresie).',
      );
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importuj playlistę z YouTube'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'https://www.youtube.com/playlist?list=…',
          helperText: 'Playlista musi być publiczna lub niepubliczna.',
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
          child: const Text('Anuluj'),
        ),
        TextButton(onPressed: _submit, child: const Text('Importuj')),
      ],
    );
  }
}
