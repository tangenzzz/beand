import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/shot_rating.dart';
import '../theme/app_theme.dart';

/// The drag rating: one axis at a time on a line with a dot. Drag (or tap)
/// the dot to a place and let go — that place is the value. The dot then
/// springs back to the start of the next axis. After the last axis the
/// widget shows all seven values in a row; tapping one asks it again.
///
/// Fixed height of [height], so it fits where the rating chips used to be
/// in the Post-Shot card.
class TasteRater extends StatefulWidget {
  const TasteRater({
    super.key,
    required this.values,
    required this.onChanged,
    this.previous,
    this.startWithSummary = false,
    this.showSummaryHeader = true,
    this.onLongPressSummary,
  });

  final RateValues values;
  final void Function(RateAxis axis, int? value) onChanged;

  /// The last rated shot with the same bean — shown as a ring on the line.
  final RateValues? previous;

  /// Open with the row of values instead of the first unrated axis (shot
  /// detail).
  final bool startWithSummary;

  /// The summary's own "Taste 78" line; off where the screen has a heading.
  final bool showSummaryHeader;

  /// Long press on the row of values (shot detail: clear the whole rating).
  final VoidCallback? onLongPressSummary;

  static const height = 76.0;

  @override
  State<TasteRater> createState() => _TasteRaterState();
}

