import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/brew_plan.dart';
import '../../../scale/brew_scale.dart';
import '../../../services/pourover_setup.dart';
import '../../../services/live_shot_service.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../sensor_stack.dart';
import '../temperature_ring.dart';
import 'recipe_format.dart';

// Pour Over hero — laid out like the machines: ring on the left with the
// same diameter (TemperatureRing.defaultSize), value column on the right
// with time (white) and weight (yellow, like the weight curve everywhere
// in the app).
//
// The ring shows the current POUR, not the whole brew: it fills up to this
// pour's target and is empty again once that is reached (pause, next pour,
// drawdown). Inside is the flow gauge with the ideal range at the top
// (12 o'clock); its needle glides to the new value instead of jumping on
// every scale packet. What to do now is in the ring too, in the gap the gauge
// leaves below the needle (user 2026-11-05); below the ring what comes next.
class PourOverHero extends StatelessWidget {
  const PourOverHero({super.key});

  static const _ringSize = TemperatureRing.defaultSize;

  // Time the needle takes to reach the new flow value. The scale delivers
  // ~10 values/s — a bit longer than one packet so it glides continuously.
  static const _needleGlide = Duration(milliseconds: 450);

  @override
  Widget build(BuildContext context) {
    final brew = context.watch<PourOverBrewService>();
    final scale = context.watch<BrewScale>();
    final running = brew.stage == ShotStage.running;
    // Before the start the hero shows what's on the scale.
    final double? grams = running ? brew.grams : scale.grams;
    final step = brew.currentStep;

    final prep = brew.prep;
    final prepStep = brew.prepActive && !running;
    final String label;
    final String? stepLine;
    if (brew.brewDone) {
      label = 'DONE';
      stepLine = brew.beverageG != null
          ? 'Yield ${formatGrams(brew.beverageG!)} g'
          : brew.serverMissing
          ? 'Server on scale'
          : null;
    } else if (!scale.isConnected) {
      label = 'NO SCALE';
      stepLine = null;
    } else if (brew.dialLeads) {
      // Machine mode: the dial leads, the app shows weight, flow and time.
      if (!running) {
        label = 'READY';
        stepLine = 'On the machine';
      } else if (brew.phase == BrewState.measuring) {
        label = 'DONE';
        stepLine = 'On the machine';
      } else {
        label = 'POURING';
        stepLine = null;
      }
    } else if (prepStep) {
      label = '${prep.stepNumber}/${PourOverSetup.stepCount}';
      stepLine = prep.status == SetupStatus.taring
          ? 'Taring…'
          : switch (prep.step) {
              SetupStep.server => 'Server on',
              SetupStep.brewer => 'Brewer on',
              SetupStep.coffee => 'Add coffee',
              SetupStep.done => '',
            };
    } else if (!running) {
      // After the steps the first water starts the brew.
      label = brew.prepComplete ? 'START POURING' : 'READY';
      stepLine = step == null ? null : '${formatGrams(step.waterG)} g';
    } else {
      switch (brew.phase) {
        case BrewState.armed:
          label = 'START POURING';
          stepLine = '0 of ${formatGrams(step!.waterG)} g';
        case BrewState.pouring:
          label = _short(step!.label, brew.stepIndex);
          stepLine =
              '${formatGrams(brew.pouredInStep.roundToDouble())} of '
              '${formatGrams(step.waterG)} g';
        case BrewState.waiting:
          label = 'WAIT';
          stepLine = formatClock(brew.waitLeftSeconds);
        case BrewState.drawdown:
          label = 'DRAWDOWN';
          stepLine = null;
        // Everything lifted: time stopped, weighing the coffee.
        case BrewState.measuring:
          label = 'DONE';
          stepLine = 'Weighing…';
      }
    }
    final needleActive =
        running &&
        (brew.phase == BrewState.pouring || brew.phase == BrewState.armed);

    // Ring = progress in the current pour; reached → empty again.
    double stepProgress = 0;
    if (running &&
        brew.phase == BrewState.pouring &&
        step != null &&
        step.waterG > 0) {
      stepProgress = (brew.pouredInStep / step.waterG).clamp(0.0, 1.0);
    }

    final values = <SensorValue>[
      SensorValue(
        'TIME',
        null,
        context.colors.textPrimary,
        text: formatClock(running ? brew.elapsedMs / 1000 : 0),
      ),
      SensorValue('G', grams, context.colors.sensorMid),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: _ringSize,
                height: _ringSize,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: brew.flow),
                  duration: _needleGlide,
                  curve: Curves.easeOut,
                  builder: (context, flow, child) => CustomPaint(
                    painter: _HeroPainter(
                      progress: stepProgress,
                      flow: flow,
                      target: brew.dialLeads
                          ? idealPourFlow
                          : step?.targetFlow ?? idealPourFlow,
                      needleActive: needleActive,
                      track: context.colors.divider,
                      progressColor: context.colors.accent,
                      green: context.colors.success,
                      yellow: context.colors.sensorMid,
                      red: context.colors.danger,
                      needle: needleActive
                          ? context.colors.textPrimary
                          : context.colors.textTertiary,
                    ),
                    child: child,
                  ),
                  child: _RingText(
                    label: label,
                    line: stepLine,
                    // Without water there is no flow to read.
                    flow: running && brew.phase != BrewState.measuring
                        ? brew.flow
                        : null,
                    size: _ringSize,
                  ),
                ),
              ),
              const SizedBox(width: SensorStack.ringToValues),
              SensorStack(sensors: values, large: true),
            ],
          ),
          // Same height with or without content, so nothing jumps when the
          // steps end and the brew starts.
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: prepStep
                ? _PrepRow(brew: brew)
                : running && !brew.dialLeads
                ? _NextLine(brew: brew)
                : null,
          ),
        ],
      ),
    );
  }

  // "Third Pour (60% — strength)" → "THIRD POUR"; without the
  // parenthetical, that belongs in the pour list. Long names → "POUR 3".
  static String _short(String label, int index) {
    final base = label.split('(').first.trim();
    return base.length > 16 ? 'POUR ${index + 1}' : base.toUpperCase();
  }
}

