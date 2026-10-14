import 'profile_draft.dart';

// Checks for user-built profiles.
//
// Two sources:
//   * What the format allows at all — schema.json from
//     github.com/MeticulousHome/espresso-profile-schema.
//   * What the machine tolerates in practice — the validation rules from
//     github.com/twchad/meticulous-mcp (profile_validator.py). The rules
//     are rewritten here, not translated; the server there is under GPL.
//
// The distinction matters: some things are valid per the schema but bring
// the machine to a halt (e.g. `interpolation: "none"`). So this is stricter
// than the schema, not just a copy of it.

// Three levels, as in the original (MACHINE / SAFETY / STRICT). The split is
// not cosmetic: Meticulous' official example profile has a flow stage
// without a pressure limit. If we treated that as an error, a profile the
// manufacturer ships itself could not be saved.
enum RuleSeverity {
  // Saving is blocked — the machine would reject the profile or get stuck
  // on it.
  error,

  // Runs, but can ruin the shot or block the machine. Saving stays
  // allowed, but the notice is shown at the top.
  safety,

  // Probably not intended, nothing more.
  warning,
}

class RuleFinding {
  const RuleFinding(this.severity, this.message, {this.stageIndex});

  final RuleSeverity severity;
  final String message;

  // Which stage the finding belongs to; null = affects the whole profile.
  final int? stageIndex;

  bool get isError => severity == RuleSeverity.error;
  bool get isSafety => severity == RuleSeverity.safety;

  // Only errors block saving.
  bool get blocksSaving => isError;
}

// Machine upper limit. The schema has none, the hardware does.
const maxPressureBar = 15.0;

// From this target pressure on, a missing flow limit becomes a gusher risk.
const _gusherPressureBar = 6.0;

const _accentColorPattern = r'^#[0-9A-Fa-f]{6}$';

// All findings for a profile, errors first.
List<RuleFinding> checkProfile(ProfileDraft draft) {
  final out = <RuleFinding>[..._checkHeader(draft), ..._checkVariables(draft)];

  for (var i = 0; i < draft.stages.length; i++) {
    out.addAll(checkStage(draft, i));
  }
  out.addAll(_checkWeightTriggerOrder(draft));

  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}

