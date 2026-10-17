import 'package:flutter/material.dart';

import '../data/library_folders.dart';
import '../data/text_normalizer.dart';
import '../theme.dart';
import 'common.dart';
import 'menu_sheet.dart';

/// "Przenieś do folderu" for a playlist's or mood's menu; `null` where there are no folders
/// (widget tests).
MenuSheetEntry? moveToFolderEntry(BuildContext context, String itemKey) {
  if (LibraryFoldersScope.maybeOf(context) == null) return null;
  return MenuSheetEntry(
    Icons.drive_file_move_outline,
    'Przenieś do folderu',
    onTap: () => showMoveToFolderSheet(context, itemKey),
  );
}

/// Asks for a name and makes a Biblioteka folder; `null` when cancelled.
Future<LibraryFolder?> createFolder(BuildContext context) async {
  final folders = LibraryFoldersScope.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const TextInputDialog(
      title: 'Nowy folder',
      hint: 'Nazwa folderu',
      initial: '',
    ),
  );
  if (name == null || name.trim().isEmpty) return null;
  return folders.create(name);
}

/// The folders [itemKey] (a playlist or mood) can go into, its own one ticked, and "Nowy
/// folder"; "Bez folderu" takes it back to Biblioteka's top level.
Future<void> showMoveToFolderSheet(BuildContext context, String itemKey) {
  final folders = LibraryFoldersScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void said(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      final current = folders.folderOf(itemKey);
      Widget tile({
        required IconData icon,
        required String title,
        required bool here,
        required VoidCallback onTap,
      }) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon, color: palette.textSecondary),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: here ? Icon(Icons.check, color: palette.accent) : null,
        onTap: () {
          Navigator.of(sheetContext).pop();
          onTap();
        },
      );

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const MenuSheetHeader(
              cover: Icon(Icons.drive_file_move_outline, size: 40),
              title: 'Przenieś do folderu',
              subtitle: 'Foldery są tylko na tym telefonie',
            ),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(
                Icons.create_new_folder_outlined,
                color: palette.textSecondary,
              ),
              title: const Text('Nowy folder'),
              onTap: () async {
                final navigator = Navigator.of(sheetContext);
                final folder = await createFolder(sheetContext);
                if (folder == null) return;
                navigator.pop();
                await folders.move(itemKey, folder.id);
                said('Przeniesiono do folderu „${folder.name}”');
              },
            ),
            tile(
              icon: Icons.library_music_outlined,
              title: 'Bez folderu',
              here: current == null,
              onTap: () {
                if (current == null) return;
                folders.move(itemKey, null);
                said('Wyjęto z folderu „${current.name}”');
              },
            ),
            for (final folder in [
              ...folders.folders,
            ]..sort((a, b) => compareNames(a.name, b.name)))
              tile(
                icon: Icons.folder_outlined,
                title: folder.name,
                here: current?.id == folder.id,
                onTap: () {
                  folders.move(itemKey, folder.id);
                  said('Przeniesiono do folderu „${folder.name}”');
                },
              ),
          ],
        ),
      );
    },
  );
}
