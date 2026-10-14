import 'dart:math';

// Editable version of a Meticulous profile.
//
// Unlike [ProfileDetail] (lib/models/profile_detail.dart), this model does
// NOT resolve variables: a value is either a number or a reference "$key".
// Only then does saving produce what came in — the editor must not turn a
// variable binding into a fixed number just because the user moved a
// different point.
//
// Fields we don't know (yet) survive in [extra] and are written back out
// unchanged. This keeps editing an imported profile lossless, even if the
// machine extends its format.
//
// Field names and allowed values come from the official schema
// (github.com/MeticulousHome/espresso-profile-schema, schema.json +
// example_profile.json).

// ----------------------------------------------------------------- Constants

// What a stage can control.
const stageTypes = ['pressure', 'flow', 'power'];

// What a stage's curve runs over.
const dynamicsOverTypes = ['time', 'weight', 'piston_position'];

// The machine only knows these two. The schema also allows "none", but the
// machine hangs with it — so it isn't listed here.
const interpolationTypes = ['linear', 'curve'];

// What can end a stage.
const exitTriggerTypes = [
  'time',
  'weight',
  'pressure',
  'flow',
  'piston_position',
  'power',
  'user_interaction',
];

// Only these two quantities can be capped during a stage.
const limitTypes = ['pressure', 'flow'];

// Types a variable can have (the same six as in the schema).
const variableTypes = [
  'pressure',
  'flow',
  'power',
  'weight',
  'time',
  'piston_position',
];

// ------------------------------------------------------------------- Helpers

final _random = Random.secure();

// UUID v4. The machine requires real UUIDs for `id` and `author_id`; adding
// a package for sixteen random bytes isn't worth it.
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

double? _num(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v);
  return null;
}

// Everything except the keys we manage ourselves — so unknown fields of a
// foreign profile are preserved.
Map<String, dynamic> _rest(Map<String, dynamic> json, Set<String> known) => {
  for (final e in json.entries)
    if (!known.contains(e.key)) e.key: e.value,
};

// Fields with a leading "_" are our own notes on the draft (e.g. the
// GaggiMate's original JSON, see gaggimate_profile_codec.dart) and never go
// to a machine.
Map<String, dynamic> _public(Map<String, dynamic> extra) => {
  for (final e in extra.entries)
    if (!e.key.startsWith('_')) e.key: e.value,
};

// -------------------------------------------------------------------- Values

// A numeric value in the profile: either fixed, or bound to a variable.
class DraftValue {
  const DraftValue.number(double value) : number = value, variableKey = null;
  const DraftValue.variable(String key) : number = null, variableKey = key;

  final double? number;
  final String? variableKey;

  bool get isVariable => variableKey != null;

  // The numeric value the machine ends up using — for a binding, the
  // variable's current value.
  double? resolve(List<DraftVariable> variables) {
    if (!isVariable) return number;
    for (final v in variables) {
      if (v.key == variableKey) return v.value;
    }
    return null;
  }

  static DraftValue? tryParse(dynamic raw) {
    if (raw is String && raw.startsWith(r'$')) {
      return DraftValue.variable(raw.substring(1));
    }
    final n = _num(raw);
    return n == null ? null : DraftValue.number(n);
  }

  dynamic toJson() => isVariable ? '\$$variableKey' : number;

  @override
  bool operator ==(Object other) =>
      other is DraftValue &&
      other.number == number &&
      other.variableKey == variableKey;

  @override
  int get hashCode => Object.hash(number, variableKey);
}

// ----------------------------------------------------------------- Variables

class DraftVariable {
  DraftVariable({
    required this.name,
    required this.key,
    required this.type,
    required this.value,
  });

  // What the user sees (and what shows on the machine's dial).
  String name;

  // How stages reference it ("$key"). Must be unique within the profile.
  String key;

  // One of [variableTypes] — determines unit and value range.
  String type;
  double value;

  static const _known = {'name', 'key', 'type', 'value'};
  Map<String, dynamic> extra = {};

  factory DraftVariable.fromJson(Map<String, dynamic> json) => DraftVariable(
    name: (json['name'] ?? '').toString(),
    key: (json['key'] ?? '').toString(),
    type: (json['type'] ?? 'pressure').toString(),
    value: _num(json['value']) ?? 0,
  )..extra = _rest(json, _known);

  Map<String, dynamic> toJson() => {
    'name': name,
    'key': key,
    'type': type,
    'value': value,
    ...extra,
  };

