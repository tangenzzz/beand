import '../../models/profile_draft.dart';

// GaggiMate profile <-> [ProfileDraft], so the profile editor stays the same
// for both machines.
//
// The read direction for the VIEW already exists
// (gaggimate_profile_detail.dart). This one is stricter: whatever comes in
// must come back out after editing — otherwise a profile silently loses
// properties on save that the editor doesn't even show
// (valve setting, phase group, transition type).
//
// For that, every draft carries the original JSON under "_source". Writing
// starts from it and only overwrites what the editor can actually change.
// Keys starting with "_" never go to a machine (see _public in
// profile_draft.dart).
//
// Terms (cf. gaggimate_profile_detail.dart):
//
//   ProfileDraft                 GaggiMate
//   -------------------------------------------------------------------
//   name                         label
//   stages[]                     phases[]
//   stage.type                   pump.target, or "power" if pump
//                                is a bare percentage
//   last curve point             the controlled setpoint in pump
//   first curve point            start value of the ramp
//                                (transition.duration)
//   limits[]                     the NON-controlled value in pump
//   time trigger (relative)      duration of the phase
//   other exit_triggers          targets[]

const _sourceKey = '_source';

// The substitute value shown for a "-1" (hold value). If it is unchanged
// on write, the -1 is kept.
const _heldKey = '_heldAs';

// Whether the phase's ramp could be shown as a curve. For the FIRST phase
// that isn't possible — there is no previous setpoint for it to rise from.
// Then the points say nothing about the transition and it is left untouched
// on write.
const _rampShownKey = '_rampShown';

// GaggiMate calls the weight target "volumetric"; "pumped" (pumped water)
// has no equivalent on the Meticulous side and keeps its name.
String _triggerTypeIn(String type) => switch (type) {
  'volumetric' => 'weight',
  _ => type,
};

String _triggerTypeOut(String type) => switch (type) {
  'weight' => 'volumetric',
  _ => type,
};

String _operatorIn(String op) => switch (op) {
  'gte' => '>=',
  'lte' => '<=',
  _ => op,
};

String _operatorOut(String comparison) => switch (comparison) {
  '>=' => 'gte',
  '<=' => 'lte',
  _ => comparison,
};

double? _num(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v);
  return null;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

// ------------------------------------------------------------------ Reading

