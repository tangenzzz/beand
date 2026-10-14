import 'dart:convert';

import '../database/database.dart';
import '../machines/gaggimate/gaggimate_profile_detail.dart';
import 'profile_detail.dart';
import 'shot_phases.dart';

// Fixed findings for a shot, without AI: how did each stage end, does it
// really control what its type says, was there a stall or channeling, how far
// was it off target, and how close to the target weight did the shot end.
//
// The findings are shown in the shot detail even without AI, and are given
// to the AI analysis as fixed facts up front — a model should not have to
// guess from the curve whether an ending was planned.
//
// Modeled on the shot evaluation of MeticAI (github.com/hessius/MeticAI,
// packages/core/src/logic/shotFacts.ts + shotAnalysis.ts). Rules and
// thresholds are adopted, not code or text — the repo states MIT in its
// README but has no license file. Our own deviations are explained below
// where they apply.

/// From this target (ml/s) on, the limit governs a flow stage with a
/// pressure limit: it is really a pressure stage. (MeticAI)
const effectiveFlowTargetMin = 6.0;

/// Up to this flow limit (ml/s) a pressure stage cannot build pressure at
/// all: it is really a flow stage. (MeticAI)
const effectiveFlowLimitMax = 3.0;

/// Less weight gain (g) in a stage that ended on time while another target
/// was still open is a stall. (MeticAI)
const stallMinWeightGain = 0.5;

/// Pressure drop (bar) with a simultaneous flow rise (ml/s) within a stage:
/// channeling. (MeticAI)
const channelingPressureDrop = 1.5;
const channelingFlowRise = 1.5;

/// Shorter stages are not checked for channeling or curve tracking.
/// Our own addition: ramps of 0.3 s consist of two or three data points,
/// whose start still belongs to the previous stage.
const minStageSecondsForCurveChecks = 2.0;

/// A mean this far off target counts as "off the curve". (MeticAI)
const adherenceDelta = 0.5;

/// Ramp-up at the start of each stage that does not count against the
/// target: the machine needs a second or two to get from 2 to 9 bar.
/// Our own addition — without it every lever profile showed "Pressure Up:
/// 8.3 instead of 9" on real shots. At most a third of the stage.
const adherenceSettleSeconds = 2.0;

/// A weight exit at 90 % of the target weight or more counts as the final
/// exit. (MeticAI)
const finalYieldFraction = 0.9;

/// A pressure stage has built its pressure once it reaches 80 % of it.
/// (MeticAI)
const pressureOnTargetFraction = 0.8;

/// Within 5 % of the target weight the shot is "on target". (MeticAI)
const weightOnTargetFraction = 0.05;

/// If a weight target is reached this many seconds before the stage ends,
/// it did not end the stage — the machine skipped it (e.g. with no scale
/// connected). Our own addition, found on GaggiMate shots with a 36 g target
/// that ended on time at 64–81 g.
const ignoredWeightSeconds = 1.5;

/// In the first seconds the flow jumps while filling; for mean and maximum
/// it only counts afterwards. (MeticAI)
const flowIgnoreSeconds = 3.5;

enum ExitKind {
  /// The stage achieved what it was built for.
  planned,

  /// An emergency brake triggered instead of the actual target.
  backstop,

  /// Cannot be determined from the data.
  unclear,
}

enum FindingSeverity { problem, note, ok }

class ShotFinding {
  const ShotFinding(this.severity, this.text);

  final FindingSeverity severity;
  final String text;
}

/// What was measured in a stage.
class StageStats {
  StageStats(this.name, this.readings) {
    final rs = readings;
    double s(int ms) => ms / 1000;
    startS = s(rs.first.timeMs);
    endS = s(rs.last.timeMs);
    double v(double? x) => x ?? 0;
    final p = [for (final r in rs) v(r.pressure)];
    final w = [for (final r in rs) v(r.weight)];
    final f = [for (final r in rs) v(r.flow)];
    final late = [
      for (final r in rs)
        if (s(r.timeMs) >= flowIgnoreSeconds) v(r.flow),
    ];
    final fSrc = late.isEmpty ? f : late;
    startWeight = w.first;
    endWeight = w.last;
    startPressure = p.first;
    endPressure = p.last;
    avgPressure = p.reduce((a, b) => a + b) / p.length;
    maxPressure = p.reduce((a, b) => a > b ? a : b);
    startFlow = f.first;
    endFlow = f.last;
    avgFlow = fSrc.reduce((a, b) => a + b) / fSrc.length;
    maxFlow = fSrc.reduce((a, b) => a > b ? a : b);
  }

