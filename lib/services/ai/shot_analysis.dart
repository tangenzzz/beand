import 'dart:convert';

import '../../database/database.dart';
import '../../models/profile_detail.dart';
import '../../models/shot_facts.dart';
import '../../models/shot_phases.dart';
import '../../models/taste_profile.dart';
import 'ai_prompt.dart';

// Judge a shot and say what to change on the next one. This is the domain
// side — what the model gets to see, in what shape it answers and how the
// answer is stored on the shot. Which provider answers doesn't matter to
// this file.
//
// The input is a summary, not raw data: 100+ data points with 25 columns
// cost tokens and blur the view. What a barista reads from the curve — how
// long each phase ran, what pressure, what flow — the app computes itself;
// the curve itself is included thinned out.

/// Maximum number of points per phase the curve keeps.
const analysisPointsPerPhase = 20;

/// How many older shots of the same bean go along as history.
const analysisHistoryShots = 5;

/// What the model learns about a shot. Gathered from the DB
/// (see [AppDatabase.shotAnalysisInput]) and turned into text here.
class ShotAnalysisInput {
  const ShotAnalysisInput({
    required this.shot,
    this.bean,
    this.readings = const [],
    this.profileJson,
    this.profileFromShot = false,
    this.history = const [],
  });

  final Shot shot;
  final Bean? bean;
  final List<ShotReading> readings;

  /// The stored profile JSON, as the machine delivers it.
  final String? profileJson;

  /// Does [profileJson] come from the shot itself (version at brew time) —
  /// or is it the current version under the same name?
  final bool profileFromShot;

  /// Earlier shots of the same bean, newest first — the part a human doesn't
  /// keep in mind: what has been tried already, and how did it taste?
  final List<Shot> history;
}

/// How the extraction turned out overall. Deliberately coarse — the field is
/// there for later filters ("all under-extracted"), not as a detailed
/// verdict.
enum ExtractionVerdict {
  under,
  over,
  balanced,
  uneven,
  unclear;

  static ExtractionVerdict? parse(Object? value) {
    if (value is! String) return null;
    final v = value.trim().toLowerCase();
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }
}

/// A concrete next step.
class AnalysisStep {
  const AnalysisStep({required this.change, required this.why});

  /// Short and imperative: "Grind finer", "Stop at 40 g".
  final String change;

  /// A sentence that refers to the data.
  final String why;

  Map<String, Object?> toJson() => {'change': change, 'why': why};
}

/// The model's answer — and what is stored on the shot.
class ShotAnalysis {
  const ShotAnalysis({
    required this.summary,
    required this.steps,
    this.extraction,
    this.caveat,
  });

  /// One-sentence finding.
  final String summary;

  /// One to three next steps, most important first.
  final List<AnalysisStep> steps;

  final ExtractionVerdict? extraction;

  /// What was missing and limits the statement ("no taste rating"), else
  /// null.
  final String? caveat;

  bool get isEmpty => summary.isEmpty && steps.isEmpty;

  /// Lenient as in the bean form: a step without a change is none and is
  /// dropped; more than three are capped because the UI promises "two to
  /// three".
  factory ShotAnalysis.fromJson(Map<String, Object?> json) {
    final steps = <AnalysisStep>[];
    final raw = json['steps'];
    if (raw is List) {
      for (final s in raw) {
        if (s is! Map) continue;
        final change = _text(s['change']);
        if (change == null) continue;
        steps.add(AnalysisStep(change: change, why: _text(s['why']) ?? ''));
        if (steps.length == 3) break;
      }
    }
    return ShotAnalysis(
      summary: _text(json['summary']) ?? '',
      steps: steps,
      extraction: ExtractionVerdict.parse(json['extraction']),
      caveat: _text(json['caveat']),
    );
  }

  Map<String, Object?> toJson() => {
    'summary': summary,
    'extraction': extraction?.name,
    'steps': [for (final s in steps) s.toJson()],
    'caveat': caveat,
  };

  String encode() => jsonEncode(toJson());

  /// Reads what's in `shots.aiAnalysis`. Broken data yields null instead of
  /// an exception — an old format must not break the shot detail.
  static ShotAnalysis? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final json = jsonDecode(stored);
      if (json is! Map<String, Object?>) return null;
      final analysis = ShotAnalysis.fromJson(json);
      return analysis.isEmpty ? null : analysis;
    } catch (_) {
      return null;
    }
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final t = value.trim();
    if (t.isEmpty || t.toLowerCase() == 'null') return null;
    return t;
  }
}