// Only the findings of a single stage — for the stage page.
List<RuleFinding> checkStage(ProfileDraft draft, int index) {
  final stage = draft.stages[index];
  final out = <RuleFinding>[];
  final label = stage.name.trim().isEmpty
      ? 'Stage ${index + 1}'
      : '"${stage.name.trim()}"';

  void error(String m) =>
      out.add(RuleFinding(RuleSeverity.error, m, stageIndex: index));
  void safety(String m) =>
      out.add(RuleFinding(RuleSeverity.safety, m, stageIndex: index));
  void warn(String m) =>
      out.add(RuleFinding(RuleSeverity.warning, m, stageIndex: index));

  // -- Format --------------------------------------------------------------

  if (stage.key.trim().isEmpty) {
    error('$label has no key. Every stage needs a unique key.');
  } else if (draft.stages
          .where((s) => s.key.trim() == stage.key.trim())
          .length >
      1) {
    error(
      '$label uses the key "${stage.key}" more than once. Keys must be unique.',
    );
  }

  if (!stageTypes.contains(stage.type)) {
    error('$label has an unknown type "${stage.type}".');
  }
  if (!dynamicsOverTypes.contains(stage.over)) {
    error(
      '$label runs its curve over "${stage.over}", which the machine does not know.',
    );
  }
  // The schema also allows "none" — that makes the machine stall.
  if (!interpolationTypes.contains(stage.interpolation)) {
    error(
      '$label uses "${stage.interpolation}" between points. Only Linear and Curve '
      'work — the machine stalls on anything else.',
    );
  }

  // -- Curve ---------------------------------------------------------------

  if (stage.points.isEmpty) {
    error('$label has no points, so there is nothing to follow.');
  } else if (stage.points.length == 1) {
    warn(
      '$label has a single point — add a second one to shape the curve over time.',
    );
  }

  if (stage.type == 'pressure') {
    for (var i = 0; i < stage.points.length; i++) {
      final v = stage.points[i].y.resolve(draft.variables);
      if (v == null) continue;
      if (v > maxPressureBar) {
        error(
          '$label point ${i + 1} asks for $v bar. The machine tops out at ${maxPressureBar.toInt()} bar.',
        );
      } else if (v < 0) {
        error('$label point ${i + 1} has a negative pressure.');
      }
    }
  }

  // Points must move forward on the x axis, otherwise the interpolation
  // jumps back.
  double? previousX;
  for (var i = 0; i < stage.points.length; i++) {
    final x = stage.points[i].x.resolve(draft.variables);
    if (x == null) continue;
    if (previousX != null && x < previousX) {
      error(
        '$label point ${i + 1} goes backwards in time. Points must run forwards.',
      );
      break;
    }
    previousX = x;
  }

  // -- Limits (the safety-relevant part) -----------------------------------

  final isLast = index == draft.stages.length - 1;

  // These two are the most important notices in the whole editor — but not
  // errors: Meticulous' own example profile has a flow stage without a
  // pressure limit.
  if (stage.type == 'flow' && !stage.hasLimit('pressure')) {
    final peak = stage.maxValue(draft.variables);
    final low = peak != null && peak <= 2;
    safety(
      '$label controls flow but has no pressure limit. With a fine grind the '
      'pressure can spike past 12 bar and stall the machine. '
      'Consider one around ${low ? 3 : 10} bar.',
    );
  }

  if (stage.type == 'pressure' && !stage.hasLimit('flow')) {
    final peak = stage.maxValue(draft.variables);
    // Below 6 bar a missing limit is harmless; if the target cannot be
    // resolved (variable), warn to be safe.
    if (peak == null || peak >= _gusherPressureBar) {
      safety(
        '$label controls pressure but has no flow limit. With a coarse grind '
        'this gushes. Consider one around 5 ml/s.',
      );
    }
  }

  final seen = <String>{};
  for (final limit in stage.limits) {
    if (!limitTypes.contains(limit.type)) {
      error('$label has a limit on "${limit.type}", which cannot be limited.');
      continue;
    }
    if (!seen.add(limit.type)) {
      warn('$label limits ${limit.type} twice — only one of them counts.');
    }
    final v = limit.value.resolve(draft.variables);
    if (v == null) continue;
    if (v < 0) {
      error('$label has a negative ${limit.type} limit.');
    } else if (limit.type == 'pressure' && v > 12) {
      warn(
        '$label limits pressure at $v bar — 10 to 12 bar is the safer range.',
      );
    } else if (limit.type == 'flow' && v > 8) {
      warn('$label limits flow at $v ml/s — 5 to 6 ml/s gives better control.');
    }
  }

  // -- Exit triggers -------------------------------------------------------

  if (stage.exitTriggers.isEmpty) {
    if (isLast) {
      // Perfectly fine: the last stage ends at the target weight.
      warn(
        '$label has no exit condition, so the shot runs until ${_g(draft.finalWeight)} is reached.',
      );
    } else {
      // The stage runs until the target weight — so none of the following
      // ones ever get a turn. That does not break the profile.
      safety(
        '$label has no exit condition. It runs until the target weight, so the '
        'stages after it never run.',
      );
    }
  } else {
    var hasTimeOrWeight = false;
    for (var i = 0; i < stage.exitTriggers.length; i++) {
      final t = stage.exitTriggers[i];
      if (!exitTriggerTypes.contains(t.type)) {
        error(
          '$label exit condition ${i + 1} uses an unknown type "${t.type}".',
        );
        continue;
      }
      if (t.type == 'time' || t.type == 'weight') hasTimeOrWeight = true;
      if (t.comparison != '>=' && t.comparison != '<=') {
        error(
          '$label exit condition ${i + 1} compares with "${t.comparison}" — only ≥ and ≤ exist.',
        );
      }
      if (!t.needsValue) continue;
      final v = t.value.resolve(draft.variables);
      if (v == null) continue;
      if (t.type == 'pressure' && (v > maxPressureBar || v < 0)) {
        error(
          '$label exit condition ${i + 1} waits for $v bar, which is out of range.',
        );
      }
    }
    if (!hasTimeOrWeight) {
      safety(
        '$label can only be left by pressure, flow or position. Add a time or '
        'weight condition as a fallback so it cannot run forever.',
      );
    }
  }

  return out;
}

// ------------------------------------------------------------------ Header

