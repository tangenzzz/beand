import 'dart:math' as math;

import 'brew_plan.dart';
import 'brew_recipe.dart';
import 'profile_detail.dart';

// What a profile aims for over time, whatever it comes from: every profile
// view draws this one shape. A new machine only has to supply it (machines
// with stages get it through ProfileDetail).
//
// Espresso profiles often don't say how long a stage takes (it may run until
// a weight is reached). Such a stretch gets [unknownStageSeconds] and counts
// as estimated: the chart draws it dashed, the value is right, the length
// isn't known.

const unknownStageSeconds = 10.0;

class SetpointPoint {
  const SetpointPoint(this.seconds, this.value);

  final double seconds;
  final double value;
}

/// A connected piece of one quantity ('pressure', 'flow', 'power', 'weight').
class SetpointSegment {
  const SetpointSegment({
    required this.type,
    required this.points,
    this.estimated = false,
  });

  final String type;
  final List<SetpointPoint> points;
  final bool estimated;
}

class SetpointStage {
  const SetpointStage({
    required this.name,
    required this.startS,
    required this.endS,
  });

  final String name;
  final double startS;
  final double endS;
}

class SetpointCurve {
  const SetpointCurve({
    required this.stages,
    required this.segments,
    this.temperature,
    this.finalWeight,
    this.flowUnit = 'ml/s',
    this.clockLabels = false,
  });

  final List<SetpointStage> stages;
  final List<SetpointSegment> segments;
  final double? temperature;
  final double? finalWeight;
  final String flowUnit;

  /// Time axis as 1:30 instead of 90s, for long brews.
  final bool clockLabels;

  bool get isEmpty => segments.isEmpty;
  double get durationS => stages.isEmpty ? 0 : stages.last.endS;
  bool get hasEstimate => segments.any((s) => s.estimated);

  factory SetpointCurve.fromProfile(ProfileDetail detail) {
    final stages = <SetpointStage>[];
    final segments = <SetpointSegment>[];
    var start = 0.0;
    for (final stage in detail.stages) {
      final timing = _stageTiming(stage, start);
      final end = start + timing.duration;
      stages.add(
        SetpointStage(
          name: stage.name.isEmpty ? 'Stage ${stage.number}' : stage.name,
          startS: start,
          endS: end,
        ),
      );
      final pieces = _stagePieces(stage, start, timing);
      for (var i = 0; i < pieces.length; i++) {
        var piece = pieces[i];
        // The same quantity goes on from where it was: a step, not a gap.
        final last = segments.isEmpty ? null : segments.last;
        if (i == 0 && last != null && last.type == piece.type) {
          final tail = last.points.last;
          final head = piece.points.first;
          if (tail.seconds == head.seconds && tail.value != head.value) {
            piece = SetpointSegment(
              type: piece.type,
              estimated: piece.estimated,
              points: [tail, ...piece.points],
            );
          }
        }
        segments.add(piece);
      }
      start = end;
    }
    return SetpointCurve(
      stages: stages,
      segments: segments,
      temperature: detail.temperature > 0 ? detail.temperature : null,
      finalWeight: detail.finalWeight > 0 ? detail.finalWeight : null,
    );
  }

  /// The pours: running water total and the flow each pour aims for.
  factory SetpointCurve.fromRecipe(BrewRecipe recipe) {
    final steps = BrewPlan(recipe).steps;
    final stages = <SetpointStage>[];
    final water = <SetpointPoint>[];
    final flow = <SetpointPoint>[];
    var t = 0.0;
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final pourEnd = t + s.plannedPourSeconds;
      final end = pourEnd + (s.waitSeconds ?? 0);
      stages.add(SetpointStage(name: s.label, startS: t, endS: end));
      water.addAll([
        SetpointPoint(t, s.startTotalG),
        SetpointPoint(pourEnd, s.targetTotalG),
      ]);
      flow.addAll([
        SetpointPoint(t, 0),
        SetpointPoint(t, s.targetFlow),
        SetpointPoint(pourEnd, s.targetFlow),
        SetpointPoint(pourEnd, 0),
      ]);
      if (end > pourEnd) {
        water.add(SetpointPoint(end, s.targetTotalG));
        flow.add(SetpointPoint(end, 0));
      }
      t = end;
    }
    return SetpointCurve(
      stages: stages,
      segments: steps.isEmpty
          ? const []
          : [
              SetpointSegment(type: 'flow', points: flow),
              SetpointSegment(type: 'weight', points: water),
            ],
      temperature: recipe.waterTempC,
      flowUnit: 'g/s',
      clockLabels: true,
    );
  }
}