Map<String, Object?> shotAnalysisSchema() => aiObjectSchema({
  'summary': aiField(
    'string',
    description:
        'One sentence: what happened in this shot and why it tasted the way '
        'it did. Cite numbers from the data.',
  ),
  'extraction': {
    'type': 'string',
    'enum': [for (final e in ExtractionVerdict.values) e.name],
    'description':
        'Overall extraction. "uneven" = signs of channeling. "unclear" if the '
        'data does not support a call.',
  },
  'steps': aiArray(
    aiObjectSchema({
      'change': aiField(
        'string',
        description:
            'The change for the next shot, imperative, at most 8 words. '
            'E.g. "Grind finer", "Stop at 40 g instead of 36 g".',
      ),
      'why': aiField(
        'string',
        description: 'One sentence, grounded in the data given.',
      ),
    }),
    description:
        '1 to 3 next steps, most important first. Change one main variable at '
        'a time — a second step is a fallback or a smaller tweak, not a '
        'simultaneous overhaul.',
  ),
  'caveat': aiNullable(
    'string',
    description:
        'What was missing and limits the advice (e.g. no taste rating, no '
        'curve). null if nothing important was missing.',
  ),
});

const shotAnalysisSystemPrompt =
    'You are an experienced espresso coach looking at one shot from a '
    'home espresso machine with pressure, flow and weight sensors. You '
    'judge from the data given and nothing else.\n'
    'Rules:\n'
    '- Base every statement on the numbers provided. Do not invent '
    'measurements, tasting notes or equipment.\n'
    '- Taste ratings from the user outweigh textbook targets. A shot that '
    'breaks the 1:2 / 25–30 s rule of thumb but is rated well is not a '
    'problem to fix.\n'
    '- Grind settings are numbers on the user\'s own grinder; you do NOT know '
    'whether a higher number is finer or coarser. Say "finer" or "coarser", '
    'never a target number — unless earlier shots of the same bean show '
    'which way the scale runs.\n'
    '- Judge the shot against the PROFILE\'s intent, not against a classic '
    '9-bar espresso. The profile section lists what each stage was told to '
    'do; compare it with what was measured. In a flow-controlled stage '
    'with a pressure cap, low pressure is the design — styles like "soup", '
    'turbo or allongé shots run at a few bar on purpose. Only call pressure '
    'too low if a PRESSURE target was missed, or the flow target was '
    'overshot because the puck gave no resistance at all.\n'
    '- The app has already checked every stage (section "Findings"). '
    'An exit marked PLANNED is the profile working as designed — never call '
    'it early, cut short or a problem. STALL means the puck choked (usually '
    'grind coarser or dose less). CHANNELING means an uneven puck — suggest '
    'puck preparation (distribution, tamping) before grind or profile '
    'changes. BACKSTOP means a safety exit fired instead of the stage\'s '
    'goal. "Off target" means the machine could not follow the profile, '
    'usually a grind or dose mismatch — unless a cap was reached on purpose.\n'
    '- If something important is missing (no rating, no curve), still give '
    'your best advice and name what was missing in "caveat".\n'
    '- Write plain English, short sentences, no greetings.';

