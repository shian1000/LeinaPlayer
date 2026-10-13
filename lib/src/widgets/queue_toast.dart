import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// A short note right above the mini player, like the reference app's "Dodano do kolejki":
/// gone after [duration], or as soon as the mini player or the bottom bar is touched — unlike a
/// SnackBar, it never stays over the full player.
class QueueToast extends ChangeNotifier {
  static const duration = Duration(seconds: 3);

  ({String text, String? actionLabel, VoidCallback? onAction})? _shown;
  Timer? _timer;

  ({String text, String? actionLabel, VoidCallback? onAction})? get shown =>
      _shown;

  void show(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? shownFor,
  }) {
    _timer?.cancel();
    _shown = (text: text, actionLabel: actionLabel, onAction: onAction);
    _timer = Timer(shownFor ?? duration, hide);
    notifyListeners();
  }

  void hide() {
    _timer?.cancel();
    if (_shown == null) return;
    _shown = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Makes the [QueueToast] of the [AppShell] reachable from the screens in its tabs.
class QueueToastScope extends InheritedNotifier<QueueToast> {
  const QueueToastScope({
    super.key,
    required QueueToast super.notifier,
    required super.child,
  });

  /// `null` outside the app shell (e.g. on a screen covering it).
  static QueueToast? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<QueueToastScope>()?.notifier;
}

/// Shows the [QueueToast] of the nearest [QueueToastScope], sliding in from below.
class QueueToastView extends StatelessWidget {
  const QueueToastView({super.key});

  @override
  Widget build(BuildContext context) {
    final toast = context
        .dependOnInheritedWidgetOfExactType<QueueToastScope>()!
        .notifier!;
    final shown = toast.shown;
    final palette = context.palette;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: shown == null
          ? const SizedBox.shrink()
          : Padding(
              key: ObjectKey(shown),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Material(
                color: palette.snackBackground,
                shape: palette.boxShape(8),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            shown.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.snackForeground,
                              fontSize: AppFontSize.body,
                            ),
                          ),
                        ),
                      ),
                      if (shown.actionLabel != null)
                        TextButton(
                          onPressed: () {
                            toast.hide();
                            shown.onAction?.call();
                          },
                          child: Text(
                            shown.actionLabel!,
                            style: TextStyle(
                              color: palette.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