List<RuleFinding> _checkHeader(ProfileDraft draft) {
  final out = <RuleFinding>[];
  void error(String m) => out.add(RuleFinding(RuleSeverity.error, m));
  void warn(String m) => out.add(RuleFinding(RuleSeverity.warning, m));

  if (draft.name.trim().isEmpty) error('The profile needs a name.');
  if (draft.author.trim().isEmpty) error('The profile needs an author.');
  if (draft.stages.isEmpty) error('The profile has no stages yet.');

  // Schema limits.
  if (draft.temperature < 0 || draft.temperature > 100) {
    error('Temperature must be between 0 and 100 °C.');
  } else if (draft.temperature < 80) {
    warn(
      '${_c(draft.temperature)} is below the usual range — that suits very dark roasts.',
    );
  } else if (draft.temperature > 96) {
    warn('${_c(draft.temperature)} is high — that suits very light roasts.');
  }

  if (draft.finalWeight <= 0 || draft.finalWeight > 2000) {
    error('Target weight must be between 0 and 2000 g.');
  } else if (draft.finalWeight < 20) {
    warn(
      '${_g(draft.finalWeight)} is a small shot — espresso is usually 25 to 45 g.',
    );
  } else if (draft.finalWeight > 60) {
    warn('${_g(draft.finalWeight)} is a large shot — that is lungo territory.');
  }

  final short = draft.shortDescription;
  if (short != null && short.length > 100) {
    error('The tagline is ${short.length} characters — 100 is the maximum.');
  }
  if (!RegExp(_accentColorPattern).hasMatch(draft.accentColor)) {
    error('The highlight colour must look like #RRGGBB.');
  }

  return out;
}

// --------------------------------------------------------------- Variables

List<RuleFinding> _checkVariables(ProfileDraft draft) {
  final out = <RuleFinding>[];
  void error(String m) => out.add(RuleFinding(RuleSeverity.error, m));
  void warn(String m) => out.add(RuleFinding(RuleSeverity.warning, m));

  final keys = <String>{};
  for (final v in draft.variables) {
    final label = v.name.trim().isEmpty ? v.key : '"${v.name.trim()}"';
    if (v.key.trim().isEmpty) {
      error('Variable $label has no key.');
    } else if (!keys.add(v.key)) {
      error('Two variables share the key "${v.key}".');
    }
    if (!variableTypes.contains(v.type)) {
      error('Variable $label has an unknown type "${v.type}".');
    }
    if (!draft.usesVariable(v.key)) {
      warn('Variable $label is not used anywhere.');
    }
  }

  // References that point nowhere.
  final referenced = <String>{};
  for (final stage in draft.stages) {
    for (final p in stage.points) {
      if (p.x.isVariable) referenced.add(p.x.variableKey!);
      if (p.y.isVariable) referenced.add(p.y.variableKey!);
    }
    for (final t in stage.exitTriggers) {
      if (t.value.isVariable) referenced.add(t.value.variableKey!);
    }
    for (final l in stage.limits) {
      if (l.value.isVariable) referenced.add(l.value.variableKey!);
    }
  }
  for (final key in referenced) {
    if (!keys.contains(key)) {
      error('Something refers to the variable "$key", but it is not defined.');
    }
  }

  return out;
}

// ------------------------------------------------ Weight trigger sequence

// Absolute weight triggers count from the start of the shot. If a later
// stage waits for a weight that an earlier one has already exceeded, it
// fires immediately — the stage is effectively skipped.
List<RuleFinding> _checkWeightTriggerOrder(ProfileDraft draft) {
  final out = <RuleFinding>[];
  double? reached;

  for (var i = 0; i < draft.stages.length; i++) {
    final stage = draft.stages[i];
    final label = stage.name.trim().isEmpty
        ? 'Stage ${i + 1}'
        : '"${stage.name.trim()}"';

    for (final t in stage.exitTriggers) {
      if (t.type != 'weight' || t.relative) continue;
      final v = t.value.resolve(draft.variables);
      if (v == null) continue;

      if (reached != null && v <= reached) {
        out.add(
          RuleFinding(
            RuleSeverity.error,
            '$label waits for ${_g(v)} total, but ${_g(reached)} is already '
            'reached by then — this stage would be skipped. Use a higher '
            'value, or switch the condition to "this stage".',
            stageIndex: i,
          ),
        );
      } else if (i > 0 && v < 10) {
        out.add(
          RuleFinding(
            RuleSeverity.warning,
            '$label waits for ${_g(v)} counted from the start of the shot. '
            'Did you mean "this stage"?',
            stageIndex: i,
          ),
        );
      }
      if (reached == null || v > reached) reached = v;
    }
  }

  return out;
}

// ------------------------------------------------------------------ Format

String _g(double v) => '${_trim(v)} g';
String _c(double v) => '${_trim(v)} °C';

String _trim(double v) {
  final rounded = (v * 10).round() / 10;
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}
