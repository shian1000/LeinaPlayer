import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../l10n.dart';
import '../theme.dart';

/// "Ustawienia › Okładki albumów": where album covers come from and in what order (drag to
/// reorder).
class CoverSourcesScreen extends StatefulWidget {
  const CoverSourcesScreen({super.key});

  @override
  State<CoverSourcesScreen> createState() => _CoverSourcesScreenState();
}

class _CoverSourcesScreenState extends State<CoverSourcesScreen> {
  String _note(CoverSource s) => switch (s) {
    CoverSource.server => l10n.coverSourcesScreenServerNote,
    CoverSource.file => l10n.coverSourcesScreenFileNote,
    CoverSource.itunes => l10n.coverSourcesScreenItunesNote,
    CoverSource.deezer => l10n.coverSourcesScreenDeezerNote,
    CoverSource.youtube => l10n.coverSourcesScreenYouTubeNote,
  };

  IconData _icon(CoverSource s) => switch (s) {
    CoverSource.server => Icons.dns_outlined,
    CoverSource.file => Icons.audio_file_outlined,
    CoverSource.itunes => Icons.album_outlined,
    CoverSource.deezer => Icons.album_outlined,
    CoverSource.youtube => Icons.smart_display_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final order = settings.coverOrder;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.coverSourcesScreenTitle),
      ),
      body: ReorderableListView(
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            l10n.coverSourcesScreenIntro,
            style: TextStyle(
              fontSize: AppFontSize.listSubtitle,
              color: palette.textSecondary,
            ),
          ),
        ),
        onReorderItem: (from, to) {
          final list = [...order];
          list.insert(to, list.removeAt(from));
          settings.setCoverOrder(list);
        },
        children: [
          for (final (i, source) in order.indexed)
            ListTile(
              key: ValueKey(source),
              leading: Icon(_icon(source)),
              title: Text(source.label),
              subtitle: Text(_note(source)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: settings.coverSources.contains(source),
                    onChanged: (v) => settings.setCoverSource(source, v),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