  final String name;
  final List<ShotReading> readings;
  late final double startS, endS;
  late final double startWeight, endWeight;
  late final double startPressure, endPressure, avgPressure, maxPressure;
  late final double startFlow, endFlow, avgFlow, maxFlow;

  // Values at the transition: the machine switches on the tick in which the
  // exit condition is met — the data point that meets it already carries the
  // name of the NEXT stage. Without these values a stage that ends exactly
  // at its target would look like it failed. (MeticAI)
  double? boundaryS, boundaryWeight, boundaryPressure, boundaryFlow;

  double get duration => endS - startS;
  double get weightGain => endWeight - startWeight;
}

/// The findings for one stage.
class StageFact {
  const StageFact({
    required this.name,
    required this.reached,
    this.declaredMode,
    this.effectiveMode,
    this.exit,
    this.exitLabel,
    this.firedTrigger,
    this.stats,
    this.stalled = false,
    this.channeling = false,
    this.pressureDrop = 0,
    this.flowRise = 0,
    this.target,
    this.measured,
    this.limitHit,
    this.profileStage,
    this.firedType,
    this.firedValue,
    this.isTerminal = false,
    this.ignoredWeight,
    this.machineExit,
  });

  final String name;
  final bool reached;

  /// What the machine itself says about the end; null if it says nothing.
  final MachineStageExit? machineExit;

  /// A weight target that was reached but did not end the stage:
  /// (threshold, second in the shot at which it was reached).
  final (double, double)? ignoredWeight;

  /// The stage according to the profile — carries the target for [goalText].
  final ProfileStage? profileStage;

  /// Which exit triggered (type and threshold), null = none.
  final String? firedType;
  final double? firedValue;

  /// The last stage that ran in the shot.
  final bool isTerminal;

  /// pressure | flow | power — according to the profile.
  final String? declaredMode;

  /// What the stage actually controls (see [effectiveFlowTargetMin]).
  final String? effectiveMode;

  final ExitKind? exit;
  final String? exitLabel;

  /// "weight ≥ 6 g" — the condition that triggered.
  final String? firedTrigger;

  final StageStats? stats;
  final bool stalled;
  final bool channeling;
  final double pressureDrop;
  final double flowRise;

  /// Mean target and measured mean of the controlled quantity.
  final double? target;
  final double? measured;

  /// "pressure capped at 6 bar" — when a limit was reached.
  final String? limitHit;

  double? get delta =>
      target == null || measured == null ? null : measured! - target!;

  bool get offTarget =>
      delta != null &&
      delta!.abs() >= adherenceDelta &&
      (stats?.duration ?? 0) >= minStageSecondsForCurveChecks;
}

class ShotFacts {
  const ShotFacts({
    required this.stages,
    required this.hasProfile,
    this.weightActual,
    this.weightTarget,
  });

  final List<StageFact> stages;

  /// Without a profile there is no statement about exits and targets — only
  /// what the curve itself shows (channeling).
  final bool hasProfile;

  final double? weightActual;
  final double? weightTarget;

  double? get deviationPct =>
      weightActual == null || weightTarget == null || weightTarget! <= 0
      ? null
      : (weightActual! - weightTarget!) / weightTarget! * 100;

  bool? get weightOnTarget => deviationPct == null
      ? null
      : deviationPct!.abs() < weightOnTargetFraction * 100;

  bool get isEmpty => stages.isEmpty && weightActual == null;

