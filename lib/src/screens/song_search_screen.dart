import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/local_library.dart';
import '../playback/player_controller.dart';
import '../data/song_catalog.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import 'database_source_screen.dart';
import 'search_fields_sheet.dart';

/// Song search over the downloaded MusicDatabase (`music.db`), opened from the
/// "Czego chcesz posłuchać?" field on the Wyszukaj tab. Results update on every keystroke.
class SongSearchScreen extends StatefulWidget {
  const SongSearchScreen({super.key});

  @override
  State<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends State<SongSearchScreen> {
  final _query = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongCatalogScope.of(context).ensureLoaded();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Wstecz',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          cursorColor: palette.accent,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: AppFontSize.listTitle,
          ),
          decoration: InputDecoration(
            hintText: 'Czego chcesz posłuchać?',
            hintStyle: TextStyle(color: palette.textSecondary),
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          const SearchFieldsButton(),
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: 'Wyczyść',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_query.clear),
            ),
        ],
      ),
      body: _Results(query: _query.text),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final mainReady = catalog.status == CatalogStatus.ready;

    // Without MusicDatabase's file, phone songs can still be searched; only explain the missing
    // database when there's nothing at all to search.
    if (!mainReady && library.songCount == 0) {
      switch (catalog.status) {
        case CatalogStatus.notLoaded || CatalogStatus.loading:
          return const _Message(
            icon: Icons.hourglass_empty,
            title: 'Wczytywanie bazy danych…',
            busy: true,
          );
        case CatalogStatus.noDatabase:
          if (sync.downloading) {
            return const _Message(
              icon: Icons.cloud_download_outlined,
              title: 'Trwa pobieranie bazy danych…',
              busy: true,
            );
          }
          return _Message(
            icon: Icons.storage_outlined,
            title: 'Brak pobranej bazy danych',
            details: !sync.hasSource
                ? 'Ustaw adres bazy w Ustawienia › Źródła muzyki › Baza danych.'
                : (sync.lastError ?? 'Baza nie została jeszcze pobrana.'),
            action: _OpenDatabaseSettings(),
          );
        case CatalogStatus.error:
          return _Message(
            icon: Icons.error_outline,
            title: 'Nie udało się odczytać bazy danych',
            details: 'Spróbuj pobrać ją ponownie.',
            action: _OpenDatabaseSettings(),
          );
        case CatalogStatus.ready:
          break;
      }
    }

    if (query.trim().isEmpty) {
      final total = (mainReady ? catalog.songCount : 0) + library.pendingCount;
      return _Message(
        icon: Icons.search,
        title: 'Szukaj wśród $total utworów',
        details: 'Wpisz tytuł utworu albo wykonawcę.',
      );
    }
    final results = searchEverywhere(query, catalog, library);
    if (results.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        title: 'Brak wyników dla „${query.trim()}”',
      );
    }
    return ListView.builder(
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Utwory: ${results.length}',
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          );
        }
        return _SongTile(hit: results[i - 1], query: query.trim());
      },
    );
  }
}

const _coverSize = 48.0;

class _SongTile extends StatelessWidget {
  const _SongTile({required this.hit, required this.query});

  final SearchHit hit;

  /// The search the result came from, shown in the full player.
  final String query;

  String get _coverSeed => hit.mainSong != null
      ? '${hit.mainSong!.id}'
      : hit.phoneFiles.first.filePath;

  Future<void> _onTap(BuildContext context, PlayerController player) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (hit.availability) {
      case SongAvailability.available:
        final ok = await player.play(
          NowPlaying(
            title: hit.title,
            artist: hit.artistLabel,
            filePath: hit.phoneFiles.first.filePath,
            coverSeed: _coverSeed,
            searchQuery: query,
          ),
        );
        if (!ok && player.lastError != null) {
          messenger.showSnackBar(SnackBar(content: Text(player.lastError!)));
        }
      case SongAvailability.potentiallyAvailable:
      case SongAvailability.unavailable:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Ten utwór jest niedostępny — nie ma go na telefonie.',
              ),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = PlayerScope.of(context);
    final isCurrent =
        hit.onPhone &&
        player.current?.filePath != null &&
        hit.phoneFiles.any((f) => f.filePath == player.current!.filePath);
    final details = [
      hit.artistLabel,
      if (hit.album != null && hit.album!.isNotEmpty) hit.album!,
      if (hit.year != null) '${hit.year}',
    ].join(' • ');
    return ListTile(
      leading: CoverArt(seed: _coverSeed, size: _coverSize),
      // The song in the player is highlighted like in the reference app.
      title: Row(
        children: [
          if (isCurrent) ...[
            Icon(Icons.equalizer, size: 18, color: palette.accent),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              hit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isCurrent ? TextStyle(color: palette.accent) : null,
            ),
          ),
        ],
      ),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _SourceIcons(hit: hit),
      onTap: () => _onTap(context, player),
    );
  }
}

/// Column of three small icons next to a result, as tall as the cover and half as wide:
/// in MusicDatabase, on the phone (with "*" when not in MusicDatabase yet), and a play button.
/// Each icon keeps its slot even when hidden, so they line up from row to row.
class _SourceIcons extends StatelessWidget {
  const _SourceIcons({required this.hit});

  final SearchHit hit;

  static const _slot = _coverSize / 3;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget slot({
      required bool visible,
      required String tooltip,
      required Widget child,
    }) => SizedBox.square(
      dimension: _slot,
      child: visible
          ? Tooltip(
              message: tooltip,
              child: Center(child: child),
            )
          : null,
    );

    return SizedBox(
      width: _coverSize / 2,
      height: _coverSize,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          slot(
            visible: hit.inMainDatabase,
            tooltip: 'W bazie danych',
            child: Icon(Icons.storage, size: 14, color: palette.textSecondary),
          ),
          slot(
            visible: hit.onPhone,
            tooltip: hit.pending
                ? 'Na telefonie, spoza bazy danych'
                : 'Na telefonie',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.smartphone, size: 14, color: palette.textSecondary),
                if (hit.pending)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Text(
                      '*',
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // No action yet — a placeholder for future playback (YouTube-style icon).
          slot(
            visible: true,
            tooltip: 'Odtwórz',
            child: const Icon(
              Icons.smart_display,
              size: 16,
              color: Color(0xFFFF0033),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenDatabaseSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.textPrimary,
        shape: context.palette.pillShape,
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DatabaseSourceScreen()),
      ),
      child: const Text('Ustawienia bazy danych'),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.details,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? details;
  final Widget? action;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Icon(icon, size: 48, color: palette.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppFontSize.listTitle,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