  DraftVariable copy() =>
      DraftVariable(name: name, key: key, type: type, value: value)
        ..extra = Map.of(extra);
}

// -------------------------------------------------------------------- Stages

// A point on the curve: x = position on the axis (seconds for
// `over: time`), y = target value.
class DraftPoint {
  DraftPoint(this.x, this.y);

  DraftValue x;
  DraftValue y;

  DraftPoint copy() => DraftPoint(x, y);
}

// Condition that advances to the next stage.
class DraftTrigger {
  DraftTrigger({
    required this.type,
    required this.value,
    this.relative = false,
    this.comparison = '>=',
  });

  // One of [exitTriggerTypes].
  String type;
  DraftValue value;

  // Counts from the start of the stage instead of the start of the shot.
  // The field must always be written — the machine expects it.
  bool relative;

  // Only '>=' or '<='.
  String comparison;

  static const _known = {'type', 'value', 'relative', 'comparison'};
  Map<String, dynamic> extra = {};

  // `user_interaction` waits for the dial and carries no value.
  bool get needsValue => type != 'user_interaction';

  factory DraftTrigger.fromJson(Map<String, dynamic> json) {
    final value = DraftValue.tryParse(json['value']);
    return DraftTrigger(
      type: (json['type'] ?? '').toString(),
      value: value ?? const DraftValue.number(0),
      relative: json['relative'] == true,
      comparison: (json['comparison'] ?? '>=').toString(),
    )..extra = _rest(json, _known);
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value.toJson(),
    'relative': relative,
    'comparison': comparison,
    ...extra,
  };

  DraftTrigger copy() => DraftTrigger(
    type: type,
    value: value,
    relative: relative,
    comparison: comparison,
  )..extra = Map.of(extra);
}

// Cap for pressure or flow that applies during the whole stage.
class DraftLimit {
  DraftLimit({required this.type, required this.value});

  String type;
  DraftValue value;

  static const _known = {'type', 'value'};
  Map<String, dynamic> extra = {};

  static DraftLimit? fromJson(Map<String, dynamic> json) {
    final value = DraftValue.tryParse(json['value']);
    if (value == null) return null;
    return DraftLimit(type: (json['type'] ?? '').toString(), value: value)
      ..extra = _rest(json, _known);
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value.toJson(),
    ...extra,
  };

  DraftLimit copy() =>
      DraftLimit(type: type, value: value)..extra = Map.of(extra);
}

class DraftStage {
  DraftStage({
    required this.name,
    required this.key,
    required this.type,
    required this.points,
    this.over = 'time',
    this.interpolation = 'linear',
    List<DraftTrigger>? exitTriggers,
    List<DraftLimit>? limits,
    this.temperatureDelta,
  }) : exitTriggers = exitTriggers ?? [],
       limits = limits ?? [];

  String name;

  // Unique key within the profile. Required in the schema — without it the
  // machine rejects the profile.
  String key;

  // One of [stageTypes].
  String type;
  List<DraftPoint> points;
  String over;
  String interpolation;
  List<DraftTrigger> exitTriggers;

  // Must always be written as an array, even empty — the machine can't
  // handle null.
  List<DraftLimit> limits;

  // Offset from the profile temperature for this one stage.
  double? temperatureDelta;

  static const _known = {
    'name',
    'key',
    'type',
    'dynamics',
    'exit_triggers',
    'limits',
    'temperature_delta',
  };
  Map<String, dynamic> extra = {};
  Map<String, dynamic> dynamicsExtra = {};

  // The unit this stage's curve is measured in.
  String get valueType => type;