/// The request including data.
String shotAnalysisTask(ShotAnalysisInput input) {
  final b = StringBuffer()
    ..writeln('Analyse this espresso shot and suggest what to change next.')
    ..writeln();

  b.writeln('## Shot');
  for (final line in _shotLines(input.shot)) {
    b.writeln('- $line');
  }

  final bean = input.bean;
  if (bean != null) {
    b
      ..writeln()
      ..writeln('## Bean');
    final roastDate = bean.thawedDate ?? bean.roastDate;
    final age = roastDate == null
        ? null
        : input.shot.timestamp.difference(roastDate).inDays;
    for (final line in [
      'Name: ${bean.name}',
      if (_has(bean.roaster)) 'Roaster: ${bean.roaster}',
      if (bean.isBlend != null) bean.isBlend! ? 'Blend' : 'Single origin',
      if (_has(bean.roastedFor)) 'Roasted for: ${bean.roastedFor}',
      if (_has(bean.roastLevel)) 'Roast level: ${bean.roastLevel}',
      if (_has(bean.country)) 'Origin: ${bean.country}',
      if (_has(bean.processing)) 'Processing: ${bean.processing}',
      if (_has(bean.variety)) 'Variety: ${bean.variety}',
      if (_has(bean.taste)) 'Roaster\'s tasting notes: ${bean.taste}',
      if (age != null)
        bean.thawedDate != null
            ? 'Thawed $age days before this shot'
            : 'Roasted $age days before this shot',
    ]) {
      b.writeln('- $line');
    }
  }

  // The profile in plain text, variables resolved. The raw JSON is full of
  // references ("\$flow_Perc Flowrate"); a model that doesn't resolve them
  // takes an intentionally low pressure for a mistake (this happened with a
  // real profile).
  final detail = parseShotProfile(input.profileJson);
  final intents = <String, String>{};
  if (detail != null && detail.stages.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Profile: what the machine was told to do')
      ..writeln(
        input.profileFromShot
            ? '(The exact version that ran this shot.)'
            : '(Today\'s version of this profile — the one used for the shot '
                  'was not recorded and may have differed.)',
      )
      ..writeln(
        '- ${detail.name}: target ${_n(detail.temperature)} °C, '
        'stops at ${_n(detail.finalWeight)} g',
      );
    final desc = [
      detail.shortDescription,
      detail.description,
    ].whereType<String>().where(_has).join(' — ');
    if (desc.isNotEmpty) b.writeln('- Author\'s description: $desc');
    for (final st in detail.stages) {
      final intent = stageIntent(st);
      intents[st.name.toLowerCase()] = intent;
      b.writeln('- Stage ${st.number} "${st.name}": $intent');
    }
    final caps = [
      for (final st in detail.stages)
        if (st.type != 'pressure')
          for (final l in st.limits)
            if (l.type == 'pressure' && l.value.value != null) l.value.value!,
    ];
    final pressureTargets = [
      for (final st in detail.stages)
        if (st.type == 'pressure')
          for (final pt in st.points) ?pt.y,
    ];
    if (pressureTargets.isEmpty && caps.isNotEmpty) {
      final maxCap = caps.reduce((a, c) => a > c ? a : c);
      b.writeln(
        '- No stage targets pressure; the highest pressure the profile ever '
        'allows is ${_n(maxCap)} bar. Low pressure in this shot is by '
        'design, not a sign of a coarse grind.',
      );
    }
  } else {
    final raw = _compactProfile(input.profileJson);
    b.writeln();
    if (raw != null) {
      b
        ..writeln('## Profile (raw, as stored on the machine)')
        ..writeln(raw);
    } else {
      b
        ..writeln('## Profile')
        ..writeln(
          'Unknown — not available. Do not assume a classic 9-bar profile.',
        );
    }
  }

  final phases = computePhases(input.readings)
      .where((p) => !p.isRetraction)
      .toList();
  if (input.readings.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Measured, per stage');
    final tracksTemp = input.shot.machine == 'gaggimate';
    for (final line in _phaseLines(
      input.readings,
      phases,
      tracksTemp,
      intents,
    )) {
      b.writeln('- $line');
    }
    final facts = computeShotFacts(
      readings: input.readings,
      profile: parseShotProfile(input.profileJson),
      finalWeight: input.shot.finalWeight,
      machineExits: parseStageExits(input.shot.stageExits),
    );
    b
      ..writeln()
      ..writeln(
        '## Findings computed by the app (authoritative — trust these over '
        'your own reading of the curve)',
      )
      ..write(facts.factSheet());
    b
      ..writeln()
      ..writeln(
        '## Curve (thinned to ≤$analysisPointsPerPhase points per stage)',
      )
      ..writeln(
        tracksTemp
            ? 't_s, pressure_bar, flow_ml_s, weight_g, temp_c, stage'
            : 't_s, pressure_bar, flow_ml_s, weight_g, stage',
      );
    for (final r in thinReadings(input.readings)) {
      final cells = [
        (r.timeMs / 1000).toStringAsFixed(1),
        _n(r.pressure),
        _n(r.flow),
        _n(r.weight),
        if (tracksTemp) _n(r.barUp),
        phaseLabel(r.stage ?? ''),
      ];
      b.writeln(cells.join(', '));
    }
  } else {
    b
      ..writeln()
      ..writeln('## Curve')
      ..writeln('Not available for this shot.');
  }

  if (input.history.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Earlier shots of the same bean (newest first)');
    for (final s in input.history) {
      b.writeln('- ${_shotLines(s, brief: true).join('; ')}');
    }
  }
  return b.toString();
}