  /// What the shot detail shows: problems first, then notes. If there is no
  /// problem, a line says so explicitly — otherwise one could not tell
  /// whether anything was checked.
  List<ShotFinding> get findings {
    final problems = <ShotFinding>[];
    final notes = <ShotFinding>[];
    for (final s in stages) {
      if (!s.reached) continue;
      final st = s.stats!;
      if (s.stalled) {
        problems.add(
          ShotFinding(
            FindingSeverity.problem,
            'Stall in ${s.name}: only ${_n(st.weightGain)} g in '
            '${_n(st.duration)} s before its time ran out',
          ),
        );
      }
      if (s.channeling) {
        problems.add(
          ShotFinding(
            FindingSeverity.problem,
            'Channeling in ${s.name}: pressure fell ${_n(s.pressureDrop)} bar '
            'while flow rose ${_n(s.flowRise)} ml/s',
          ),
        );
      }
      if (s.exit == ExitKind.backstop) {
        problems.add(
          ShotFinding(FindingSeverity.problem, '${s.name}: ${s.exitLabel}'),
        );
      }
      // If a limit kicked in, that explains the deviation — the profile is
      // built that way (e.g. a fill phase at the flow limit). This then only
      // goes into the fact sheet for the AI, not as a note.
      if (s.offTarget && s.limitHit == null) {
        final pressure = s.declaredMode == 'pressure';
        notes.add(
          ShotFinding(
            FindingSeverity.note,
            '${s.name}: ${pressure ? 'pressure' : 'flow'} '
            '${_n(s.measured!)} ${pressure ? 'bar' : 'ml/s'} instead of '
            '${_n(s.target!)}',
          ),
        );
      }
    }
    for (final s in stages) {
      if (s.ignoredWeight case (final w, final at)?) {
        notes.add(
          ShotFinding(
            FindingSeverity.note,
            '${s.name}: ${_n(w)} g was reached at ${_n(at)} s, but the stage '
            'ran on to ${_n(s.stats!.endS)} s — '
            '${s.machineExit?.scaleConnected == false ? 'no scale was connected, the weight was only estimated' : 'the machine did not stop on weight (scale connected?)'}',
          ),
        );
      }
    }
    final dev = deviationPct;
    if (dev != null && weightOnTarget == false) {
      notes.add(
        ShotFinding(
          FindingSeverity.note,
          'Stopped at ${_n(weightActual!)} g, ${_n(dev.abs())} % '
          '${dev < 0 ? 'under' : 'over'} the ${_n(weightTarget!)} g target',
        ),
      );
    }
    final missed = [
      for (final s in stages)
        if (!s.reached) s.name,
    ];
    if (missed.isNotEmpty && weightOnTarget != true) {
      notes.add(
        ShotFinding(
          FindingSeverity.note,
          'Never reached: ${missed.join(', ')}',
        ),
      );
    }
    return [
      ...problems,
      if (problems.isEmpty)
        ShotFinding(
          FindingSeverity.ok,
          !hasProfile
              ? 'No problems seen in the curve'
              : weightOnTarget == true
              ? 'Ran as planned · ${_n(weightActual!)} g of ${_n(weightTarget!)} g'
              : 'No problems found',
        ),
      ...notes,
    ];
  }

  /// The same as a fact sheet for the AI.
  String factSheet() {
    final b = StringBuffer();
    if (weightActual != null) {
      b.write('- Final weight ${_n(weightActual!)} g');
      if (weightTarget != null) {
        b.write(
          ' (target ${_n(weightTarget!)} g, '
          '${deviationPct! >= 0 ? '+' : ''}${_n(deviationPct!)} %)',
        );
      }
      b.writeln();
    }
    if (!hasProfile) {
      b.writeln('- No profile available: stage exits could not be checked.');
    }
    for (final s in stages) {
      if (!s.reached) {
        b.writeln('- ${s.name}: not reached in this shot');
        continue;
      }
      final mode = s.effectiveMode == null
          ? ''
          : s.effectiveMode != s.declaredMode
          ? ' [${s.effectiveMode}-governed; declared ${s.declaredMode}, '
                'its limit decides]'
          : ' [${s.effectiveMode}]';
      final parts = [
        if (s.exit != null)
          'ended: ${switch (s.exit!) {
                ExitKind.planned => 'PLANNED',
                ExitKind.backstop => 'BACKSTOP',
                ExitKind.unclear => 'UNCLEAR',
              }} — ${s.exitLabel}'
              '${s.firedTrigger == null ? '' : ' (${s.firedTrigger})'}',
        if (s.stalled) 'STALL (${_n(s.stats!.weightGain)} g gained)',
        if (s.ignoredWeight case (final w, final at)?)
          'WEIGHT TARGET IGNORED: ${_n(w)} g was reached at ${_n(at)} s but '
              'the stage ran on — the machine did not stop on weight',
        if (s.channeling)
          'CHANNELING (pressure −${_n(s.pressureDrop)} bar, '
              'flow +${_n(s.flowRise)} ml/s beyond what the profile intends)',
        if (s.offTarget)
          'off target: ${_n(s.measured!)} vs ${_n(s.target!)}'
              '${s.limitHit == null ? '' : ', ${s.limitHit}'}',
        if (!s.offTarget && s.limitHit != null) s.limitHit!,
      ];
      b.writeln(
        '- ${s.name}$mode: '
        '${parts.isEmpty ? 'no remarks' : parts.join('; ')}',
      );
    }
    return b.toString();
  }
}