class _TasteRaterState extends State<TasteRater>
    with SingleTickerProviderStateMixin {
  static const _axes = RateAxis.values;
  static const _inset = 12.0;
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 25.4, // ζ ≈ 0.62: one small overshoot, then rest
  );

  late final AnimationController _dot = AnimationController.unbounded(
    vsync: this,
  );
  late RateValues _values = {...widget.values};

  // Written here but not yet back from the database (null = cleared).
  final Map<RateAxis, int?> _pending = {};
  late bool _asking;
  late int _index;
  bool _redo = false;
  bool _grabbing = false;
  bool _committed = false;
  int? _step;
  double _width = 1;

  RateAxis get _axis => _axes[_index];

  @override
  void initState() {
    super.initState();
    final first = _nextUnrated(-1);
    // Nothing rated yet: straight to the first question, also in the shot
    // detail, so rating can start right away.
    _asking = first != null && !(widget.startWithSummary && _values.isNotEmpty);
    _index = first ?? 0;
    _dot.value = _axis.start / RateAxis.steps;
  }

  @override
  void didUpdateWidget(TasteRater old) {
    super.didUpdateWidget(old);
    if (mapEquals(old.values, widget.values)) return;
    final fromOutside = _pending.isEmpty;
    // The database answers a moment after our own write: take what it
    // says, but keep what was set here and has not arrived yet.
    _pending.removeWhere((axis, value) => widget.values[axis] == value);
    final next = {...widget.values};
    _pending.forEach((axis, value) {
      if (value == null) {
        next.remove(axis);
      } else {
        next[axis] = value;
      }
    });
    _values = next;
    if (!fromOutside) return;
    // Cleared elsewhere (Clear rating): all back to "–", first question.
    if (_values.isEmpty) {
      _dot.stop();
      _asking = true;
      _redo = false;
      _index = 0;
      _step = null;
      _grabbing = false;
      _dot.value = _axis.start / RateAxis.steps;
    } else if (old.values.isEmpty && widget.startWithSummary) {
      // Brought back (Undo): the row of values again.
      _asking = false;
      _redo = false;
    }
  }

  @override
  void dispose() {
    _dot.dispose();
    super.dispose();
  }

  int? _nextUnrated(int after) {
    for (var i = after + 1; i < _axes.length; i++) {
      if (!_values.containsKey(_axes[i])) return i;
    }
    return null;
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _springTo(double target) {
    if (_reduceMotion) {
      _dot.value = target;
      return;
    }
    _dot.animateWith(SpringSimulation(_spring, _dot.value, target, 0));
  }

  int _stepAt(double dx) => ((dx - _inset) / _width * RateAxis.steps)
      .round()
      .clamp(0, RateAxis.steps);

  void _moveTo(double dx) {
    _dot.stop();
    final fraction = ((dx - _inset) / _width).clamp(0.0, 1.0);
    _dot.value = fraction;
    final step = _stepAt(dx);
    if (step != _step) {
      if (_step != null) HapticFeedback.selectionClick();
      setState(() => _step = step);
    }
  }

  void _grab(double dx) {
    _committed = false;
    _step = null;
    setState(() => _grabbing = true);
    _moveTo(dx);
  }

  void _commit() {
    if (_committed || _step == null) return;
    _committed = true;
    final axis = _axis;
    final value = _step!;
    HapticFeedback.mediumImpact();
    widget.onChanged(axis, value);
    _pending[axis] = value;
    setState(() {
      _grabbing = false;
      _step = null;
      _values = {..._values, axis: value};
    });
    _advance();
  }

  // A vertical scroll took the pointer (or a tap is about to commit): go
  // back unless the tap commits in this same frame.
  void _cancel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _committed) return;
      setState(() {
        _grabbing = false;
        _step = null;
      });
      _springTo(_axis.start / RateAxis.steps);
    });
  }

  void _advance() {
    final next = _redo ? null : _nextUnrated(_index);
    if (next == null) {
      setState(() {
        _asking = false;
        _redo = false;
      });
      return;
    }
    setState(() => _index = next);
    _springTo(_axis.start / RateAxis.steps);
  }

  // The × next to the axis name: only this value goes, the question stays
  // so it can be rated anew or skipped.
  void _clearAxis() {
    final axis = _axis;
    HapticFeedback.selectionClick();
    widget.onChanged(axis, null);
    _pending[axis] = null;
    setState(() {
      _values = {..._values}..remove(axis);
      _step = null;
    });
    _springTo(axis.start / RateAxis.steps);
  }

  void _skip() {
    if (_redo) {
      setState(() {
        _asking = false;
        _redo = false;
      });
      return;
    }
    final next = _index + 1 < _axes.length ? _index + 1 : null;
    if (next == null) {
      setState(() => _asking = false);
      return;
    }
    setState(() => _index = next);
    _springTo(_axis.start / RateAxis.steps);
  }

  // From the row of values or a filled progress mark: ask that axis again.
  // An axis not rated yet carries on with the ones after it.
  void _ask(RateAxis axis) {
    _dot.stop();
    setState(() {
      _index = axis.index;
      _redo = _values.containsKey(axis);
      _asking = true;
      _grabbing = false;
      _step = null;
    });
    _dot.value = (_values[axis] ?? axis.start) / RateAxis.steps;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TasteRater.height,
      child: _asking ? _buildAsk(context) : _buildSummary(context),
    );
  }

  Widget _buildAsk(BuildContext context) {
    final colors = context.colors;
    final axis = _axis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, -0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Row(
                    key: ValueKey(axis),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        axis.label,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_values.containsKey(axis))
                        Semantics(
                          button: true,
                          label: 'Clear ${axis.label}',
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _clearAxis,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _Progress(values: _values, current: _index, onTap: _ask),
              const SizedBox(width: 8),
              _TextAction(
                label: 'Skip',
                semantics: 'Skip ${axis.label}',
                onTap: _skip,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: LayoutBuilder(
            builder: (context, box) {
              _width = math.max(1, box.maxWidth - 2 * _inset);
              return Semantics(
                slider: true,
                label: axis.label,
                value: axis.display(_values[axis] ?? axis.start),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragDown: (d) => _grab(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => _moveTo(d.localPosition.dx),
                  onHorizontalDragEnd: (_) => _commit(),
                  onHorizontalDragCancel: _cancel,
                  onTapUp: (d) {
                    if (!_grabbing) _grab(d.localPosition.dx);
                    _moveTo(d.localPosition.dx);
                    _commit();
                  },
                  child: AnimatedBuilder(
                    animation: _dot,
                    builder: (context, _) => CustomPaint(
                      painter: _LinePainter(
                        axis: axis,
                        divider: colors.divider,
                        idealColor: colors.textTertiary,
                        previous: widget.previous?[axis],
                        inset: _inset,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: _inset + _dot.value * _width - 12,
                            top: 8,
                            child: _Thumb(
                              text: axis.display(
                                _step ??
                                    (_dot.value * RateAxis.steps).round().clamp(
                                      0,
                                      RateAxis.steps,
                                    ),
                              ),
                              grabbing: _grabbing,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  axis.lowLabel,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
                Text(
                  axis.highLabel,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final colors = context.colors;
    final score = _values.score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.showSummaryHeader)
          SizedBox(
            height: 18,
            child: Row(
              children: [
                Text(
                  'Taste',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (score != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$score',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tap a value to change it',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: GestureDetector(
            onLongPress: widget.onLongPressSummary == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    widget.onLongPressSummary!();
                  },
            child: Row(
              children: [
                for (final axis in _axes)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: _values.containsKey(axis)
                          ? '${axis.label} ${axis.display(_values[axis]!)}'
                          : '${axis.label}, not rated',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _ask(axis),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _values.containsKey(axis)
                                  ? axis.display(_values[axis]!)
                                  : '–',
                              style: TextStyle(
                                color: _values.containsKey(axis)
                                    ? axis.color(context, _values[axis]!)
                                    : colors.textTertiary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              axis.shortLabel,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
      ),
    ),
  );
}

// Seven small marks: grey until rated, then in the value's color. A rated
// one can be tapped to go back to it.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.values,
    required this.current,
    required this.onTap,
  });

  final RateValues values;
  final int current;
  final ValueChanged<RateAxis> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final axis in RateAxis.values)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: values.containsKey(axis) ? () => onTap(axis) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 10,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: values.containsKey(axis)
                      ? axis.color(context, values[axis]!)
                      : axis.index == current
                      ? colors.textSecondary
                      : colors.divider,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.text, required this.grabbing});

  final String text;
  final bool grabbing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedScale(
      scale: grabbing ? 1.2 : 1,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.textPrimary,
          boxShadow: [
            BoxShadow(
              color: colors.accent.withValues(alpha: grabbing ? 0.16 : 0),
              spreadRadius: 6,
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: colors.card,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

// The line with eleven marks: longer at 0, 5 and 10, longest at the ideal;
// the previous shot's value as a ring.
class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.axis,
    required this.divider,
    required this.idealColor,
    required this.previous,
    required this.inset,
  });

  final RateAxis axis;
  final Color divider;
  final Color idealColor;
  final int? previous;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - 2 * inset;
    final mid = size.height / 2;
    final line = Paint()
      ..color = divider
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(inset, mid), Offset(inset + width, mid), line);
    for (var i = 0; i <= RateAxis.steps; i++) {
      final x = inset + i / RateAxis.steps * width;
      final ideal = i == axis.ideal;
      final major = i % 5 == 0;
      final half = ideal ? 9.0 : (major ? 6.0 : 3.0);
      canvas.drawLine(
        Offset(x, mid - half),
        Offset(x, mid + half),
        Paint()
          ..color = ideal ? idealColor : divider
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    final prev = previous;
    if (prev != null) {
      canvas.drawCircle(
        Offset(inset + prev / RateAxis.steps * width, mid),
        6.5,
        Paint()
          ..color = idealColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.axis != axis ||
      old.previous != previous ||
      old.divider != divider ||
      old.idealColor != idealColor;
}
