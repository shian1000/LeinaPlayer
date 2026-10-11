import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';

/// "Kolejka", opened from the full player: the song playing, the songs added with "Dodaj do
/// kolejki", then the rest of the playlist / results in play order. Tapping a song plays it
/// (skipping the ones before it); each can be taken out.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => const QueueScreen()));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final queue = PlaybackQueueScope.of(context);
    final current = queue.current;
    final added = queue.added;
    final rest = queue.contextUpcoming;
    final contextName = queue.playlistName != null
        ? 'Następne z: ${queue.playlistName}'
        : queue.searchQuery != null
        ? 'Następne z: „${queue.searchQuery}” w wyszukiwarce'
        : 'Następne';

    Widget heading(String text, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppFontSize.emphasis,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Kolejka'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          heading('Teraz odtwarzane'),
          if (current != null)
            _QueueRow(hit: current, isCurrent: true)
          else
            _Empty('Nic nie jest odtwarzane'),
          if (added.isNotEmpty) ...[
            heading(
              'Następne w kolejce',
              action: TextButton(
                onPressed: queue.clearAdded,
                child: const Text('Wyczyść kolejkę'),
              ),
            ),
            for (final entry in added) _UpcomingRow(entry: entry),
          ],
          if (rest.isNotEmpty) ...[
            heading(contextName),
            for (final entry in rest) _UpcomingRow(entry: entry),
          ],
          if (added.isEmpty && rest.isEmpty)
            _Empty(
              'Po tym utworze nic więcej nie zagra. Dodaj coś przez '
              '„Dodaj do kolejki” w menu utworu.',
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => queue.setShuffle(!queue.shuffle),
                icon: Icon(
                  Icons.shuffle,
                  color: queue.shuffle ? palette.accent : null,
                ),
                label: Text(
                  queue.shuffle ? 'Losowo: wł.' : 'Losowo: wył.',
                  style: TextStyle(
                    color: queue.shuffle ? palette.accent : palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, style: TextStyle(color: context.palette.textSecondary)),
  );
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.entry});

  final QueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final queue = PlaybackQueueScope.of(context);
    return _QueueRow(
      key: ValueKey(entry.key),
      hit: entry.hit,
      onTap: () => runQueueAction(
        context,
        (onStatus) => queue.jumpTo(entry, onStatus: onStatus),
      ),
      trailing: IconButton(
        tooltip: 'Usuń z kolejki',
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => queue.remove(entry),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.hit,
    this.isCurrent = false,
    this.onTap,
    this.trailing,
  });

  final SearchHit hit;
  final bool isCurrent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: CoverArt(seed: hit.coverSeed, size: SongTile.coverSize),
      title: CurrentTitle(text: hit.title, isCurrent: isCurrent),
      subtitle: Text(
        hit.artistLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SourceIcons(hit: hit),
          trailing ?? const SizedBox(width: 12),
        ],
      ),
      onTap: onTap,
    );
  }
}