// What to do now, in the gap the gauge leaves below the needle: a short label,
// the amount large, and the flow while pouring. Sized to the ring's chord.
class _RingText extends StatelessWidget {
  const _RingText({
    required this.label,
    required this.line,
    required this.flow,
    required this.size,
  });

  final String label;
  final String? line;
  final double? flow;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget fit(Widget child, double share) => SizedBox(
      width: size * share,
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          // Low enough to clear the needle at rest (lower left).
          top: size * 0.62,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              fit(
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    height: 1.15,
                  ),
                ),
                0.5,
              ),
              if (line != null)
                fit(
                  Text(
                    line!,
                    maxLines: 1,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  0.72,
                ),
              if (flow != null)
                Text(
                  '${flow!.toStringAsFixed(1)} g/s',
                  maxLines: 1,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    height: 1.15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// While brewing, below the ring: the pour after this one.
class _NextLine extends StatelessWidget {
  const _NextLine({required this.brew});

  final PourOverBrewService brew;

  @override
  Widget build(BuildContext context) {
    final steps = brew.plan?.steps ?? const [];
    // During a pause the index already points at the coming pour.
    final i = brew.phase == BrewState.waiting
        ? brew.stepIndex
        : brew.stepIndex + 1;
    if (brew.phase == BrewState.measuring || i >= steps.length) {
      return const SizedBox.shrink();
    }
    final next = steps[i];
    return Center(
      child: Text(
        'Next: ${next.label} · ${formatGrams(next.waterG)} g',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter({
    required this.progress,
    required this.flow,
    required this.target,
    required this.needleActive,
    required this.track,
    required this.progressColor,
    required this.green,
    required this.yellow,
    required this.red,
    required this.needle,
  });

  final double progress;
  final double flow;

  /// The pour's flow from the profile — always at the top of the gauge.
  final double target;
  final bool needleActive;
  final Color track;
  final Color progressColor;
  final Color green;
  final Color yellow;
  final Color red;
  final Color needle;

  // Like the machines' ring (TemperatureRing).
  static const _outerStroke = 5.0;
  static const _dialStroke = 5.0;

  // Gauge: 240° arc, center (ideal value) at the top.
  static const _sweep = 240 * math.pi / 180;
  static const _start = -math.pi / 2 - _sweep / 2;

  double _angleFor(double gPerS) =>
      _start + _sweep * (gPerS / flowDialMaxFor(target)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - _outerStroke / 2;

    // Outer ring: progress in the current pour.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outerStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, ring..color = track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        ring..color = progressColor,
      );
    }

    // Gauge: red – yellow – green – yellow – red.
    final dr = r * 0.72;
    final rect = Rect.fromCircle(center: c, radius: dr);
    final zones = <(double, double, Color)>[
      (0, target * (1 - flowYellowShare), red),
      (target * (1 - flowYellowShare), target * (1 - flowGreenShare), yellow),
      (target * (1 - flowGreenShare), target * (1 + flowGreenShare), green),
      (target * (1 + flowGreenShare), target * (1 + flowYellowShare), yellow),
      (target * (1 + flowYellowShare), flowDialMaxFor(target), red),
    ];
    const gap = 0.03; // small gap between the zones (rad)
    final dial = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _dialStroke
      ..strokeCap = StrokeCap.butt;
    for (final (from, to, color) in zones) {
      final a = _angleFor(from) + gap / 2;
      final b = _angleFor(to) - gap / 2;
      canvas.drawArc(
        rect,
        a,
        b - a,
        false,
        dial..color = needleActive ? color : color.withValues(alpha: 0.35),
      );
    }

    // Needle.
    final angle = _angleFor(flow);
    final tip = c + Offset(math.cos(angle), math.sin(angle)) * (dr - 8);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = needle
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 4, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) =>
      old.progress != progress ||
      old.flow != flow ||
      old.target != target ||
      old.needleActive != needleActive ||
      old.track != track ||
      old.progressColor != progressColor ||
      old.needle != needle;
}

// The setup steps below the ring: done with its weight, the current one in the
// accent, the coming one dim. A failed tare takes the row over.
class _PrepRow extends StatelessWidget {
  const _PrepRow({required this.brew});

  final PourOverBrewService brew;

  static double _one(double g) => (g * 10).roundToDouble() / 10;

  @override
  Widget build(BuildContext context) {
    final prep = brew.prep;
    final colors = context.colors;
    if (prep.status == SetupStatus.tareFailed) {
      return Center(
        child: Text(
          'Tare not confirmed · tap Tare',
          style: TextStyle(color: colors.danger, fontSize: 13),
        ),
      );
    }
    final brewer = brew.detectedBrewer?.displayName ?? 'Brewer';
    Widget cell(SetupStep step, String name, double? grams) {
      final done = prep.step.index > step.index;
      final current = prep.step == step;
      final color = current
          ? colors.accent
          : done
          ? colors.textSecondary
          : colors.textTertiary;
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (done) ...[
                  Icon(Icons.check, size: 13, color: colors.accent),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 13, height: 1.2),
                  ),
                ),
              ],
            ),
            Text(
              grams == null ? '–' : '${formatGrams(_one(grams))} g',
              maxLines: 1,
              style: TextStyle(color: color, fontSize: 13, height: 1.2),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        cell(SetupStep.server, 'Server', prep.serverG),
        cell(SetupStep.brewer, brewer, prep.brewerG),
        cell(SetupStep.coffee, 'Coffee', prep.liveCoffeeG ?? prep.coffeeG),
      ],
    );
  }
}
