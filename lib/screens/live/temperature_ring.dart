import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// The Home screen's hero ring: large current value, target and status line
// below it, the double progress ring around it (inner preheat, outer
// "Stabilized"). Shared — the Meticulous card feeds it from four sensors,
// the GaggiMate hero from its single one. So both machines look the same
// without the Meticulous calculations (ETA model, stabilization band)
// moving into the GaggiMate hero.
//
// outerProgress == null means: only ONE ring. "Stabilized" compares four
// sensors with each other — a machine with one sensor has nothing to go on,
// and an empty second ring would just look like a failure.

class TemperatureRing extends StatelessWidget {
  const TemperatureRing({
    super.key,
    required this.heroValue,
    required this.targetTemp,
    required this.progress,
    required this.outerProgress,
    required this.color,
    required this.statusText,
    required this.statusColor,
    required this.showCheck,
    this.size = defaultSize,
  });

  final double? heroValue;
  final double? targetTemp;
  final double progress;
  final double? outerProgress;
  final Color color;
  final String? statusText;
  final Color statusColor;
  final bool showCheck;

  // Diameter. The text inside stays the same — a larger ring just gives it
  // more room (GaggiMate hero).
  final double size;

  // Ring and text slightly larger (previously 128, hero 24 / target 9 /
  // status 10). Public because the sensor column next to it sizes itself
  // exactly by this and must never be taller.
  static const defaultSize = 168.0;

  // Duration of the glide to the new ring value.
  static const _glide = Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Both rings glide to the new value instead of jumping. A new
          // value mid-glide starts from the current position — at ~9
          // readings/s the ring follows the temperature as a calm,
          // continuous motion.
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: _glide,
            curve: Curves.easeOutCubic,
            builder: (context, inner, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: outerProgress ?? 0),
              duration: _glide,
              curve: Curves.easeOutCubic,
              builder: (context, outer, _) => CustomPaint(
                size: Size(size, size),
                painter: _RingPainter(
                  progress: inner,
                  outerProgress: outerProgress == null ? null : outer,
                  color: color,
                  track: context.colors.divider,
                  // The same token as the inner ring at target — not the
                  // accent color, which changed with the setting.
                  stabilizedColor: context.colors.heroRingReady,
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                heroValue == null ? '—' : '${heroValue!.toStringAsFixed(1)}°',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 12,
                    color: context.colors.textSecondary,
                  ),
                  if (targetTemp != null) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${targetTemp!.toStringAsFixed(1)}°',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    statusText ?? '~',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (showCheck) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.check_rounded, size: 13, color: statusColor),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.outerProgress,
    required this.color,
    required this.track,
    required this.stabilizedColor,
  });

  final double progress;
  final double? outerProgress;
  final Color color;

  /// The unfilled track of both rings.
  final Color track;

  /// The outer ring ("Stabilized").
  final Color stabilizedColor;

  // Double ring without a gap: inside the familiar preheat progress,
  // outside "Stabilized". Together ~10px, so almost the previous ring
  // thickness of 9px.
  static const _strokeWidth = 5.0;

  void _drawRing(
    Canvas canvas,
    Offset center,
    double radius,
    double value,
    Color fillColor,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - _strokeWidth / 2;
    final stabilized = outerProgress;
    if (stabilized == null) {
      // Single ring: sits outside so it stays as large as the double ring
      // combined and both machines show the same diameter.
      _drawRing(canvas, center, outerRadius, progress, color);
      return;
    }
    _drawRing(canvas, center, outerRadius - _strokeWidth, progress, color);
    _drawRing(canvas, center, outerRadius, stabilized, stabilizedColor);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.outerProgress != outerProgress ||
        oldDelegate.color != color ||
        oldDelegate.track != track ||
        oldDelegate.stabilizedColor != stabilizedColor;
  }
}