  factory DraftStage.fromJson(Map<String, dynamic> json) {
    final dynamics = json['dynamics'] is Map
        ? Map<String, dynamic>.from(json['dynamics'] as Map)
        : const <String, dynamic>{};

    final points = <DraftPoint>[];
    for (final p in (dynamics['points'] as List? ?? const [])) {
      if (p is! List || p.length < 2) continue;
      final x = DraftValue.tryParse(p[0]);
      final y = DraftValue.tryParse(p[1]);
      if (x != null && y != null) points.add(DraftPoint(x, y));
    }

    return DraftStage(
        name: (json['name'] ?? '').toString(),
        key: (json['key'] ?? '').toString(),
        type: (json['type'] ?? 'pressure').toString(),
        points: points,
        over: (dynamics['over'] ?? 'time').toString(),
        interpolation: (dynamics['interpolation'] ?? 'linear').toString(),
        exitTriggers: [
          for (final t in (json['exit_triggers'] as List? ?? const []))
            if (t is Map) DraftTrigger.fromJson(Map<String, dynamic>.from(t)),
        ],
        limits: [
          for (final l in (json['limits'] as List? ?? const []))
            if (l is Map) ?DraftLimit.fromJson(Map<String, dynamic>.from(l)),
        ],
        temperatureDelta: _num(json['temperature_delta']),
      )
      ..extra = _rest(json, _known)
      ..dynamicsExtra = _rest(dynamics, {'points', 'over', 'interpolation'});
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'key': key,
    'type': type,
    'dynamics': {
      'points': [
        for (final p in points) [p.x.toJson(), p.y.toJson()],
      ],
      'over': over,
      'interpolation': interpolation,
      ...dynamicsExtra,
    },
    'exit_triggers': [for (final t in exitTriggers) t.toJson()],
    'limits': [for (final l in limits) l.toJson()],
    if (temperatureDelta != null) 'temperature_delta': temperatureDelta,
    ..._public(extra),
  };

  DraftStage copy() =>
      DraftStage(
          name: name,
          key: key,
          type: type,
          points: [for (final p in points) p.copy()],
          over: over,
          interpolation: interpolation,
          exitTriggers: [for (final t in exitTriggers) t.copy()],
          limits: [for (final l in limits) l.copy()],
          temperatureDelta: temperatureDelta,
        )
        ..extra = Map.of(extra)
        ..dynamicsExtra = Map.of(dynamicsExtra);

  // Highest target value of the curve — for the rule "pressure stage from
  // 6 bar needs a flow limit". Returns null if no point can be resolved.
  double? maxValue(List<DraftVariable> variables) {
    double? best;
    for (final p in points) {
      final v = p.y.resolve(variables);
      if (v == null) continue;
      if (best == null || v > best) best = v;
    }
    return best;
  }

  bool hasLimit(String type) => limits.any((l) => l.type == type);
}

// ------------------------------------------------------------------- Profile

class PreviousAuthor {
  PreviousAuthor({
    required this.name,
    required this.authorId,
    required this.profileId,
  });

  final String name;
  final String authorId;
  final String profileId;