/// How a stage ended according to the machine (GaggiMate writes this into
/// its recording, see GaggiMatePhaseExit). Stored in shots.stageExits.
class MachineStageExit {
  const MachineStageExit({
    required this.stage,
    this.reason,
    this.pumped,
    this.scaleConnected,
  });

  final String stage;

  /// weight | pressure | flow | pumped | time | safety | aborted
  final String? reason;
  final double? pumped;
  final bool? scaleConnected;
}

List<MachineStageExit> parseStageExits(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final list = jsonDecode(json);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map && e['stage'] is String)
          MachineStageExit(
            stage: e['stage'] as String,
            reason: e['reason'] as String?,
            pumped: (e['pumped'] as num?)?.toDouble(),
            scaleConnected: e['scale'] as bool?,
          ),
    ];
  } catch (_) {
    return const [];
  }
}

/// Target and result of a stage in short form — for the line below the
/// stage bar in the shot detail: per stage, what it intended and what came
/// of it, not just the target weight.
extension StageFactText on StageFact {
  /// "Flow 1 → 1.5 ml/s · max 0.5 bar · until 6 g". Null without a profile.
  String? get goalText {
    final st = profileStage;
    if (st == null) return null;
    final type = st.type;
    final unit = switch (type) {
      'pressure' => 'bar',
      'flow' => 'ml/s',
      'power' => '%',
      _ => '',
    };
    final ys = [for (final p in st.points) ?p.y];
    final label = type.isEmpty
        ? 'Stage'
        : '${type[0].toUpperCase()}${type.substring(1)}';
    final target = ys.isEmpty
        ? label
        : st.isConstant || ys.length == 1
        ? '$label ${_n(ys.first)} $unit'
        : '$label ${_n(ys.first)} → ${_n(ys.last)} $unit';
    final limits = [
      for (final l in st.limits)
        if (l.value.value != null)
          'max ${_n(l.value.value!)} ${_unit(l.type)}'.trim(),
    ];
    final exits = [
      for (final t in st.exitTriggers)
        if (t.value.value != null)
          switch (t.type) {
            'time' =>
              t.relative
                  ? '${_n(t.value.value!)} s'
                  : 'at ${_n(t.value.value!)} s',
            _ =>
              '${t.comparison.startsWith('<') ? '≤ ' : ''}'
                      '${_n(t.value.value!)} ${_unit(t.type)}'
                  .trim(),
          },
    ];
    final until = exits.isNotEmpty
        ? 'until ${exits.join(' or ')}'
        : isTerminal
        ? 'until the target weight'
        : null;
    return [target.trim(), ...limits, ?until].join(' · ');
  }

  /// How well did it go? Problem, note or OK.
  FindingSeverity get severity {
    if (stalled || channeling || exit == ExitKind.backstop) {
      return FindingSeverity.problem;
    }
    if (exit == ExitKind.unclear ||
        ignoredWeight != null ||
        (offTarget && limitHit == null)) {
      return FindingSeverity.note;
    }
    return FindingSeverity.ok;
  }