ProfileDraft gaggiMateDraftFromJson(Map<String, dynamic> json) {
  final rawPhases = json['phases'] as List? ?? const [];
  final stages = <DraftStage>[];

  // A ramp starts at the setpoint the previous phase ended with.
  double? previousSetpoint;
  double? lastWeightTarget;

  for (var i = 0; i < rawPhases.length; i++) {
    final raw = rawPhases[i];
    if (raw is! Map) continue;
    final phase = Map<String, dynamic>.from(raw);

    final duration = _num(phase['duration']) ?? 0;
    final pump = phase['pump'];

    final String type;
    double? setpoint;
    final limits = <DraftLimit>[];

    if (pump is Map) {
      final advanced = Map<String, dynamic>.from(pump);
      type = (advanced['target'] ?? 'pressure').toString();
      setpoint = _num(advanced[type]);
      // The other value is a soft limit; 0 means "none".
      final otherType = type == 'pressure' ? 'flow' : 'pressure';
      final other = _num(advanced[otherType]);
      if (other != null && other > 0) {
        limits.add(
          DraftLimit(type: otherType, value: DraftValue.number(other)),
        );
      }
    } else {
      // Simple profiles only control pump power in percent.
      type = 'power';
      setpoint = _num(pump);
    }

    // -1 means "hold the value measured at phase start". For display the
    // previous setpoint is used; on write the -1 stays as long as nobody
    // touches the value — for that the stage remembers which substitute
    // value it showed.
    double? heldAs;
    if (setpoint != null && setpoint < 0) {
      setpoint = previousSetpoint;
      heldAs = setpoint;
    }

    final transition = _map(phase['transition']);
    final rampSeconds = _num(transition['duration']) ?? 0;
    final transitionType = (transition['type'] ?? 'instant').toString();

    final points = <DraftPoint>[];
    var ramped = false;
    if (setpoint != null) {
      ramped =
          rampSeconds > 0 &&
          transitionType != 'instant' &&
          previousSetpoint != null &&
          previousSetpoint != setpoint;
      if (ramped) {
        points.add(
          DraftPoint(
            const DraftValue.number(0),
            DraftValue.number(previousSetpoint),
          ),
        );
        points.add(
          DraftPoint(
            DraftValue.number(rampSeconds.clamp(0, duration)),
            DraftValue.number(setpoint),
          ),
        );
      } else {
        points.add(
          DraftPoint(const DraftValue.number(0), DraftValue.number(setpoint)),
        );
      }
      if (duration > 0) {
        points.add(
          DraftPoint(DraftValue.number(duration), DraftValue.number(setpoint)),
        );
      }
      previousSetpoint = setpoint;
    }

    final triggers = <DraftTrigger>[
      // On the GaggiMate the duration is a property of the phase itself,
      // not one condition among many. The editor still lists it with the
      // conditions — that's where people look for it.
      if (duration > 0)
        DraftTrigger(
          type: 'time',
          value: DraftValue.number(duration),
          relative: true,
        ),
      for (final t in (phase['targets'] as List? ?? const []))
        if (t is Map)
          DraftTrigger(
            type: _triggerTypeIn((t['type'] ?? '').toString()),
            value: DraftValue.number(_num(t['value']) ?? 0),
            relative: false,
            comparison: _operatorIn((t['operator'] ?? 'gte').toString()),
          ),
    ];

    for (final t in (phase['targets'] as List? ?? const [])) {
      if (t is Map && t['type'] == 'volumetric') {
        final value = _num(t['value']);
        if (value != null && value > 0) lastWeightTarget = value;
      }
    }

    stages.add(
      DraftStage(
        name: (phase['name'] ?? '').toString(),
        key: 'phase_${i + 1}',
        type: type,
        points: points,
        interpolation: transitionType == 'instant' ? 'linear' : 'curve',
        exitTriggers: triggers,
        limits: limits,
      )..extra = {_sourceKey: phase, _heldKey: ?heldAs, _rampShownKey: ramped},
    );
  }

  final description = (json['description'] ?? '').toString().trim();
  return ProfileDraft(
    id: (json['id'] ?? '').toString(),
    name: (json['label'] ?? '').toString(),
    // The GaggiMate keeps no author; the editor requires one.
    author: 'bean\'d',
    authorId: newUuid(),
    temperature: _num(json['temperature']) ?? 93,
    finalWeight: lastWeightTarget ?? 0,
    description: description.isEmpty ? null : description,
    stages: stages,
  )..extra = {_sourceKey: json};
}

// ------------------------------------------------------------------ Writing

Map<String, dynamic> gaggiMateJsonFromDraft(ProfileDraft draft) {
  final source = _map(draft.extra[_sourceKey]);

  final phases = <Map<String, dynamic>>[];
  for (final stage in draft.stages) {
    phases.add(_phaseFromStage(stage, draft));
  }

  return {
    // Whatever already existed stays — type, favorite, selected, utility and
    // anything the firmware adds later.
    ...source,
    'id': draft.id,
    'label': draft.name,
    'description': draft.description ?? '',
    'temperature': draft.temperature,
    'phases': phases,
  };
}

