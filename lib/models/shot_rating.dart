import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The seven axes of the drag rating, in the order they are asked: what you
/// notice on the first sip, then what you feel in the mouth, then what stays,
/// and the verdict on the extraction last.
///
/// Every axis is stored as a whole number from 0 to [RateAxis.steps]. On a
/// balance axis the middle (5) is ideal and the value is shown as −5 … +5;
/// on the others more is better (0 … 10).
enum RateAxis {
  acidity('Acidity', 'Ac', 'flat', 'sharp', isBalance: true),
  sweetness('Sweetness', 'Sw', 'none', 'rich'),
  flavor('Flavor', 'Fl', 'muted', 'intense'),
  body('Body', 'Bo', 'thin', 'syrupy', isBalance: true),
  mouthfeel('Mouthfeel', 'Mo', 'rough', 'silky'),
  aftertaste('Aftertaste', 'Af', 'short', 'long'),
  extraction('Extraction', 'Ex', 'sour', 'bitter', isBalance: true, weight: 2);

  const RateAxis(
    this.label,
    this.shortLabel,
    this.lowLabel,
    this.highLabel, {
    this.isBalance = false,
    this.weight = 1,
  });

  final String label;

  /// Two letters for the row of values.
  final String shortLabel;

  /// What the left and the right end of the line mean.
  final String lowLabel;
  final String highLabel;

  /// Ideal in the middle instead of at the right end.
  final bool isBalance;

  /// Weight in the overall score — extraction counts double, since it is
  /// what dialling in is about.
  final int weight;

  /// Highest stored value; the line has [steps] + 1 marks.
  static const steps = 10;

  /// Where the dot starts before the axis is rated: the middle on every
  /// axis, so each answer is a short nudge left or right and the thumb
  /// always starts in the same place.
  int get start => steps ~/ 2;

  /// Where the ideal sits on the line.
  int get ideal => isBalance ? steps ~/ 2 : steps;

  /// The number shown to the user: −5 … +5 on a balance axis, 0 … 10 else.
  String display(int value) {
    if (!isBalance) return '$value';
    final d = value - steps ~/ 2;
    if (d == 0) return '0';
    return d > 0 ? '+$d' : '−${-d}';
  }

  /// How good a value is, 0 … 1 — on a balance axis the distance from the
  /// middle counts.
  double goodness(int value) {
    final v = value.clamp(0, steps);
    if (!isBalance) return v / steps;
    const half = steps / 2;
    return 1 - (v - half).abs() / half;
  }

  /// Accent near the ideal, the "off" color otherwise.
  Color color(BuildContext context, int value) =>
      goodness(value) >= 0.6 ? context.colors.accent : context.colors.sensorUp;
}

/// One value per axis; an axis that is missing is not rated.
typedef RateValues = Map<RateAxis, int>;

extension RateValuesX on RateValues {
  bool get isRated => isNotEmpty;

  /// 0 … 100: weighted mean of the goodness of all rated axes, or null if
  /// nothing is rated.
  int? get score {
    var sum = 0.0;
    var weights = 0;
    for (final e in entries) {
      sum += e.key.goodness(e.value) * e.key.weight;
      weights += e.key.weight;
    }
    if (weights == 0) return null;
    return (100 * sum / weights).round();
  }

  /// Stars that follow from [score]: a fifth of the range each, at least
  /// one once anything is rated.
  int? get stars {
    final s = score;
    if (s == null) return null;
    return (s / 20).round().clamp(1, 5);
  }
}