typedef _Timing = ({double duration, double? timed, bool overTime});

// How long the stage runs and for how much of that the profile vouches
// ([timed]; null = for none of it).
_Timing _stageTiming(ProfileStage stage, double start) {
  double? trigger;
  for (final t in stage.exitTriggers) {
    final v = t.value.value;
    if (t.type != 'time' || v == null) continue;
    // Not relative = counted from the start of the shot.
    final seconds = t.relative ? v : v - start;
    if (seconds > 0) trigger = math.min(trigger ?? seconds, seconds);
  }
  final overTime = stage.over == 'time';
  if (trigger != null) {
    return (duration: trigger, timed: trigger, overTime: overTime);
  }
  final curveEnd = overTime && stage.points.length >= 2
      ? stage.points.last.x
      : null;
  if (curveEnd != null && curveEnd > 0) {
    // After the curve it holds until something else ends the stage.
    final open = stage.exitTriggers.isNotEmpty;
    return (
      duration: open ? math.max(curveEnd, unknownStageSeconds) : curveEnd,
      timed: curveEnd,
      overTime: true,
    );
  }
  return (duration: unknownStageSeconds, timed: null, overTime: overTime);
}

List<SetpointSegment> _stagePieces(
  ProfileStage stage,
  double start,
  _Timing timing,
) {
  final raw = [
    for (final p in stage.points)
      if (p.x != null && p.y != null) (x: p.x!, y: p.y!),
  ];
  if (raw.isEmpty) return const [];
  final duration = timing.duration;
  final timed = timing.timed;

  // Not over time (e.g. over weight): only the shape is known.
  if (!timing.overTime) {
    final first = raw.first.x;
    final span = raw.last.x - first;
    return [
      SetpointSegment(
        type: stage.type,
        estimated: timed == null,
        points: span <= 0
            ? [
                SetpointPoint(start, raw.first.y),
                SetpointPoint(start + duration, raw.last.y),
              ]
            : [
                for (final p in raw)
                  SetpointPoint(start + (p.x - first) / span * duration, p.y),
              ],
      ),
    ];
  }

  final solidEnd = timed ?? 0;
  final stepped = stage.interpolation == 'none';
  final solid = <SetpointPoint>[];
  void add(double x, double y) => solid.add(SetpointPoint(start + x, y));
  if (raw.first.x > 0) add(0, raw.first.y);
  for (var i = 0; i < raw.length; i++) {
    final p = raw[i];
    if (p.x > solidEnd) {
      // The stage ends inside the curve.
      if (i > 0 && solidEnd > raw[i - 1].x) {
        final a = raw[i - 1];
        final y = stepped
            ? a.y
            : a.y + (p.y - a.y) * (solidEnd - a.x) / (p.x - a.x);
        add(solidEnd, y);
      }
      break;
    }
    if (stepped && i > 0) add(p.x, raw[i - 1].y);
    add(p.x, p.y);
  }
  final held = raw.last.y;
  if (timed != null && raw.last.x < solidEnd) add(solidEnd, held);

  final holdStart = start + solidEnd;
  final holdEnd = start + duration;
  final open = holdEnd > holdStart
      ? SetpointSegment(
          type: stage.type,
          estimated: true,
          points: [
            SetpointPoint(
              holdStart,
              solid.isEmpty ? raw.first.y : solid.last.value,
            ),
            SetpointPoint(
              holdEnd,
              solid.isEmpty ? raw.first.y : solid.last.value,
            ),
          ],
        )
      : null;
  return [
    if (solid.length >= 2) SetpointSegment(type: stage.type, points: solid),
    ?open,
  ];
}
