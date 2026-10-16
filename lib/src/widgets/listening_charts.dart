import 'package:flutter/material.dart';

import '../theme.dart';

/// "45 min", "< 1 min".
String minutesLabel(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  return minutes == 0 && d > Duration.zero ? '< 1 min' : '$minutes min';
}

/// Listened time by the hour of day: one thin bar per hour, the busiest hour named.
class HourChart extends StatelessWidget {
  const HourChart({super.key, required this.hours});

  static const _height = 96.0;

  final List<Duration> hours;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final most = hours.reduce((a, b) => a > b ? a : b);
    final peak = hours.indexOf(most);
    final caption = TextStyle(
      fontSize: AppFontSize.caption,
      color: palette.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Najwięcej słuchasz między $peak:00 a ${(peak + 1) % 24}:00',
            style: const TextStyle(fontSize: AppFontSize.body),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (hour, time) in hours.indexed)
                  Expanded(
                    child: Tooltip(
                      message: '$hour:00 – ${minutesLabel(time)}',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: most == Duration.zero
                            ? 0
                            : (_height * time.inSeconds / most.inSeconds).clamp(
                                time > Duration.zero ? 2.0 : 0.0,
                                _height,
                              ),
                        decoration: BoxDecoration(
                          color: hour == peak
                              ? palette.accent
                              : palette.accent.withValues(alpha: 0.45),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.divider),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final label in ['0', '6', '12', '18'])
                Expanded(child: Text(label, style: caption)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Listened time month by month (a year's or a season's summary): a bar per month, its short
/// name under it.
class MonthChart extends StatelessWidget {
  const MonthChart({super.key, required this.months, this.height = 120});

  static const _names = [
    'sty',
    'lut',
    'mar',
    'kwi',
    'maj',
    'cze',
    'lip',
    'sie',
    'wrz',
    'paź',
    'lis',
    'gru',
  ];

  final List<({DateTime month, Duration listened})> months;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final most = months
        .map((m) => m.listened)
        .fold(Duration.zero, (a, b) => a > b ? a : b);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: most == Duration.zero
                        ? 0
                        : (height * m.listened.inSeconds / most.inSeconds)
                              .clamp(
                                m.listened > Duration.zero ? 2.0 : 0.0,
                                height,
                              ),
                    decoration: BoxDecoration(
                      color: m.listened == most
                          ? palette.accent
                          : palette.accent.withValues(alpha: 0.45),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.divider),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final m in months)
              Expanded(
                child: Text(
                  _names[m.month.month - 1],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
