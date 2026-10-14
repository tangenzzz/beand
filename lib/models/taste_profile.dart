import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The eight axes of the rating flower.
///
/// The upper half collects what's good about the shot, the lower half what's
/// off — so opposites sit vertically across from each other (Sweetness over
/// Hollow, Body over Astringent …). The order of the values is that of the
/// segments counterclockwise from the right; [sector] pins it so drawing and
/// tapping use the same mapping.
enum TasteAxis {
  finish('Finish', 'Finish', 0, true),
  body('Body', 'Body', 1, true),
  acidity('Acidity', 'Acid', 2, true),
  sweetness('Sweetness', 'Sweet', 3, true),
  hollow('Hollow', 'Hollow', 4, false),
  salty('Salty', 'Salt', 5, false),
  astringent('Astringent', 'Astr.', 6, false),
  bitter('Bitter', 'Bitter', 7, false);

  const TasteAxis(this.label, this.shortLabel, this.sector, this.isPositive);

  final String label;

  /// Abbreviation for tight spots (card).
  final String shortLabel;

  /// Segment number, counterclockwise from the 3 o'clock direction.
  final int sector;

  final bool isPositive;

  // The color comes from the theme, so it needs the context.
  Color color(BuildContext context) =>
      isPositive ? context.colors.accent : context.colors.sensorUp;

  /// Highest value of an axis: three points. One tap means "was there", each
  /// further tap increases it, the fourth clears the value again.
  static const maxValue = 3;
}

/// One value per axis, 0 (not rated) to [TasteAxis.maxValue].
typedef TasteValues = Map<TasteAxis, int>;

extension TasteValuesX on TasteValues {
  bool get isRated => values.any((v) => v > 0);

  int get positiveSum =>
      entries.where((e) => e.key.isPositive).fold(0, (sum, e) => sum + e.value);

  int get negativeSum => entries
      .where((e) => !e.key.isPositive)
      .fold(0, (sum, e) => sum + e.value);

  /// A value from 0 to 100: the balance between upper and lower half.
  /// All unrated gives 50, only good 100, only off 0.
  ///
  /// Clamped because shots still rated with the flower (0-5 per axis) can
  /// exceed today's range.
  int get score {
    const span = 4 * TasteAxis.maxValue;
    final raw = ((positiveSum - negativeSum) / span + 1) / 2 * 100;
    return raw.clamp(0, 100).round();
  }
}

/// Free extra attributes of a shot, stored comma-separated
/// ("strawberry, ash"). Unlike the eight axes they have no score and no
/// polarity — they are just present or not.
List<String> splitTasteExtras(String? raw) => (raw ?? '')
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

String? joinTasteExtras(Iterable<String> extras) {
  final cleaned = [
    for (final e in extras)
      if (e.trim().isNotEmpty) e.trim(),
  ];
  return cleaned.isEmpty ? null : cleaned.join(', ');
}