List<String> _shotLines(Shot s, {bool brief = false}) {
  final ratio = s.doseGrams != null && s.doseGrams! > 0 && s.finalWeight != null
      ? '1:${(s.finalWeight! / s.doseGrams!).toStringAsFixed(1)}'
      : null;
  final taste = s.tasteValues;
  final extras = splitTasteExtras(s.tasteExtras);
  return [
    if (brief) 'Date: ${_date(s.timestamp)}',
    if (!brief && _has(s.profileName)) 'Profile: ${s.profileName}',
    if (brief && _has(s.profileName)) 'profile ${s.profileName}',
    'Dose: ${_g(s.doseGrams)}',
    'Yield: ${_g(s.finalWeight)}',
    if (ratio != null) 'Ratio: $ratio',
    'Time: ${s.durationMs == null ? 'unknown' : '${(s.durationMs! / 1000).toStringAsFixed(1)} s'}',
    'Grind setting: ${s.grindSize ?? 'unknown'}',
    if (s.profileTemp != null) 'Target temperature: ${_n(s.profileTemp)} °C',
    if (!brief && s.brewTemp != null)
      'Measured mean temperature: ${_n(s.brewTemp)} °C',
    'Stars: ${s.rating == null ? 'not rated' : '${s.rating}/5'}',
    if (taste.isRated)
      'Taste (0–5, ${brief ? 'non-zero only' : 'only rated axes listed'}): '
          '${[for (final axis in TasteAxis.values)
            if ((taste[axis] ?? 0) > 0) '${axis.label}${axis.isPositive ? '' : ' (defect)'} ${taste[axis]}'].join(', ')}'
    else if (!brief)
      'Taste: not rated',
    if (extras.isNotEmpty) 'Tasted: ${extras.join(', ')}',
    if (_has(s.notes)) 'User notes: "${s.notes!.trim()}"',
  ];
}

List<String> _phaseLines(
  List<ShotReading> readings,
  List<ShotPhase> phases,
  bool tracksTemp,
  Map<String, String> intents,
) {
  if (phases.isEmpty) {
    return [_rangeLine('Whole shot', readings, tracksTemp)];
  }
  return [
    for (final p in phases)
      _rangeLine(
        '${p.name} (${(p.startMs / 1000).toStringAsFixed(1)}–'
        '${(p.endMs / 1000).toStringAsFixed(1)} s)',
        [
          // The last phase extends up to and including the last data point
          // (computePhases sets its end exactly there).
          for (final r in readings)
            if (r.timeMs >= p.startMs &&
                (r.timeMs < p.endMs ||
                    (identical(p, phases.last) && r.timeMs == p.endMs)))
              r,
        ],
        tracksTemp,
        intent: intents[p.name.toLowerCase()],
      ),
  ];
}

String _rangeLine(
  String label,
  List<ShotReading> rs,
  bool tracksTemp, {
  String? intent,
}) {
  if (rs.isEmpty) return '$label: no readings';
  String stat(String name, Iterable<double?> values, String unit) {
    final v = values.whereType<double>().toList();
    if (v.isEmpty) return '$name n/a';
    final avg = v.reduce((a, b) => a + b) / v.length;
    final max = v.reduce((a, b) => a > b ? a : b);
    return '$name avg ${_n(avg)} / max ${_n(max)} $unit';
  }

  final weights = rs.map((r) => r.weight).whereType<double>();
  final parts = [
    stat('pressure', rs.map((r) => r.pressure), 'bar'),
    stat('flow', rs.map((r) => r.flow), 'ml/s'),
    if (weights.isNotEmpty) 'weight at end ${_n(weights.last)} g',
    if (tracksTemp) stat('temp', rs.map((r) => r.barUp), '°C'),
  ];
  final measured = '$label — measured ${parts.join(', ')}';
  return intent == null ? measured : '$measured (intended: $intent)';
}

