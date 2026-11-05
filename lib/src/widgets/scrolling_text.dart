import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A [Text] that slides sideways, back and forth, when it doesn't fit, instead
/// of ending in "…". Sizes itself like [Text]. A text allowed [maxLines] above
/// one wraps as usual while it fits in them, and scrolls on one line otherwise.
///
/// Waits are timers and each slide is a finite animation, so between slides it
/// asks for no frames (and `pumpAndSettle` in tests settles).
class ScrollingText extends StatefulWidget {
  const ScrollingText(
    String this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
  }) : span = null;

  const ScrollingText.rich(
    InlineSpan this.span, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
  }) : text = null;

  final String? text;
  final InlineSpan? span;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;

  static const pixelsPerSecond = 30.0;
  static const pauseAtStart = Duration(milliseconds: 2500);
  static const pauseAtEnd = Duration(milliseconds: 1500);

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(vsync: this);
  Timer? _pause;
  double _overflow = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still != _still) {
      _still = still;
      _restart();
    }
  }

  @override
  void didUpdateWidget(ScrollingText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.span != widget.span) _restart();
  }

  @override
  void dispose() {
    _pause?.cancel();
    _slide.dispose();
    super.dispose();
  }

  void _overflowChanged(double overflow) {
    // Reported from layout, when a ticker can't be started yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || overflow == _overflow) return;
      _overflow = overflow;
      _restart();
    });
  }

  void _restart() {
    _pause?.cancel();
    _slide.value = 0;
    if (_overflow <= 0 || _still) return;
    _slide.duration = Duration(
      milliseconds: (_overflow / ScrollingText.pixelsPerSecond * 1000).ceil(),
    );
    _pause = Timer(ScrollingText.pauseAtStart, _slideThere);
  }

  // A stopped animation's future never completes, so _restart ends these loops.
  void _slideThere() => _slide.forward().then((_) {
    _pause = Timer(ScrollingText.pauseAtEnd, _slideBack);
  });

  void _slideBack() => _slide.reverse().then((_) {
    _pause = Timer(ScrollingText.pauseAtStart, _slideThere);
  });

  InlineSpan get _span => widget.span ?? TextSpan(text: widget.text);

  Widget _wrapped({required int maxLines}) => Text.rich(
    _span,
    style: widget.style,
    textAlign: widget.textAlign,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );

  Widget _scrolling() => _Marquee(
    progress: _slide,
    onOverflow: _overflowChanged,
    child: Text.rich(
      _span,
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_still) return _wrapped(maxLines: widget.maxLines);
    if (widget.maxLines == 1) return _scrolling();
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style.merge(widget.style),
            children: [_span],
          ),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        if (fits) {
          _overflowChanged(0);
          return _wrapped(maxLines: widget.maxLines);
        }
        return _scrolling();
      },
    );
  }
}

class _Marquee extends SingleChildRenderObjectWidget {
  const _Marquee({
    required this.progress,
    required this.onOverflow,
    required super.child,
  });

  final Animation<double> progress;
  final ValueChanged<double> onOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMarquee(progress, onOverflow);

  @override
  void updateRenderObject(BuildContext context, _RenderMarquee renderObject) {
    renderObject.onOverflow = onOverflow;
  }
}

/// Lays its child out at full width and shows the part that fits. No
/// [Scrollable]: these sit inside lists, whose scroll notifications,
/// `ensureVisible` and tests' `find.byType(Scrollable)` mustn't meet them.
class _RenderMarquee extends RenderProxyBox {
  _RenderMarquee(this._progress, this.onOverflow);

  final Animation<double> _progress;
  ValueChanged<double> onOverflow;
  double _overflow = 0;
  final _clip = LayerHandle<ClipRectLayer>();

  Offset get _shift => Offset(-_overflow * _progress.value, 0);

  // Painting every frame of a slide mustn't repaint what's around the text.
  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  // minWidth is kept so that textAlign works when the parent sets the width.
  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.minWidth,
        minHeight: constraints.minHeight,
        maxHeight: constraints.maxHeight,
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    child!.getDryLayout(_childConstraints(constraints)),
  );

  @override
  void performLayout() {
    child!.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child!.size);
    // Rounding of a text that fits isn't worth a slide.
    final excess = child!.size.width - size.width;
    final overflow = excess < 1 ? 0.0 : excess;
    if (overflow != _overflow) {
      _overflow = overflow;
      onOverflow(overflow);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_overflow == 0) {
      _clip.layer = null;
      context.paintChild(child!, offset);
      return;
    }
    // Only the sides: tall diacritics may reach above the line.
    final visible = Rect.fromLTRB(0, -size.height, size.width, size.height * 2);
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      visible,
      (context, offset) => context.paintChild(child!, offset + _shift),
      oldLayer: _clip.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, 0, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _shift,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
}
