import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// What dragging a row one way does: shown under the row, done on release past the threshold.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.onTriggered,
    this.color,
    this.foreground,
  });

  final IconData icon;

  /// Read out by screen readers, as the row's custom action.
  final String label;
  final VoidCallback onTriggered;

  /// Behind the row once the drag goes far enough; the theme's accent by default.
  final Color? color;
  final Color? foreground;
}

/// A row that can be dragged sideways, like the reference app's song rows: right queues the
/// song, left takes it away. Past [threshold] the colour fills in and the phone ticks;
/// letting go there triggers the action, and the row slides back either way.
class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.child, this.right, this.left});

  final Widget child;

  /// Dragging to the right.
  final SwipeAction? right;

  /// Dragging to the left.
  final SwipeAction? left;

  /// How far the row has to go, as part of its width (at most [maxThreshold]).
  static const threshold = 0.25;
  static const maxThreshold = 120.0;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);
  double _drag = 0;
  double _width = 0;
  bool _armed = false;

  double get _threshold =>
      min(_width * SwipeActions.threshold, SwipeActions.maxThreshold);

  /// Past the threshold the row follows the finger more slowly.
  double _shown(double drag) {
    final over = drag.abs() - _threshold;
    if (over <= 0) return drag;
    return drag.sign * (_threshold + over * 0.35);
  }

  void _update(DragUpdateDetails details) {
    var drag = _drag + details.primaryDelta!;
    if (drag > 0 && widget.right == null) drag = 0;
    if (drag < 0 && widget.left == null) drag = 0;
    _drag = drag;
    _offset.value = _shown(drag);
    final armed = drag.abs() >= _threshold;
    if (armed != _armed) {
      if (armed) HapticFeedback.mediumImpact();
      setState(() => _armed = armed);
    }
  }

  void _end([DragEndDetails? _]) {
    final action = !_armed
        ? null
        : _drag > 0
        ? widget.right
        : widget.left;
    _drag = 0;
    setState(() => _armed = false);
    _offset.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    action?.onTriggered();
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final right = widget.right;
    final left = widget.left;
    return Semantics(
      customSemanticsActions: {
        if (right != null)
          CustomSemanticsAction(label: right.label): right.onTriggered,
        if (left != null)
          CustomSemanticsAction(label: left.label): left.onTriggered,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: _end,
            child: AnimatedBuilder(
              animation: _offset,
              child: widget.child,
              builder: (context, child) {
                final offset = _offset.value;
                final action = offset > 0
                    ? right
                    : offset < 0
                    ? left
                    : null;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: action == null
                          ? const SizedBox()
                          : ColoredBox(
                              color: _armed
                                  ? action.color ?? palette.accent
                                  : palette.surfaceHigh,
                              child: Align(
                                alignment: offset > 0
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: AnimatedScale(
                                    scale: _armed ? 1.2 : 1,
                                    duration: const Duration(milliseconds: 120),
                                    child: Icon(
                                      action.icon,
                                      color: _armed
                                          ? action.foreground ??
                                                palette.onAccent
                                          : palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Transform.translate(
                      offset: Offset(offset, 0),
                      // Its own Material, so the row's ink still shows over the colour.
                      child: Material(
                        color: offset == 0
                            ? Colors.transparent
                            : palette.background,
                        child: child,
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
