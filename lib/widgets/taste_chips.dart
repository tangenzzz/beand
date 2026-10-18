import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/taste_profile.dart';
import '../theme/app_theme.dart';

/// The rating chips — they replace the rating flower in the card and shot
/// detail, because the flower's small rings were too hard to hit with a
/// finger.
///
/// The eight fixed axes ([TasteAxis]) as a 2×4 grid of notes: one tap means "was there",
/// each further tap increases up to three, the fourth clears again.
/// Turquoise for the good half, orange for the off-putting one — as in the
/// flower.
///
/// Custom free-text attributes existed briefly too; they were removed from
/// the UI again. The `shots.tasteExtras` column and its database methods
/// stay in place so nothing is lost if we bring them back.
class TasteChips extends StatelessWidget {
  const TasteChips({
    super.key,
    required this.values,
    this.shortLabels = false,
    this.onAxisChanged,
    this.onlyRated = false,
    this.dense = false,
  });

  final TasteValues values;

  /// Abbreviations instead of full names — for the card, where width is
  /// tight.
  final bool shortLabels;

  /// Null makes the chips display-only.
  final void Function(TasteAxis axis, int value)? onAxisChanged;

  /// Only show axes with points — for the shareable shot image.
  final bool onlyRated;

  /// Smaller chips (shareable shot image).
  final bool dense;

  static const _chipGap = 6.0;

  void _cycle(TasteAxis axis, int current) {
    // After the maximum back to zero — the fourth tap clears.
    onAxisChanged!(axis, current >= TasteAxis.maxValue ? 0 : current + 1);
  }

  @override
  Widget build(BuildContext context) {
    // In the app: a fixed grid of two rows à four — the pleasant notes on
    // top, the off-putting ones below. Each note is plain text with its level
    // as dots behind it: no underline, no pill. The shareable image keeps its
    // small pills (dense).
    if (!dense) {
      Widget row(bool positive) => Row(
        children: [
          for (final axis in TasteAxis.values)
            if (axis.isPositive == positive)
              Expanded(
                child: _TasteCell(
                  label: shortLabels ? axis.shortLabel : axis.label,
                  points: values[axis] ?? 0,
                  color: axis.color(context),
                  onTap: onAxisChanged == null
                      ? null
                      : () => _cycle(axis, values[axis] ?? 0),
                ),
              ),
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [row(true), row(false)],
      );
    }
    return Wrap(
      spacing: _chipGap,
      runSpacing: _chipGap,
      children: [
        for (final axis in TasteAxis.values)
          if (!onlyRated || (values[axis] ?? 0) > 0)
            _Chip(
              label: shortLabels ? axis.shortLabel : axis.label,
              points: values[axis] ?? 0,
              color: axis.color(context),
              dense: dense,
              onTap: onAxisChanged == null
                  ? null
                  : () => _cycle(axis, values[axis] ?? 0),
            ),
      ],
    );
  }
}

class _TasteCell extends StatelessWidget {
  const _TasteCell({
    required this.label,
    required this.points,
    required this.color,
    this.onTap,
  });

  final String label;
  final int points;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rated = points > 0;
    return Semantics(
      button: onTap != null,
      label: label,
      value: rated ? '$points of ${TasteAxis.maxValue}' : 'not rated',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            // Long names shrink rather than wrap, so the grid stays fixed.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: rated ? colors.textPrimary : colors.textSecondary,
                      fontSize: 14,
                      fontWeight: rated ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  for (var i = 0; i < points; i++) ...[
                    SizedBox(width: i == 0 ? 5 : 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shareable image's chip: label followed by one dot per level. Without dots it stays empty
/// (outline only), with dots it fills in its color. Sizes enlarged compared
/// to the original design (28 px): 34 px tall, radius 17, 5 px dots,
/// font 13.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.points,
    required this.color,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final int points;
  final Color color;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final active = points > 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: dense ? 24 : 34,
        padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(dense ? 12 : 17),
          border: Border.all(color: active ? color : context.colors.divider),
          color: active ? color.withValues(alpha: 0.14) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? color : context.colors.textSecondary,
                fontSize: dense ? 11 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              for (var i = 0; i < points; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Container(
                  width: dense ? 4 : 5,
                  height: dense ? 4 : 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2.5),
                    color: color,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
