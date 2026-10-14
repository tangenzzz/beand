import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/brew_plan.dart';
import '../../../scale/brew_scale.dart';
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
// every scale packet. Name and progress of the pour are on a line below
// the ring.
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

    final String label;
    final String? stepLine;
    if (!scale.isConnected) {
      label = 'NO SCALE';
      stepLine = null;
    } else if (!running) {
      label = 'READY';
      stepLine = step == null
          ? null
          : '${step.label} · ${formatGrams(step.waterG)} g';
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
          stepLine = 'next in ${formatClock(brew.waitLeftSeconds)}';
        case BrewState.drawdown:
          label = 'DRAWDOWN';
          stepLine = null;
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
                  child: _FlowValue(
                    flow: brew.flow,
                    active: needleActive,
                    size: _ringSize,
                  ),
                ),
              ),
              const SizedBox(width: SensorStack.ringToValues),
              SensorStack(sensors: values),
            ],
          ),
          // Pour info below the ring instead of inside — inside the ring it
          // was too large.
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                if (stepLine != null)
                  TextSpan(
                    text: '  ·  $stepLine',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // "Third Pour (60% — strength)" → "THIRD POUR"; without the
  // parenthetical, that belongs in the pour list. Long names → "POUR 3".
  static String _short(String label, int index) {
    final base = label.split('(').first.trim();
    return base.length > 18 ? 'POUR ${index + 1}' : base.toUpperCase();
  }
}

// Inside the ring only the flow below the needle axis.
class _FlowValue extends StatelessWidget {
  const _FlowValue({
    required this.flow,
    required this.active,
    required this.size,
  });

  final double flow;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: size * 0.58,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: flow.toStringAsFixed(1),
                  style: TextStyle(
                    color: active
                        ? context.colors.textPrimary
                        : context.colors.textTertiary,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: ' g/s',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter({
    required this.progress,
    required this.flow,
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
      _start + _sweep * (gPerS / flowDialMax).clamp(0.0, 1.0);

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
      (0, idealPourFlow - flowYellowBand, red),
      (idealPourFlow - flowYellowBand, idealPourFlow - flowGreenBand, yellow),
      (idealPourFlow - flowGreenBand, idealPourFlow + flowGreenBand, green),
      (idealPourFlow + flowGreenBand, idealPourFlow + flowYellowBand, yellow),
      (idealPourFlow + flowYellowBand, flowDialMax, red),
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
      old.needleActive != needleActive ||
      old.track != track ||
      old.progressColor != progressColor ||
      old.needle != needle;
}