  /// "Reached 6 g in 5.8 s · Ø 1.2 ml/s · max 0.4 bar" — how it ended and
  /// what was measured. [facts] provides the target weight for the last
  /// stage.
  String resultText(ShotFacts facts) {
    final s = stats;
    if (!reached || s == null) return 'Not reached in this shot';
    final v = firedValue;
    final ending = switch (firedType) {
      'weight' when isTerminal && facts.weightTarget != null =>
        'Target weight ${_n(facts.weightActual ?? s.endWeight)} / '
            '${_n(facts.weightTarget!)} g',
      'weight' => 'Reached ${_n(v!)} g in ${_n(s.duration)} s',
      'time' => 'Ran ${_n(s.duration)} s',
      'pumped' =>
        machineExit?.pumped == null
            ? 'Pumped its water target in ${_n(s.duration)} s'
            : 'Pumped ${_n(machineExit!.pumped!)} ml in ${_n(s.duration)} s',
      null when machineExit?.reason == 'aborted' =>
        'Stopped by hand after ${_n(s.duration)} s',
      'pressure' => 'Reached ${_n(v!)} bar after ${_n(s.duration)} s',
      'flow' => 'Reached ${_n(v!)} ml/s after ${_n(s.duration)} s',
      null when isTerminal && facts.weightActual != null =>
        facts.weightTarget == null
            ? 'Ended at ${_n(facts.weightActual!)} g'
            : 'Ended at ${_n(facts.weightActual!)} / '
                  '${_n(facts.weightTarget!)} g',
      _ => '${_n(s.duration)} s',
    };
    final pressure = profileStage?.type == 'pressure';
    final measured = pressure
        ? 'Ø ${_n(s.avgPressure)} bar · max ${_n(s.maxFlow)} ml/s'
        : 'Ø ${_n(s.avgFlow)} ml/s · max ${_n(s.maxPressure)} bar';
    final remarks = [
      if (offTarget) 'target ${_n(target!)}',
      ?limitHit,
      if (ignoredWeight case (final w, final at)?)
        '${_n(w)} g already at ${_n(at)} s — did not stop',
      if (stalled) 'stall',
      if (channeling)
        'channeling (−${_n(pressureDrop)} bar, +${_n(flowRise)} ml/s)',
      if (exit == ExitKind.backstop) exitLabel!,
      if (exit == ExitKind.unclear && firedType == null && !isTerminal)
        exitLabel!,
    ];
    return [ending, measured, ...remarks].join(' · ');
  }
}

/// Reads a stored profile of either machine into the same shape: a
/// GaggiMate profile (`phases` instead of `stages`) goes through the same
/// translator as the profile view. Null if no stages come out.
ProfileDetail? parseShotProfile(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final detail = map['stages'] == null && map['phases'] is List
        ? gaggiMateProfileDetail(map)
        : ProfileDetail.fromJson(map);
    return detail.stages.isEmpty ? null : detail;
  } catch (_) {
    return null;
  }
}

ShotFacts computeShotFacts({
  required List<ShotReading> readings,
  ProfileDetail? profile,
  double? finalWeight,
  List<MachineStageExit> machineExits = const [],
}) {
  MachineStageExit? machineExitFor(String name) {
    final key = name.trim().toLowerCase();
    for (final e in machineExits) {
      if (e.stage.trim().toLowerCase() == key && e.reason != null) return e;
    }
    return null;
  }

  // Data points by stage, in order; the retraction does not count.
  final runs = <String, List<ShotReading>>{};
  for (final r in readings) {
    final stage = r.stage?.trim();
    if (stage == null || stage.isEmpty || stage == retractionStage) continue;
    runs.putIfAbsent(stage, () => []).add(r);
  }
  final stats = [for (final e in runs.entries) StageStats(e.key, e.value)];
  for (var i = 0; i < stats.length - 1; i++) {
    final next = stats[i + 1];
    stats[i]
      ..boundaryS = next.startS
      ..boundaryWeight = next.startWeight
      ..boundaryPressure = next.startPressure
      ..boundaryFlow = next.startFlow;
  }
  StageStats? statsFor(String name) {
    final key = name.trim().toLowerCase();
    for (final s in stats) {
      if (s.name.toLowerCase() == key) return s;
    }
    return null;
  }

  final actual =
      finalWeight ?? (readings.isEmpty ? null : readings.last.weight);
  final target = profile != null && profile.finalWeight > 0
      ? profile.finalWeight
      : null;
  final weightOnTarget = actual == null || target == null
      ? null
      : actual >= target * (1 - weightOnTargetFraction);

  if (profile == null) {
    return ShotFacts(
      hasProfile: false,
      weightActual: actual,
      stages: [for (final s in stats) _curveOnlyFact(s)],
    );
  }

  final executed = [
    for (final st in profile.stages)
      if (statsFor(st.name) != null) st,
  ];
  final terminal = executed.isEmpty ? null : executed.last;

  return ShotFacts(
    hasProfile: true,
    weightActual: actual,
    weightTarget: target,
    stages: [
      for (final st in profile.stages)
        if (statsFor(st.name) case final s?)
          _stageFact(
            st,
            s,
            isTerminal: identical(st, terminal),
            globalTarget: target,
            weightOnTarget: weightOnTarget,
            machineExit: machineExitFor(st.name),
          )
        else
          StageFact(name: st.name, reached: false),
    ],
  );
}

