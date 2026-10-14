import '../../models/machine_profile.dart';
import '../../models/profile_detail.dart';

// Translates a GaggiMate profile (the firmware's schema/profile.json) into
// the same [ProfileDetail] shape the profile view uses for the Meticulous —
// so a GaggiMate profile looks the same there and no second screen has to
// be maintained.
//
// The concepts match almost one to one, they are just named differently:
//
//   Meticulous                    GaggiMate
//   ------------------------------------------------------------------
//   stages[]                      phases[]
//   stage.type (pressure/flow)    pump.target (or "power" for percent)
//   dynamics.points               built from transition + pump setpoint
//   exit_triggers[]               targets[] + duration
//   limits[]                      the non-controlled value from pump
//
// What the GaggiMate doesn't know (variables, author, image) stays empty.
ProfileDetail gaggiMateProfileDetail(Map<String, dynamic> json) {
  final id = (json['id'] ?? '').toString();
  final profileTemp = _num(json['temperature']) ?? 0;
  final rawPhases = json['phases'] as List? ?? const [];

  final stages = <ProfileStage>[];
  // The start of a ramp is the setpoint the previous phase ended with — the
  // firmware continues from there.
  double? previousSetpoint;
  double? lastWeightTarget;

  for (var i = 0; i < rawPhases.length; i++) {
    final raw = rawPhases[i];
    if (raw is! Map) continue;
    final phase = Map<String, dynamic>.from(raw);
    final duration = _num(phase['duration']) ?? 0;
    final pump = phase['pump'];

    // Two forms: a percentage (simple profiles, flush routines) or an object
    // with controlled pressure or flow.
    final String type;
    double? setpoint;
    final limits = <StageLimit>[];
    if (pump is Map) {
      final advanced = Map<String, dynamic>.from(pump);
      type = (advanced['target'] ?? 'pressure').toString();
      setpoint = _num(advanced[type]);
      // The other value is a soft limit; 0 means "none".
      final otherType = type == 'pressure' ? 'flow' : 'pressure';
      final other = _num(advanced[otherType]);
      if (other != null && other > 0) {
        limits.add(StageLimit(type: otherType, value: ProfileValue(other)));
      }
    } else {
      type = 'power';
      setpoint = _num(pump);
    }

    // -1 means "hold the value measured at phase start" — no concrete
    // setpoint can be derived from it.
    final held = setpoint != null && setpoint < 0;
    if (held) setpoint = previousSetpoint;

    final transition = phase['transition'] is Map
        ? Map<String, dynamic>.from(phase['transition'] as Map)
        : const <String, dynamic>{};
    final rampSeconds = _num(transition['duration']) ?? 0;
    final interpolation = (transition['type'] ?? 'instant').toString();

    // The curve as points over time: without a ramp a straight line at the
    // setpoint, with a ramp first up from the previous value, then hold.
    final points = <StagePoint>[];
    if (setpoint != null) {
      final ramp = rampSeconds > 0 && interpolation != 'instant';
      if (ramp && previousSetpoint != null && previousSetpoint != setpoint) {
        points.add(StagePoint(0, previousSetpoint));
        points.add(StagePoint(rampSeconds.clamp(0, duration), setpoint));
      } else {
        points.add(StagePoint(0, setpoint));
      }
      if (duration > 0) points.add(StagePoint(duration, setpoint));
      previousSetpoint = setpoint;
    }

    final triggers = <StageTrigger>[
      // On the GaggiMate the duration is not one exit condition among many
      // but a property of the phase. The view still lists it with the
      // triggers — that's where people look for it.
      if (duration > 0)
        StageTrigger(
          type: 'time',
          value: ProfileValue(duration),
          relative: true,
          comparison: '>=',
        ),
      for (final t in (phase['targets'] as List? ?? const []))
        if (t is Map)
          StageTrigger(
            type: _triggerType((t['type'] ?? '').toString()),
            value: ProfileValue(_num(t['value'])),
            relative: false,
            // The firmware writes "gte"/"lte"; the view and the shot findings
            // work with ">="/"<=" as on the Meticulous. Without the
            // translation it read "weight gte 36 g", and no weight exit was
            // ever detected as triggered.
            comparison: switch ((t['operator'] ?? 'gte').toString()) {
              'gte' => '>=',
              'lte' => '<=',
              'gt' => '>',
              'lt' => '<',
              final other => other,
            },
          ),
    ];
    for (final t in (phase['targets'] as List? ?? const [])) {
      if (t is Map && t['type'] == 'volumetric') {
        final value = _num(t['value']);
        if (value != null && value > 0) lastWeightTarget = value;
      }
    }

    stages.add(
      ProfileStage(
        number: i + 1,
        name: _phaseName(phase, i),
        type: type,
        points: points,
        over: 'time',
        interpolation: interpolation == 'instant' ? 'linear' : interpolation,
        exitTriggers: triggers,
        limits: limits,
      ),
    );
  }

  final description = (json['description'] ?? '').toString().trim();
  return ProfileDetail(
    id: id,
    name: (json['label'] ?? '').toString(),
    temperature: profileTemp,
    finalWeight: lastWeightTarget ?? 0,
    // No image and no own color: the card gets one from the placeholder
    // palette, tied to the id.
    accentColor: profilePlaceholderColor(id),
    imagePath: null,
    shortDescription: null,
    description: description.isEmpty ? null : description,
    author: null,
    previousAuthors: const [],
    lastChanged: null,
    stages: stages,
    // The GaggiMate has no profile variables.
    variables: const [],
    isTemporary: false,
  );
}

// The phase always has a name; if it's missing, at least the group
// (preinfusion or brew) stays recognizable.
String _phaseName(Map<String, dynamic> phase, int index) {
  final name = (phase['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  return switch ((phase['phase'] ?? '').toString()) {
    'preinfusion' => 'Pre-infusion',
    'brew' => 'Brew',
    _ => 'Phase ${index + 1}',
  };
}

// GaggiMate calls the weight target "volumetric", the shared view "weight";
// "pumped" (pumped water) has no equivalent there and stays as is.
String _triggerType(String type) => switch (type) {
  'volumetric' => 'weight',
  _ => type,
};

double? _num(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v);
  return null;
}
