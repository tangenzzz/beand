import 'dart:math' as math;

import 'brew_recipe.dart';

// The sequence of a pour-over brew from recipe + chosen dose.
//
// Times in the recipe: we read `wait_seconds` as the pause AFTER the pour
// (fits most recipes in the repo, e.g. "Bloom 40 s, then 15 s each"). The
// pouring duration itself is not given anywhere — we assume the ideal flow
// for it. Live, however, what happens on the scale counts: a pour is done
// when its target weight is reached, then its pause runs (see BrewProgress).

/// Ideal flow while pouring (g/s) — middle of the green zone on the gauge.
const idealPourFlow = 5.0;

/// Green up to ±1.5 g/s around the ideal, yellow up to ±3 g/s, red beyond.
const flowGreenBand = 1.5;
const flowYellowBand = 3.0;

/// Gauge scale: 0 … 2× ideal so the ideal sits at the top (12 o'clock).
const flowDialMax = idealPourFlow * 2;

/// Grams of tolerance at which a pour counts as reached.
const stepTolerance = 1.5;

enum FlowZone { green, yellow, red }

FlowZone flowZone(double gPerS) {
  final d = (gPerS - idealPourFlow).abs();
  if (d <= flowGreenBand) return FlowZone.green;
  if (d <= flowYellowBand) return FlowZone.yellow;
  return FlowZone.red;
}

class BrewPlan {
  BrewPlan(this.recipe, {double? doseG})
    : doseG = doseG ?? recipe.doseG,
      steps = _scaled(recipe, (doseG ?? recipe.doseG) / recipe.doseG);

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

  /// Target weight after [seconds] according to the plan (pour at ideal
  /// flow, then pause) — the dashed line in the chart.
  double targetAt(double seconds) {
    var t = 0.0;
    for (final s in steps) {
      final pour = s.waterG / idealPourFlow;
      if (seconds < t + pour) {
        return s.startTotalG + (seconds - t) * idealPourFlow;
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
      t += s.waterG / idealPourFlow + (s.waitSeconds ?? 0);
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
        t += left / idealPourFlow;
        // Last pour: the pause after it is drawdown time, it doesn't count.
        if (i < steps.length - 1) t += waitLeft ?? (s.waitSeconds ?? 0);
      } else {
        t += s.waterG / idealPourFlow;
        if (i < steps.length - 1) t += s.waitSeconds ?? 0;
      }
    }
    return t;
  }

  static List<BrewStep> _scaled(BrewRecipe r, double factor) => [
    for (final s in r.steps)
      BrewStep(
        label: s.label,
        waterG: _round(s.waterG * factor),
        targetTotalG: _round(s.targetTotalG * factor),
        waitSeconds: s.waitSeconds,
        note: s.note,
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
