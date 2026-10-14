import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../database/database.dart';
import '../../theme/app_theme.dart';
import 'bean_widgets.dart';

// Remaining amount in the bag: bag weight minus the doses of all shots with
// this bean. null if no bag weight is set — then there is neither ring nor
// number.
double? beanRemaining(Bean bean, Map<int, double> usage) {
  final total = bean.weightGrams;
  if (total == null || total <= 0) return null;
  return math.max(0, total - (usage[bean.id] ?? 0));
}

// Empty = nothing left (under half a gram, as the display rounds).
bool beanIsEmpty(Bean bean, Map<int, double> usage) {
  final rest = beanRemaining(bean, usage);
  return rest != null && rest < 0.5;
}

// Used up: manually marked as empty (always applies) or — with remaining
// amount [stock] enabled — empty by calculation.
bool beanUsedUp(Bean bean, Map<int, double> usage, {required bool stock}) =>
    bean.emptiedAt != null || (stock && beanIsEmpty(bean, usage));

// Below this fraction ring and number turn a muted orange.
const beanStockLowFraction = 0.2;

// Bean photo with a subtle ring that empties clockwise (the gap grows from
// 12 o'clock), and the remainder in grams at the bottom center. The number's
// box lets the photo show through blurred and interrupts the ring.
// Finished: ring and number disappear entirely, only the photo remains.
class BeanStockAvatar extends StatelessWidget {
  const BeanStockAvatar({
    super.key,
    required this.photoPath,
    required this.remaining,
    required this.total,
    this.size = 56,
    this.labelOverhang = 6,
  });

  final String? photoPath;
  // null = no bag weight: photo only.
  final double? remaining;
  final double? total;
  final double size;
  // How far the box sticks out below the ring; less in tight rows
  // (Pre-Shot picker) so it doesn't get clipped.
  final double labelOverhang;

  static const _stroke = 2.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photoSize = size - 2 * (_stroke + _gap);
    final photo = Center(
      child: BeanThumbnail(path: photoPath, size: photoSize, circle: true),
    );
    final rest = remaining;
    final full = total;
    if (rest == null || full == null || full <= 0 || rest < 0.5) {
      return SizedBox(width: size, height: size, child: photo);
    }
    final fraction = (rest / full).clamp(0.0, 1.0);
    final low = fraction < beanStockLowFraction;
    final arcColor = low
        ? colors.heroRingHeating.withValues(alpha: 0.75)
        : colors.textSecondary.withValues(alpha: 0.55);
    return Semantics(
      label: '${rest.round()} g left',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            photo,
            Positioned.fill(
              child: CustomPaint(
                painter: _StockRingPainter(
                  fraction: fraction,
                  color: arcColor,
                  track: colors.textPrimary.withValues(alpha: 0.08),
                  stroke: _stroke,
                ),
              ),
            ),
            // Center of the box on the ring line.
            Positioned(
              left: 0,
              right: 0,
              bottom: -labelOverhang,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      color: colors.card.withValues(alpha: 0.35),
                      child: Text(
                        '${rest.round()}g',
                        style: TextStyle(
                          color: low
                              ? colors.heroRingHeating
                              : colors.textPrimary.withValues(alpha: 0.85),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockRingPainter extends CustomPainter {
  const _StockRingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction <= 0) return;
    // The used part grows clockwise from 12 o'clock; the rest extends from
    // there back to 12 o'clock.
    final sweep = math.pi * 2 * fraction;
    final start = -math.pi / 2 + math.pi * 2 * (1 - fraction);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      paint
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StockRingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}
