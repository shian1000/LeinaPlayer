import 'package:flutter/material.dart';

import '../data/source_settings.dart';
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
    CoverSource.server =>
      'Jeszcze niedostępne — serwer bazy danych nie ma okładek',
    CoverSource.file => 'Okładka zapisana w pliku muzycznym na telefonie',
    CoverSource.itunes => 'Wyszukiwanie albumu w iTunes',
    CoverSource.deezer => 'Wyszukiwanie albumu w serwisie Deezer',
    CoverSource.youtube => 'Miniatura filmu, przycięta do kwadratu — przy teledyskach to kadr z filmu',
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
        title: const Text('Okładki albumów'),
      ),
      body: ReorderableListView(
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Okładka albumu pochodzi z pierwszego włączonego źródła od góry, które ją ma. '
            'Przeciągnij, aby zmienić kolejność. Pobrane okładki: Oszczędzanie danych i tryb '
            'offline › Pamięć podręczna.',
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
                    value:
                        source.available &&
                        settings.coverSources.contains(source),
                    onChanged: source.available
                        ? (v) => settings.setCoverSource(source, v)
                        : null,
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