StageFact _curveOnlyFact(StageStats s) {
  final (channeling, drop, rise) = _channeling(s, null);
  return StageFact(
    name: s.name,
    reached: true,
    stats: s,
    channeling: channeling,
    pressureDrop: drop,
    flowRise: rise,
  );
}

StageFact _stageFact(
  ProfileStage st,
  StageStats s, {
  required bool isTerminal,
  required double? globalTarget,
  required bool? weightOnTarget,
  MachineStageExit? machineExit,
}) {
  final declared = st.type;
  final ys = [for (final p in st.points) ?p.y];
  final hasTarget =
      (declared == 'pressure' || declared == 'flow') && ys.isNotEmpty;
  final maxTarget = hasTarget ? ys.reduce((a, b) => a > b ? a : b) : null;
  final pointMean = hasTarget ? ys.reduce((a, b) => a + b) / ys.length : null;

  double? limit(String type) {
    for (final l in st.limits) {
      if (l.type == type && l.value.value != null) return l.value.value;
    }
    return null;
  }

  // What the stage really controls. (MeticAI)
  var effective = declared;
  if (declared == 'flow' &&
      maxTarget != null &&
      maxTarget >= effectiveFlowTargetMin &&
      limit('pressure') != null) {
    effective = 'pressure';
  } else if (declared == 'pressure' &&
      (limit('flow') ?? double.infinity) <= effectiveFlowLimitMax) {
    effective = 'flow';
  }

  // Which exit triggered? The first one whose condition is met — when in
  // doubt using the value at the transition. Tolerances as in MeticAI. A
  // weight target that was reached long before the end does not count.
  StageTrigger? fired;
  double? firedValue;
  (double, double)? ignoredWeight;
  for (final t in st.exitTriggers) {
    final v = t.value.value;
    if (v == null) continue;
    final rising = t.comparison == '>=' || t.comparison == '>';
    final (double? now, double? boundary) = switch (t.type) {
      'time' =>
        t.relative
            ? (s.duration, s.boundaryS == null ? null : s.boundaryS! - s.startS)
            : (s.endS, s.boundaryS),
      'weight' => (s.endWeight, s.boundaryWeight),
      'pressure' => (
        rising ? s.maxPressure : s.endPressure,
        s.boundaryPressure,
      ),
      'flow' => (rising ? s.maxFlow : s.endFlow, s.boundaryFlow),
      _ => (null, null),
    };
    final tol = t.type == 'time' || t.type == 'weight' ? 0.5 : 0.2;
    bool hit(double? a) =>
        a != null &&
        switch (t.comparison) {
          '>=' => a >= v - tol,
          '>' => a > v,
          '<=' => a <= v + tol,
          '<' => a < v,
          _ => false,
        };
    if (hit(now) || hit(boundary)) {
      if (t.type == 'weight' && t.comparison.startsWith('>')) {
        final at = _firstWeightAt(s, v - tol);
        if (at != null && s.endS - at > ignoredWeightSeconds) {
          ignoredWeight ??= (v, at);
          continue;
        }
      }
      // Look at all conditions, do not stop at the first hit: a skipped
      // weight target often comes AFTER the time.
      if (fired == null) {
        fired = t;
        firedValue = v;
      }
    }
  }

  // If the machine itself says how the stage ended, that wins — we only
  // guess where it is silent (Meticulous, older GaggiMate firmware).
  final told = machineExit?.reason;
  if (told != null && told != 'safety' && told != 'aborted') {
    fired = null;
    firedValue = null;
    for (final t in st.exitTriggers) {
      if (t.type == told && t.value.value != null) {
        fired = t;
        firedValue = t.value.value;
        break;
      }
    }
  }

  // Did a pressure-controlled stage build its pressure? (MeticAI)
  bool? pressureOnTarget;
  if (effective == 'pressure') {
    final want =
        limit('pressure') ?? (declared == 'pressure' ? pointMean : null);
    if (want != null && want > 0) {
      pressureOnTarget = s.maxPressure >= pressureOnTargetFraction * want;
    }
  }

  final total = st.exitTriggers.length;
  final (ExitKind exit, String label) = switch (told) {
    'safety' => (ExitKind.backstop, 'the brew safety timeout ended it'),
    'aborted' => (ExitKind.unclear, 'stopped by hand'),
    _ => _classifyExit(
      effective,
      told ?? fired?.type,
      total,
      firedValue: firedValue,
      globalTarget: globalTarget,
      pressureOnTarget: pressureOnTarget,
      isTerminal: isTerminal,
      weightOnTarget: weightOnTarget,
      maxPressure: s.maxPressure,
      wantedPressure: limit('pressure') ?? pointMean,
    ),
  };

  // A pause (target 0, e.g. a GaggiMate bloom) is not supposed to deliver
  // anything — that is not a stall. Our own addition.
  final isPause = ys.isNotEmpty && ys.every((y) => y <= 0);
  final stalled =
      fired?.type == 'time' &&
      total > 1 &&
      !isPause &&
      s.weightGain < stallMinWeightGain;

  final (channeling, drop, rise) = _channeling(s, st);

  // Measured vs. target — for the quantity the type prescribes, point by
  // point against the target AT THAT TIME. Our own deviation: MeticAI uses
  // the mean of the profile points; for a ramp 9 → 3 bar over 55 s that ends
  // on weight after 8 s, the target would then be 6 instead of ~8 bar.
  final (meanTarget, measured) = hasTarget
      ? _alignedAdherence(st, s)
      : (null, null);

  // Was a limit reached? Often explains why the target was missed.
  String? limitHit;
  for (final l in st.limits) {
    final lv = l.value.value;
    if (lv == null) continue;
    final reachedAt = switch (l.type) {
      'pressure' => s.maxPressure,
      'flow' => s.maxFlow,
      _ => null,
    };
    // Tolerance 0.2 as in MeticAI, for small limits at most 10 % — otherwise
    // 0.3 bar would already count as "at the 0.5 bar limit".
    final tol = lv * 0.1 < 0.2 ? lv * 0.1 : 0.2;
    if (reachedAt != null && reachedAt >= lv - tol) {
      limitHit =
          'held at the ${_n(lv)} ${l.type == 'pressure' ? 'bar' : 'ml/s'} cap';
      break;
    }
  }

  return StageFact(
    name: st.name,
    reached: true,
    declaredMode: declared,
    effectiveMode: effective,
    exit: exit,
    exitLabel: label,
    firedTrigger: fired == null
        ? null
        : '${fired.type} ${fired.comparison.replaceAll('>=', '≥').replaceAll('<=', '≤')} '
                  '${_n(firedValue!)} ${_unit(fired.type)}'
              .trim(),
    stats: s,
    stalled: stalled,
    channeling: channeling,
    pressureDrop: drop,
    flowRise: rise,
    target: meanTarget,
    measured: measured,
    limitHit: limitHit,
    profileStage: st,
    firedType: told == 'safety' || told == 'aborted'
        ? null
        : (told ?? fired?.type),
    firedValue: firedValue,
    isTerminal: isTerminal,
    ignoredWeight: ignoredWeight,
    machineExit: machineExit,
  );
}