  factory PreviousAuthor.fromJson(Map<String, dynamic> json) => PreviousAuthor(
    name: (json['name'] ?? '').toString(),
    authorId: (json['author_id'] ?? '').toString(),
    profileId: (json['profile_id'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'author_id': authorId,
    'profile_id': profileId,
  };
}

class ProfileDraft {
  ProfileDraft({
    required this.id,
    required this.name,
    required this.author,
    required this.authorId,
    required this.temperature,
    required this.finalWeight,
    List<DraftVariable>? variables,
    List<DraftStage>? stages,
    List<PreviousAuthor>? previousAuthors,
    this.version,
    this.image,
    this.accentColor = '#C8793F',
    this.shortDescription,
    this.description,
  }) : variables = variables ?? [],
       stages = stages ?? [],
       previousAuthors = previousAuthors ?? [];

  String id;
  String name;
  String author;
  String authorId;
  int? version;
  double temperature;
  double finalWeight;

  // display.*
  String? image;
  String accentColor;
  String? shortDescription;
  String? description;

  List<PreviousAuthor> previousAuthors;

  // Must always be written, even empty: otherwise the Meticulous app
  // crashes when you try to add a variable there.
  List<DraftVariable> variables;
  List<DraftStage> stages;

  static const _known = {
    'id',
    'name',
    'author',
    'author_id',
    'version',
    'temperature',
    'final_weight',
    'display',
    'previous_authors',
    'variables',
    'stages',
  };
  Map<String, dynamic> extra = {};
  Map<String, dynamic> displayExtra = {};

  // A fresh, empty profile with a first stage, so the editor doesn't start
  // on an empty page.
  factory ProfileDraft.empty({String author = 'bean\'d'}) => ProfileDraft(
    id: newUuid(),
    name: '',
    author: author,
    authorId: newUuid(),
    temperature: 92,
    finalWeight: 40,
    stages: [defaultStage(1, 'pressure')],
  );

  // A new stage with sensible starting values: a flat curve and a time
  // trigger so it doesn't run forever. The editor adds the limits via the
  // rule check.
  static DraftStage defaultStage(int number, String type) {
    final start = switch (type) {
      'flow' => 2.0,
      'power' => 50.0,
      _ => 6.0,
    };
    return DraftStage(
      name: switch (type) {
        'flow' => 'Flow',
        'power' => 'Power',
        _ => 'Pressure',
      },
      key: 'stage_$number',
      type: type,
      points: [
        DraftPoint(const DraftValue.number(0), DraftValue.number(start)),
        DraftPoint(const DraftValue.number(30), DraftValue.number(start)),
      ],
      exitTriggers: [
        DraftTrigger(
          type: 'time',
          value: const DraftValue.number(30),
          relative: true,
        ),
      ],
      limits: [
        if (type == 'pressure')
          DraftLimit(type: 'flow', value: const DraftValue.number(5)),
        if (type == 'flow')
          DraftLimit(type: 'pressure', value: const DraftValue.number(10)),
      ],
    );
  }

  factory ProfileDraft.fromJson(Map<String, dynamic> json) {
    final display = json['display'] is Map
        ? Map<String, dynamic>.from(json['display'] as Map)
        : const <String, dynamic>{};

    String? clean(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return ProfileDraft(
        id: clean(json['id']) ?? newUuid(),
        name: (json['name'] ?? '').toString(),
        author: (json['author'] ?? '').toString(),
        authorId: clean(json['author_id']) ?? newUuid(),
        version: _num(json['version'])?.toInt(),
        temperature: _num(json['temperature']) ?? 92,
        finalWeight: _num(json['final_weight']) ?? 40,
        image: clean(display['image']),
        accentColor: clean(display['accentColor']) ?? '#C8793F',
        shortDescription: clean(display['shortDescription']),
        description: clean(display['description']),
        previousAuthors: [
          for (final a in (json['previous_authors'] as List? ?? const []))
            if (a is Map) PreviousAuthor.fromJson(Map<String, dynamic>.from(a)),
        ],
        variables: [
          for (final v in (json['variables'] as List? ?? const []))
            if (v is Map) DraftVariable.fromJson(Map<String, dynamic>.from(v)),
        ],
        stages: [
          for (final s in (json['stages'] as List? ?? const []))
            if (s is Map) DraftStage.fromJson(Map<String, dynamic>.from(s)),
        ],
      )
      ..extra = _rest(json, _known)
      ..displayExtra = _rest(display, {
        'image',
        'accentColor',
        'shortDescription',
        'description',
      });
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'author_id': authorId,
    if (version != null) 'version': version,
    'temperature': temperature,
    'final_weight': finalWeight,
    'display': {
      if (image != null) 'image': image,
      'accentColor': accentColor,
      if (shortDescription != null) 'shortDescription': shortDescription,
      if (description != null) 'description': description,
      ...displayExtra,
    },
    if (previousAuthors.isNotEmpty)
      'previous_authors': [for (final a in previousAuthors) a.toJson()],
    'variables': [for (final v in variables) v.toJson()],
    'stages': [for (final s in stages) s.toJson()],
    ..._public(extra),
  };

  ProfileDraft copy() =>
      ProfileDraft(
          id: id,
          name: name,
          author: author,
          authorId: authorId,
          version: version,
          temperature: temperature,
          finalWeight: finalWeight,
          image: image,
          accentColor: accentColor,
          shortDescription: shortDescription,
          description: description,
          previousAuthors: List.of(previousAuthors),
          variables: [for (final v in variables) v.copy()],
          stages: [for (final s in stages) s.copy()],
        )
        ..extra = Map.of(extra)
        ..displayExtra = Map.of(displayExtra);

  // A key that doesn't exist in the profile yet.
  String freeStageKey() {
    final used = stages.map((s) => s.key).toSet();
    for (var i = 1; i < 1000; i++) {
      if (!used.contains('stage_$i')) return 'stage_$i';
    }
    return 'stage_${newUuid()}';
  }

  String freeVariableKey(String type) {
    final used = variables.map((v) => v.key).toSet();
    for (var i = 1; i < 1000; i++) {
      if (!used.contains('${type}_$i')) return '${type}_$i';
    }
    return '${type}_${newUuid()}';
  }

  // Is a variable still used anywhere? Determines whether unbinding is
  // worth reporting.
  bool usesVariable(String key) {
    for (final stage in stages) {
      for (final p in stage.points) {
        if (p.x.variableKey == key || p.y.variableKey == key) return true;
      }
      for (final t in stage.exitTriggers) {
        if (t.value.variableKey == key) return true;
      }
      for (final l in stage.limits) {
        if (l.value.variableKey == key) return true;
      }
    }
    return false;
  }
}
