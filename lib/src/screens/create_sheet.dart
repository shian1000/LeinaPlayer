import 'package:flutter/material.dart';

import '../widgets/menu_sheet.dart';

/// "Utwórz" sheet — opened from the bottom-nav tab and from the "+" in the Library header,
/// so the caller passes its own [idPrefix] to keep the two entry points distinguishable.
Future<void> showCreateSheet(BuildContext context, {required String idPrefix}) {
  return showMenuSheet(
    context,
    idPrefix: idPrefix,
    largeIcons: true,
    entries: const [
      MenuSheetEntry(
        Icons.music_note_outlined,
        'Playlista',
        subtitle: 'Utwórz playlistę z utworami lub odcinkami',
      ),
      MenuSheetEntry(
        Icons.group_outlined,
        'Współtworzone playlisty',
        subtitle: 'Utwórz playlistę ze znajomymi',
      ),
      MenuSheetEntry(
        Icons.join_inner,
        'Blend',
        subtitle: 'Połącz gusta znajomych w jedną playlistę',
      ),
    ],
  );
}
