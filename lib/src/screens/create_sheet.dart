import 'package:flutter/material.dart';

import '../data/library_folders.dart';
import '../data/moods.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import 'playlist_import.dart';

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
        'Playlista',
        subtitle: 'Utwórz nową albo zaimportuj z YouTube',
        onTap: () =>
            showPlaylistSheet(context, idPrefix: '$idPrefix › Playlista'),
      ),
      if (MoodLibraryScope.maybeOf(context) != null)
        MenuSheetEntry(
          moodIcon,
          'Nastrój',
          subtitle: 'Utwory o podobnym klimacie, np. do ćwiczeń',
          onTap: () => createMood(context),
        ),
      if (LibraryFoldersScope.maybeOf(context) != null)
        MenuSheetEntry(
          Icons.create_new_folder_outlined,
          'Folder',
          subtitle: 'Uporządkuj playlisty i nastroje w Bibliotece',
          onTap: () => createFolder(context),
        ),
      const MenuSheetEntry(
        Icons.group_outlined,
        'Współtworzone playlisty',
        subtitle: 'Utwórz playlistę ze znajomymi',
      ),
      const MenuSheetEntry(
        Icons.join_inner,
        'Blend',
        subtitle: 'Połącz gusta znajomych w jedną playlistę',
      ),
    ],
  );
}