/// Second in the shot at which the weight in this stage first reached
/// [atLeast]; null if never.
double? _firstWeightAt(StageStats s, double atLeast) {
  for (final r in s.readings) {
    if ((r.weight ?? 0) >= atLeast) return r.timeMs / 1000;
  }
  return null;
}

(ExitKind, String) _classifyExit(
  String mode,
  String? trigger,
  int total, {
  double? firedValue,
  double? globalTarget,
  bool? pressureOnTarget,
  required bool isTerminal,
  bool? weightOnTarget,
  double? maxPressure,
  double? wantedPressure,
}) {
  if (trigger == null) {
    // The last stage also ends without its own exit as soon as the shot
    // reaches its target weight.
    if (isTerminal && weightOnTarget == true) {
      return (ExitKind.planned, 'reached the target weight');
    }
    if (total == 0) {
      return isTerminal
          ? (
              ExitKind.unclear,
              'stopped before the target weight (stopped by hand?)',
            )
          : (ExitKind.planned, 'ran its planned course');
    }
    return (
      ExitKind.unclear,
      'none of the exit conditions the app can check was met',
    );
  }
  switch (trigger) {
    case 'weight':
      final nearFinal =
          globalTarget != null &&
          globalTarget > 0 &&
          firedValue != null &&
          firedValue >= globalTarget * finalYieldFraction;
      if (nearFinal && pressureOnTarget == false) {
        return (
          ExitKind.backstop,
          'reached the target weight without building its pressure '
              '(max ${_n(maxPressure ?? 0)} of ${_n(wantedPressure ?? 0)} bar) '
              '— the puck gave way',
        );
      }
      return (
        ExitKind.planned,
        nearFinal
            ? 'reached the target weight'
            : 'reached its weight milestone',
      );
    case 'time':
      return (ExitKind.planned, 'ran its planned time');
    case 'pumped':
      return (ExitKind.planned, 'pumped its planned amount of water');
    case 'pressure':
      if (mode == 'flow' || mode == 'power') {
        return (ExitKind.planned, 'built up the puck resistance it waited for');
      }
      return (ExitKind.planned, 'reached its pressure');
    case 'flow':
      if (mode == 'pressure' && total > 1) {
        return (
          ExitKind.backstop,
          'its flow backstop fired — the puck channeled or choked',
        );
      }
      return (ExitKind.planned, 'reached its flow');
  }
  return (ExitKind.unclear, 'ended on $trigger');
}

