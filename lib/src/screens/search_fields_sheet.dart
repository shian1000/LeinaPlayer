import 'package:flutter/material.dart';

import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../theme.dart';
import '../l10n.dart';

/// Filter icon that opens the "Szukaj w" sheet; shows a dot while the selection differs from
/// the defaults (Tytuł, Wykonawca, Album, Nastrój, playlists and albums searched).
class SearchFieldsButton extends StatelessWidget {
  const SearchFieldsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final fields = SongCatalogScope.of(context).searchFields;
    final customised =
        fields.length != SearchField.defaults.length ||
        !fields.containsAll(SearchField.defaults) ||
        !SourceSettingsScope.of(context).playlistSearch ||
        !SourceSettingsScope.of(context).albumSearch;
    return IconButton(
      tooltip: l10n.searchFieldsSheetTitle,
      icon: Badge(
        isLabelVisible: customised,
        smallSize: 8,
        backgroundColor: context.palette.accent,
        child: const Icon(Icons.tune, size: 28),
      ),
      onPressed: () => showSearchFieldsSheet(context),
    );
  }
}

/// Bottom sheet with a checkbox per [SearchField]; changes apply (and are saved) immediately.
Future<void> showSearchFieldsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const _SearchFieldsSheet(),
  );
}

class _SearchFieldsSheet extends StatelessWidget {
  const _SearchFieldsSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = SongCatalogScope.of(context);
    final selected = catalog.searchFields;
    final settings = SourceSettingsScope.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.searchFieldsSheetSearchIn,
                    style: TextStyle(
                      fontSize: AppFontSize.emphasis,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: palette.accent),
                  onPressed: () {
                    catalog.setSearchFields(SearchField.defaults);
                    settings.setPlaylistSearch(true);
                  },
                  child: Text(l10n.searchFieldsSheetRestoreDefaults),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.searchFieldsSheetHelp,
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
          for (final field in SearchField.values)
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(field.label),
              subtitle: switch (field) {
                SearchField.artist => Text(l10n.searchFieldsSheetArtistHelp),
                SearchField.language => Text(
                  l10n.searchFieldsSheetLanguageHelp,
                ),
                SearchField.mood => Text(l10n.searchFieldsSheetMoodHelp),
                _ => null,
              },
              value: selected.contains(field),
              // Search needs at least one field, so the last ticked box can't be cleared.
              onChanged: selected.length == 1 && selected.contains(field)
                  ? null
                  : (on) => catalog.setSearchFields(
                      on!
                          ? {...selected, field}
                          : ({...selected}..remove(field)),
                    ),
            ),
          const Divider(),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(l10n.searchFieldsSheetSearchPlaylists),
            subtitle: Text(l10n.searchFieldsSheetSearchPlaylistsHelp),
            value: settings.playlistSearch,
            onChanged: settings.setPlaylistSearch,
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(l10n.searchFieldsSheetSearchAlbums),
            subtitle: Text(l10n.searchFieldsSheetSearchAlbumsHelp),
            value: settings.albumSearch,
            onChanged: settings.setAlbumSearch,
          ),
        ],
      ),
    );
  }
}