Map<String, dynamic> _phaseFromStage(DraftStage stage, ProfileDraft draft) {
  final source = _map(stage.extra[_sourceKey]);
  final out = <String, dynamic>{
    // Fields the editor doesn't touch (valve, phase, temperature …) come
    // from here unchanged.
    ...source,
    'name': stage.name,
  };

  // -- Setpoint and limit -------------------------------------------------

  final setpoint = stage.points.isEmpty
      ? null
      : stage.points.last.y.resolve(draft.variables);

  if (stage.type == 'power') {
    out['pump'] = setpoint ?? 0;
  } else {
    final pump = _map(source['pump']);
    final otherType = stage.type == 'pressure' ? 'flow' : 'pressure';

    // A -1 ("hold value") stays as long as the displayed substitute value is
    // unchanged — otherwise the intent would be silently lost.
    final heldAs = _num(stage.extra[_heldKey]);
    final stillHeld = heldAs != null && setpoint == heldAs;

    pump['target'] = stage.type;
    if (!stillHeld) pump[stage.type] = setpoint ?? 0;
    final limit = stage.limits.where((l) => l.type == otherType).firstOrNull;
    pump[otherType] = limit?.value.resolve(draft.variables) ?? 0;
    out['pump'] = pump;
  }

  // -- Transition -----------------------------------------------------------

  final transition = _map(source['transition']);
  final showsRamp =
      stage.points.length >= 2 &&
      stage.points.first.y.resolve(draft.variables) != setpoint;

  if (showsRamp) {
    transition['duration'] = stage.points[1].x.resolve(draft.variables) ?? 0;
    if ((transition['type'] ?? 'instant') == 'instant') {
      transition['type'] = 'ease-in-out';
    }
  } else if (stage.extra[_rampShownKey] == true) {
    // The ramp WAS visible and is now gone — so someone removed it on
    // purpose.
    transition['duration'] = 0;
    transition['type'] = 'instant';
  }
  // Otherwise the points say nothing about the transition (first phase
  // without a previous setpoint). Then whatever the firmware had stays.
  if (transition.isEmpty) {
    transition.addAll({'type': 'instant', 'duration': 0, 'adaptive': false});
  }
  out['transition'] = transition;

  // -- Duration and conditions --------------------------------------------

  // The relative time trigger is the phase duration, not a target of its own.
  final durationTrigger = stage.exitTriggers
      .where((t) => t.type == 'time' && t.relative)
      .firstOrNull;
  out['duration'] =
      durationTrigger?.value.resolve(draft.variables) ??
      _num(source['duration']) ??
      0;

  final targets = [
    for (final t in stage.exitTriggers)
      if (!(t.type == 'time' && t.relative) && t.needsValue)
        {
          'type': _triggerTypeOut(t.type),
          'operator': _operatorOut(t.comparison),
          'value': t.value.resolve(draft.variables) ?? 0,
        },
  ];
  // Some phases have no `targets` at all (the "Dripping" phase in the
  // example profile). Adding an empty array would be a change — so only
  // create it if there is something to write or the field existed before.
  if (targets.isNotEmpty || source.containsKey('targets')) {
    out['targets'] = targets;
  }

  return out;
}

// An empty GaggiMate profile for "Create new profile".
ProfileDraft gaggiMateEmptyDraft() => gaggiMateDraftFromJson({
  'id': '',
  'label': '',
  'type': 'pro',
  'description': '',
  'temperature': 93,
  'phases': [
    {
      'name': 'Pre-infusion',
      'phase': 'preinfusion',
      'valve': 1,
      'duration': 10,
      'temperature': 0,
      'transition': {'type': 'instant', 'duration': 0, 'adaptive': false},
      'pump': {'target': 'flow', 'pressure': 3, 'flow': 4},
      'targets': <Map<String, dynamic>>[],
    },
    {
      'name': 'Brew',
      'phase': 'brew',
      'valve': 1,
      'duration': 30,
      'temperature': 0,
      'transition': {'type': 'instant', 'duration': 0, 'adaptive': false},
      'pump': {'target': 'pressure', 'pressure': 9, 'flow': 5},
      'targets': [
        {'type': 'volumetric', 'operator': 'gte', 'value': 36},
      ],
    },
  ],
});
