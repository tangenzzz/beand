import 'dart:math' as math;

import 'brew_recipe.dart';

// The sequence of a pour-over brew from recipe + chosen dose.
//
// Times in the recipe: we read `wait_seconds` as the pause AFTER the pour
// (fits most recipes in the repo, e.g. "Bloom 40 s, then 15 s each"). A
// profile says how long each pour takes; the collection's recipes don't, for
// those we assume the ideal flow. Live, however, what happens on the scale
// counts: a pour is done when its target weight is reached, then its pause
// runs (see BrewProgress).

/// Flow without a target from a profile (g/s).
const idealPourFlow = 5.0;

/// Green up to ±30 % around the target, yellow up to ±60 %, red beyond. At
/// the 5 g/s default that is ±1.5 and ±3 g/s.
const flowGreenShare = 0.3;
const flowYellowShare = 0.6;

/// Gauge scale for a target: 0 … 2× so the target sits at the top.
double flowDialMaxFor(double target) => target * 2;

/// Flow axis of the live chart, the same for every brew.
const flowDialMax = idealPourFlow * 2;

/// Grams of tolerance at which a pour counts as reached.
const stepTolerance = 1.5;

enum FlowZone { green, yellow, red }

FlowZone flowZone(double gPerS, {double target = idealPourFlow}) {
  final d = (gPerS - target).abs();
  if (d <= target * flowGreenShare) return FlowZone.green;
  if (d <= target * flowYellowShare) return FlowZone.yellow;
  return FlowZone.red;
}

extension BrewStepTiming on BrewStep {
  /// The profile's pour time, else at the ideal flow.
  double get plannedPourSeconds {
    final s = pourSeconds;
    return s != null && s > 0 ? s : waterG / idealPourFlow;
  }

  /// What the gauge aims for during this pour.
  double get targetFlow {
    final t = plannedPourSeconds;
    return t > 0 && waterG > 0 ? waterG / t : idealPourFlow;
  }
}

final _amount = RegExp(
  r'(?<![\d.,:])(\d+(?:[.,]\d+)?)(\s?)(g|ml)\b',
  caseSensitive: false,
);

/// Amounts written in a profile's text ("Pour to 170 g") follow the coffee
/// actually used, like the numbers next to them.
String scaleAmounts(String text, double factor) {
  if ((factor - 1).abs() < 0.001) return text;
  return text.replaceAllMapped(_amount, (m) {
    final value = double.parse(m[1]!.replaceAll(',', '.')) * factor;
    // Whole grams, like the steps' own numbers.
    final shown = value.round();
    return '$shown${m[2]}${m[3]}';
  });
}

class BrewPlan {
  // A dose of 0 (or none, or nonsense) falls back to the recipe's: scaled
  // by 0 every pour was 0 g — the chart crashed on a zero grid and the
  // ratio on 1:∞ (bug 2026-11-04).
  BrewPlan(this.recipe, {double? doseG})
    : doseG = _validDose(doseG) ?? recipe.doseG,
      steps = _scaled(
        recipe,
        (_validDose(doseG) ?? recipe.doseG) / recipe.doseG,
      );

  static double? _validDose(double? g) =>
      g != null && g.isFinite && g >= 1 ? g : null;

  final BrewRecipe recipe;
  final double doseG;
  final List<BrewStep> steps;

  double get scale => doseG / recipe.doseG;
  double get totalWaterG => steps.isEmpty ? 0 : steps.last.targetTotalG;
  double get ratio => totalWaterG / doseG;

  /// Index of the pour [grams] belongs to (the first one not yet reached);
  /// after the last one: steps.length.
  int stepIndexFor(double grams) {
    for (var i = 0; i < steps.length; i++) {
      if (grams < steps[i].targetTotalG - stepTolerance) return i;
    }
    return steps.length;
  }

  /// Planned total duration until the end of the last pour (s).
  double get plannedSeconds => _secondsFrom(0, 0);

  /// Target weight after [seconds] according to the plan (pour, then pause)
  /// — the dashed line in the chart.
  double targetAt(double seconds) {
    var t = 0.0;
    for (final s in steps) {
      final pour = s.plannedPourSeconds;
      if (seconds < t + pour) {
        return s.startTotalG + (seconds - t) * s.targetFlow;
      }
      t += pour;
      final wait = s.waitSeconds ?? 0;
      if (seconds < t + wait) return s.targetTotalG;
      t += wait;
    }
    return totalWaterG;
  }

  /// Start times of the pours according to the plan (s) — for the chart
  /// phases.
  List<double> get plannedStepStarts {
    final out = <double>[];
    var t = 0.0;
    for (final s in steps) {
      out.add(t);
      t += s.plannedPourSeconds + (s.waitSeconds ?? 0);
    }
    return out;
  }

  /// Remaining time when pour [index] is at [pouredInStep] g or its pause
  /// still lasts [waitLeft] s.
  double remainingSeconds(
    int index, {
    double pouredInStep = 0,
    double waitLeft = 0,
  }) => _secondsFrom(index, pouredInStep, waitLeft: waitLeft);

  double _secondsFrom(int index, double pouredInStep, {double? waitLeft}) {
    if (index >= steps.length) return 0;
    var t = 0.0;
    for (var i = index; i < steps.length; i++) {
      final s = steps[i];
      if (i == index) {
        final left = math.max(0.0, s.waterG - pouredInStep);
        t += left / s.targetFlow;
        // Last pour: the pause after it is drawdown time, it doesn't count.
        if (i < steps.length - 1) t += waitLeft ?? (s.waitSeconds ?? 0);
      } else {
        t += s.plannedPourSeconds;
        if (i < steps.length - 1) t += s.waitSeconds ?? 0;
      }
    }
    return t;
  }

  static List<BrewStep> _scaled(BrewRecipe r, double factor) => [
    for (final s in r.steps)
      BrewStep(
        label: scaleAmounts(s.label, factor),
        waterG: _round(s.waterG * factor),
        targetTotalG: _round(s.targetTotalG * factor),
        waitSeconds: s.waitSeconds,
        note: s.note == null ? null : scaleAmounts(s.note!, factor),
        // More coffee means more water at the same flow.
        pourSeconds: s.pourSeconds == null ? null : s.pourSeconds! * factor,
      ),
  ];

  // To whole grams — nobody can pour half grams from a kettle.
  static double _round(double g) => g.roundToDouble();
}

/// Smooths the scale readings into a flow (g/s) over a short window.
class FlowEstimator {
  FlowEstimator({this.window = const Duration(milliseconds: 1500)});

  final Duration window;
  final _points = <({int ms, double g})>[];

  void add(int ms, double grams) {
    _points.add((ms: ms, g: grams));
    while (_points.length > 2 &&
        ms - _points.first.ms > window.inMilliseconds) {
      _points.removeAt(0);
    }
  }

  void reset() => _points.clear();

  /// Slope (linear regression) — more robust against scale jitter than
  /// first/last point. Never negative (dripping/tare wobble).
  double get gramsPerSecond {
    if (_points.length < 2) return 0;
    final n = _points.length;
    final t0 = _points.first.ms;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final p in _points) {
      final x = (p.ms - t0) / 1000;
      sx += x;
      sy += p.g;
      sxx += x * x;
      sxy += x * p.g;
    }
    final den = n * sxx - sx * sx;
    if (den == 0) return 0;
    return math.max(0, (n * sxy - sx * sy) / den);
  }
}