/// A stage in one sentence: what is controlled, to which setpoint, where the
/// limit is and when it ends — all variables resolved.
String stageIntent(ProfileStage st) {
  String unit(String type) => switch (type) {
    'pressure' => 'bar',
    'flow' => 'ml/s',
    'power' => '%',
    'weight' => 'g',
    'time' => 's',
    'piston_position' => 'mm',
    _ => '',
  };
  String v(double? x, String type) =>
      x == null ? '?' : '${_n(x)} ${unit(type)}'.trim();

  final u = st.type;
  final controlled = switch (u) {
    'pressure' => 'pressure-controlled',
    'flow' => 'flow-controlled',
    'power' => 'pump power-controlled',
    _ => '$u-controlled',
  };
  final ys = [for (final p in st.points) p.y];
  final String target;
  if (ys.isEmpty) {
    target = 'no target';
  } else if (st.isConstant) {
    target = 'target ${v(ys.first, u)}';
  } else {
    final over = st.over == 'time' ? 's' : unit(st.over);
    final pts = [
      for (final p in st.points)
        '${v(p.y, u)} at ${_n(p.x)}${over.isEmpty ? '' : ' $over'}',
    ];
    target = 'target ${pts.join(' → ')}';
  }
  final limits = [
    for (final l in st.limits)
      '${l.type} capped at ${v(l.value.value, l.type)}',
  ];
  final exits = [
    for (final t in st.exitTriggers)
      '${t.type} ${t.comparison} ${v(t.value.value, t.type)}'
          '${t.relative ? ' (within stage)' : ''}',
  ];
  return [
    '$controlled, $target',
    ...limits,
    exits.isEmpty
        ? 'runs until the final weight'
        : 'ends when ${exits.join(' or ')}',
  ].join('; ');
}

/// At most [perPhase] points per phase, evenly spaced, first and last point
/// of each phase always included. Retraction is dropped — only the piston
/// moves back there, it says nothing about taste.
List<ShotReading> thinReadings(
  List<ShotReading> readings, {
  int perPhase = analysisPointsPerPhase,
}) {
  final runs = <List<ShotReading>>[];
  String? current;
  for (final r in readings) {
    if (r.stage == retractionStage) continue;
    if (runs.isEmpty || r.stage != current) {
      runs.add([]);
      current = r.stage;
    }
    runs.last.add(r);
  }
  final out = <ShotReading>[];
  for (final run in runs) {
    if (run.length <= perPhase) {
      out.addAll(run);
      continue;
    }
    final step = (run.length - 1) / (perPhase - 1);
    for (var i = 0; i < perPhase; i++) {
      out.add(run[(i * step).round()]);
    }
  }
  return out;
}

/// The profile JSON without what says nothing about taste (images, authors,
/// IDs), and capped — a huge profile must not eat the whole request.
String? _compactProfile(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final m = Map<String, Object?>.from(decoded);
    for (final k in const [
      'id',
      'display',
      'author_id',
      'previous_authors',
      'last_changed',
      'isLegacy',
    ]) {
      m.remove(k);
    }
    final text = jsonEncode(m);
    return text.length > 8000
        ? '${text.substring(0, 8000)} …(truncated)'
        : text;
  } catch (_) {
    return null;
  }
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

String _n(double? v) {
  if (v == null) return '';
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}

String _g(double? v) => v == null ? 'unknown' : '${_n(v)} g';

String _date(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Gathers everything the analysis should know about a shot. Null if the
/// shot doesn't exist (anymore).
Future<ShotAnalysisInput?> loadShotAnalysisInput(
  AppDatabase db,
  int shotId,
) async {
  final entry = await db.watchShotEntry(shotId).first;
  if (entry == null) return null;
  final shot = entry.shot;
  final readings = await db.readingsFor(shotId);
  final profile = await profileJsonForShot(db, shot);
  // The bean from the entry, not shot.beanId: that may point to a deleted
  // bean (tombstone).
  final bean = entry.bean;
  final history = bean == null
      ? const <Shot>[]
      : await db.earlierShotsOfBean(
          bean.id,
          before: shot.timestamp,
          limit: analysisHistoryShots,
        );
  return ShotAnalysisInput(
    shot: shot,
    bean: bean,
    readings: readings,
    profileJson: profile.json,
    profileFromShot: profile.fromShot,
    history: history,
  );
}