/// Mean target and mean measured value over the same data points, without
/// the ramp-up. Only for stages over time (or with a constant target) — a
/// curve over weight cannot be aligned this way.
(double?, double?) _alignedAdherence(ProfileStage st, StageStats s) {
  final pts = [
    for (final p in st.points)
      if (p.x != null && p.y != null) (x: p.x!, y: p.y!),
  ]..sort((a, b) => a.x.compareTo(b.x));
  if (pts.isEmpty) return (null, null);
  if (!st.isConstant && st.over != 'time') return (null, null);

  double targetAt(double t) {
    if (t <= pts.first.x) return pts.first.y;
    for (var i = 1; i < pts.length; i++) {
      if (t <= pts[i].x) {
        final a = pts[i - 1], b = pts[i];
        final span = b.x - a.x;
        return span <= 0 ? b.y : a.y + (b.y - a.y) * (t - a.x) / span;
      }
    }
    return pts.last.y;
  }

  final settle = s.duration / 3 < adherenceSettleSeconds
      ? s.duration / 3
      : adherenceSettleSeconds;
  var sumT = 0.0, sumM = 0.0, n = 0;
  for (final r in s.readings) {
    final rel = r.timeMs / 1000 - s.startS;
    if (rel < settle) continue;
    final m = st.type == 'pressure' ? r.pressure : r.flow;
    if (m == null) continue;
    sumT += targetAt(rel);
    sumM += m;
    n++;
  }
  if (n == 0) return (null, null);
  return (sumT / n, sumM / n);
}

/// Channeling: pressure falls while flow rises (MeticAI) — but only beyond
/// what the profile itself prescribes. Our own deviation: in a lever profile
/// the pressure drops on purpose (9 → 6 bar) and the flow rises by itself;
/// without the deduction every shot would show "Channeling". Short stages
/// are not checked.
(bool, double, double) _channeling(StageStats s, ProfileStage? st) {
  var intendedDrop = 0.0;
  var intendedRise = 0.0;
  if (st != null && st.startValue != null && st.endValue != null) {
    if (st.type == 'pressure') {
      intendedDrop = (st.startValue! - st.endValue!).clamp(0, double.infinity);
    } else if (st.type == 'flow') {
      intendedRise = (st.endValue! - st.startValue!).clamp(0, double.infinity);
    }
  }
  final drop = s.startPressure - s.endPressure - intendedDrop;
  final rise = s.endFlow - s.startFlow - intendedRise;
  final channeling =
      s.duration >= minStageSecondsForCurveChecks &&
      drop >= channelingPressureDrop &&
      rise >= channelingFlowRise;
  return (channeling, drop, rise);
}

/// The profile a shot is checked against: the one stored at brew time,
/// otherwise the current version under its name. Also returns which one it
/// was — the AI should know whether it judges against the right version.
Future<({String? json, bool fromShot})> profileJsonForShot(
  AppDatabase db,
  Shot shot,
) async {
  if (shot.profileJson != null) return (json: shot.profileJson, fromShot: true);
  final name = shot.profileName;
  if (name == null || name.isEmpty) return (json: null, fromShot: false);
  final stored = await db.storedProfileByName(name, machine: shot.machine);
  return (json: stored?.json, fromShot: false);
}

String _unit(String type) => switch (type) {
  'pressure' => 'bar',
  // GaggiMate: pumped water — the recording does not contain it, so this
  // condition cannot be verified.
  'pumped' => 'ml water',
  'flow' => 'ml/s',
  'weight' => 'g',
  'time' => 's',
  _ => '',
};

String _n(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}
