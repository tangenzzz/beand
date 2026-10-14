import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/taste_profile.dart';
import '../theme/app_theme.dart';

/// The rating flower: eight taste axes as segments of a circle, each with
/// five rings.
///
/// At the top is what makes the shot good (teal), at the bottom what
/// detracts (orange); a line separates the two halves. A tap on a ring sets
/// the value, a tap on the same ring clears it again — like the stars.
class TasteFlower extends StatelessWidget {
  const TasteFlower({
    super.key,
    required this.values,
    this.diameter = 150,
    this.showLabels = true,
    this.shortLabels = false,
    this.onChanged,
  });

  final TasteValues values;

  /// Diameter of the circle; the labels are outside of it.
  final double diameter;

  final bool showLabels;

  /// Abbreviations instead of full names — for the card, where width is
  /// tight.
  final bool shortLabels;

  /// Null makes the flower display-only.
  final void Function(TasteAxis axis, int value)? onChanged;

  // Room for the labels left/right and top/bottom.
  static const _labelGutterX = 66.0;
  static const _shortLabelGutterX = 44.0;
  static const _labelGutterY = 22.0;

  /// Total size including labels — so callers can plan the card height
  /// without knowing the internals.
  static Size sizeFor(
    double diameter, {
    bool showLabels = true,
    bool shortLabels = false,
  }) {
    if (!showLabels) return Size.square(diameter);
    final gutterX = shortLabels ? _shortLabelGutterX : _labelGutterX;
    return Size(diameter + 2 * gutterX, diameter + 2 * _labelGutterY);
  }

  void _handleTap(Offset local, Size size) {
    final notify = onChanged;
    if (notify == null) return;
    final delta = local - Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;
    // Some leniency at the edge: the outermost ring is hard to hit otherwise.
    if (delta.distance > radius * 1.08) return;
    // On screen y points down, in the angle math up.
    var degrees = math.atan2(-delta.dy, delta.dx) * 180 / math.pi;
    if (degrees < 0) degrees += 360;
    final sector = (degrees ~/ 45) % TasteAxis.values.length;
    final axis = TasteAxis.values.firstWhere((a) => a.sector == sector);
    final level = (delta.distance / radius * TasteAxis.maxValue).ceil().clamp(
      1,
      TasteAxis.maxValue,
    );
    notify(axis, level == (values[axis] ?? 0) ? 0 : level);
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(
      diameter,
      showLabels: showLabels,
      shortLabels: shortLabels,
    );
    return Semantics(
      label: 'Taste profile',
      value: values.isRated
          ? [
              for (final axis in TasteAxis.values)
                if ((values[axis] ?? 0) > 0) '${axis.label} ${values[axis]}',
            ].join(', ')
          : 'not rated',
      child: SizedBox.fromSize(
        size: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onChanged == null
              ? null
              : (details) => _handleTap(details.localPosition, size),
          child: CustomPaint(
            painter: _FlowerPainter(
              values: values,
              diameter: diameter,
              showLabels: showLabels,
              shortLabels: shortLabels,
              axisColor: (axis) => axis.color(context),
              // Unrated rings: lighter than the card, but clearly below the
              // colors. The gaps, in contrast, as dark as the background.
              emptyColor: context.colors.textPrimary.withValues(alpha: 0.12),
              dividerColor: context.colors.bg,
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowerPainter extends CustomPainter {
  const _FlowerPainter({
    required this.values,
    required this.diameter,
    required this.showLabels,
    required this.shortLabels,
    required this.axisColor,
    required this.emptyColor,
    required this.dividerColor,
  });

  final TasteValues values;
  final double diameter;
  final bool showLabels;
  final bool shortLabels;

  /// Color of an axis — comes from the theme, hence passed in.
  final Color Function(TasteAxis axis) axisColor;

  /// Unrated rings and the gaps between the fields.
  final Color emptyColor;
  final Color dividerColor;
  // Gaps between the fields, in pixels: the same width sideways and
  // radially, so the gaps run through the flower like straight lines (in
  // degrees they would be wide outside and invisible inside).
  static const _gap = 1.3;
  // The innermost ring does not start exactly at the center, otherwise all
  // eight segments merge into a blob there.
  static const _innerFactor = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;
    final inner = radius * _innerFactor;
    final ring = (radius - inner) / TasteAxis.maxValue;

    for (final axis in TasteAxis.values) {
      final value = values[axis] ?? 0;
      for (var level = 1; level <= TasteAxis.maxValue; level++) {
        final r0 = inner + ring * (level - 1) + _gap / 2;
        final r1 = inner + ring * level - _gap / 2;
        // The sideways gap in degrees depends on the radius: wider inside,
        // narrower outside — measured at the middle of the ring it stays the
        // same width everywhere.
        final gapDegrees =
            (math.atan(_gap / 2 / ((r0 + r1) / 2)) * 180 / math.pi).clamp(
              0.0,
              14.0,
            );
        final filled = level <= value;
        final paint = Paint()
          ..color = filled
              // Lighter towards the outside: the reached value is in front.
              ? axisColor(axis).withValues(alpha: 0.5 + 0.125 * (level - 1))
              : emptyColor;
        canvas.drawPath(
          _segment(
            center,
            r0,
            r1,
            axis.sector * 45 + gapDegrees,
            45 - 2 * gapDegrees,
          ),
          paint,
        );
      }
    }

    // Divider between the good (top) and detracting (bottom) half: darker
    // than the card, like a cut through the flower.
    canvas.drawLine(
      center + Offset(-radius - 7, 0),
      center + Offset(radius + 7, 0),
      Paint()
        ..color = dividerColor
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    if (showLabels) _paintLabels(canvas, center, radius);
  }

  void _paintLabels(Canvas canvas, Offset center, double radius) {
    for (final axis in TasteAxis.values) {
      final mid = (axis.sector * 45 + 22.5) * math.pi / 180;
      final direction = Offset(math.cos(mid), -math.sin(mid));
      final anchor = center + direction * (radius + 11);
      final painter = TextPainter(
        text: TextSpan(
          text: shortLabels ? axis.shortLabel : axis.label,
          style: TextStyle(
            color: axisColor(axis).withValues(alpha: 0.92),
            fontSize: shortLabels ? 10 : 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Side labels grow outwards, the diagonal ones are centered above or
      // below their segment.
      final dx = direction.dx > 0.5
          ? 0.0
          : (direction.dx < -0.5 ? -painter.width : -painter.width / 2);
      painter.paint(canvas, anchor + Offset(dx, -painter.height / 2));
    }
  }

  // Ring segment between [r0] and [r1]; angles in degrees, counterclockwise
  // from the 3 o'clock direction — Canvas computes the other way round.
  Path _segment(
    Offset center,
    double r0,
    double r1,
    double startDegrees,
    double sweepDegrees,
  ) {
    final start = -(startDegrees + sweepDegrees) * math.pi / 180;
    final sweep = sweepDegrees * math.pi / 180;
    return Path()
      ..arcTo(Rect.fromCircle(center: center, radius: r1), start, sweep, true)
      ..arcTo(
        Rect.fromCircle(center: center, radius: r0),
        start + sweep,
        -sweep,
        false,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.diameter != diameter ||
      old.showLabels != showLabels ||
      old.shortLabels != shortLabels ||
      !mapEquals(old.values, values);
}
