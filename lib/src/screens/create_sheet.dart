import 'package:flutter/material.dart';

import '../data/library_folders.dart';
import '../data/moods.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import 'playlist_import.dart';
import '../l10n.dart';

/// "Utwórz" sheet — opened from the bottom-nav tab and from the "+" in the Library header,
/// so the caller passes its own [idPrefix] to keep the two entry points distinguishable.
Future<void> showCreateSheet(BuildContext context, {required String idPrefix}) {
  return showMenuSheet(
    context,
    idPrefix: idPrefix,
    largeIcons: true,
    entries: [
      MenuSheetEntry(
        Icons.music_note_outlined,
        l10n.createSheetPlaylist,
        subtitle: l10n.createSheetPlaylistHelp,
        onTap: () =>
            showPlaylistSheet(context, idPrefix: '$idPrefix › Playlista'),
      ),
      if (MoodLibraryScope.maybeOf(context) != null)
        MenuSheetEntry(
          moodIcon,
          l10n.createSheetMood,
          subtitle: l10n.createSheetMoodHelp,
          onTap: () => createMood(context),
        ),
      if (LibraryFoldersScope.maybeOf(context) != null)
        MenuSheetEntry(
          Icons.create_new_folder_outlined,
          l10n.createSheetFolder,
          subtitle: l10n.createSheetFolderHelp,
          onTap: () => createFolder(context),
        ),
    ],
  );
}
