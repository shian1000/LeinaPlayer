import 'package:flutter/material.dart';

import '../playback/playback_queue.dart';
import '../theme.dart';
import 'menu_sheet.dart';

const _times = [
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(hours: 1),
];

/// What's left of [queue]'s sleep timer, e.g. "12 min" or "koniec utworu"; `null` when it's off.
String? sleepTimerLeft(PlaybackQueue queue) {
  if (queue.sleepAfterSong) return 'koniec utworu';
  final at = queue.sleepAt;
  if (at == null) return null;
  final left = at.difference(DateTime.now());
  // Rounded up: "0 min" while it still plays would read as already off.
  final minutes = (left.inSeconds / 60).ceil().clamp(1, 24 * 60);
  return '$minutes min';
}

/// "Wyłącznik czasowy" in a song's menu, with what's left when it's on; `null` without a queue.
MenuSheetEntry? sleepTimerEntry(BuildContext context) {
  final queue = PlaybackQueueScope.maybeOf(context);
  if (queue == null) return null;
  final left = sleepTimerLeft(queue);
  return MenuSheetEntry(
    Icons.timer_outlined,
    left == null ? 'Wyłącznik czasowy' : 'Wyłącznik czasowy: $left',
    onTap: () => showSleepTimerSheet(context),
  );
}

/// "Wyłącznik czasowy": stop the music after a while, or when the current song ends.
Future<void> showSleepTimerSheet(BuildContext context) {
  final queue = PlaybackQueueScope.of(context);
  final left = sleepTimerLeft(queue);
  String label(Duration time) =>
      time.inHours >= 1 ? '${time.inHours} godz.' : '${time.inMinutes} min';
  return showMenuSheet(
    context,
    idPrefix: 'Wyłącznik czasowy',
    header: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          const Text(
            'Wyłącznik czasowy',
            style: TextStyle(
              fontSize: AppFontSize.listTitle,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (left != null)
            Text(
              'Muzyka zatrzyma się za: $left',
              style: TextStyle(color: context.palette.textSecondary),
            ),
        ],
      ),
    ),
    entries: [
      if (left != null)
        MenuSheetEntry(
          Icons.timer_off_outlined,
          'Wyłącz wyłącznik czasowy',
          onTap: queue.cancelSleep,
        ),
      for (final time in _times)
        MenuSheetEntry(
          Icons.timer_outlined,
          label(time),
          onTap: () => queue.sleepIn(time),
        ),
      MenuSheetEntry(
        Icons.music_off_outlined,
        'Koniec utworu',
        onTap: queue.sleepAfterCurrent,
      ),
    ],
  );
}
