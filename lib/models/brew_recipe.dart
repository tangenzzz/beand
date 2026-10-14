// Pour-over recipes from HotThoughts/brew-recipes (CC0 1.0).
//
// Validation mirrors the repo's `schema.yaml`: required fields, enums,
// value ranges. A recipe that fails is skipped — so a broken update from
// GitHub can never break the app.

const brewRecipesRepo = 'HotThoughts/brew-recipes';

const brewRecipeBrewers = {
  'V60',
  'Chemex',
  'Aeropress',
  'ColdBrew',
  'Kalita',
  'Orea',
  'FrenchPress',
  'StaggX',
  'Origami',
  'April',
  'Other',
};

const brewRecipeGrindSizes = [
  'extra-coarse',
  'coarse',
  'medium-coarse',
  'medium',
  'medium-fine',
  'fine',
  'extra-fine',
];

const _brewTemperatures = {
  'cold',
  'room-temperature',
  'cold-or-room-temperature',
};
final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _ratioPattern = RegExp(r'^1:\d+(\.\d+)?$');

class BrewRecipeFormatException implements Exception {
  BrewRecipeFormatException(this.message);
  final String message;
  @override
  String toString() => 'BrewRecipeFormatException: $message';
}

/// A phase as written in the recipe. With `pours`, [waterG] is the amount
/// PER partial pour.
class BrewPhase {
  const BrewPhase({
    required this.label,
    required this.waterG,
    this.waitSeconds,
    this.pours,
    this.note,
  });

  final String label;
  final double waterG;
  final double? waitSeconds;
  final int? pours;
  final String? note;

  double get totalWaterG => waterG * (pours ?? 1);

  Map<String, dynamic> toJson() => {
    'label': label,
    'water_g': waterG,
    if (waitSeconds != null) 'wait_seconds': waitSeconds,
    if (pours != null) 'pours': pours,
    if (note != null) 'note': note,
  };
}

/// A single pour as the live brew works through it: partial pours are
/// expanded, [targetTotalG] is the scale reading after this pour.
class BrewStep {
  const BrewStep({
    required this.label,
    required this.waterG,
    required this.targetTotalG,
    this.waitSeconds,
    this.note,
  });

  final String label;
  final double waterG;
  final double targetTotalG;
  final double? waitSeconds;
  final String? note;

  double get startTotalG => targetTotalG - waterG;
}

class BrewRecipe {
  const BrewRecipe({
    required this.id,
    required this.name,
    required this.brewer,
    required this.doseG,
    required this.waterMl,
    required this.grindSize,
    required this.phases,
    required this.sourceName,
    this.ratio,
    this.variant,
    this.paperFilter,
    this.waterTempC,
    this.brewTemperature,
    this.description,
    this.sourceUrl,
    this.competition,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String brewer;
  final double doseG;
  final double waterMl;
  final String? ratio;
  final String? variant;
  final String? paperFilter;
  final double? waterTempC;
  final String? brewTemperature;
  final String grindSize;
  final String? description;
  final List<BrewPhase> phases;
  final String sourceName;
  final String? sourceUrl;
  final String? competition;
  final List<String> tags;

  /// Ratio as a number (1:15 → 15). If missing in the recipe, from water/dose.
  double get ratioValue {
    final r = ratio;
    if (r != null) return double.parse(r.substring(2));
    return waterMl / doseG;
  }

  List<BrewStep> get steps {
    final out = <BrewStep>[];
    var total = 0.0;
    for (final p in phases) {
      final n = p.pours ?? 1;
      for (var i = 0; i < n; i++) {
        total += p.waterG;
        out.add(
          BrewStep(
            label: n > 1 ? '${p.label} ${i + 1}/$n' : p.label,
            waterG: p.waterG,
            targetTotalG: total,
            waitSeconds: p.waitSeconds,
            note: p.note,
          ),
        );
      }
    }
    return out;
  }

  /// Water according to the pours; may differ from [waterMl] (e.g. bypass).
  double get stepsWaterG => phases.fold(0.0, (s, p) => s + p.totalWaterG);

  /// Validates against the schema; throws [BrewRecipeFormatException].
  factory BrewRecipe.fromJson(Map<String, dynamic> j) {
    const known = {
      'id',
      'name',
      'brewer',
      'dose_g',
      'water_ml',
      'ratio',
      'variant',
      'paper_filter',
      'water_temp_c',
      'brew_temperature',
      'grind_size',
      'description',
      'phases',
      'source',
      'tags',
    };
    for (final k in j.keys) {
      if (!known.contains(k)) {
        throw BrewRecipeFormatException('unknown field $k');
      }
    }
    final id = _str(j, 'id');
    if (!_idPattern.hasMatch(id)) throw BrewRecipeFormatException('bad id $id');
    final brewer = _str(j, 'brewer');
    if (!brewRecipeBrewers.contains(brewer)) {
      throw BrewRecipeFormatException('bad brewer $brewer');
    }
    final dose = _num(j, 'dose_g', min: 5, max: 120)!;
    final water = _num(j, 'water_ml', min: 50, max: 1200)!;
    final ratio = _optStr(j, 'ratio');
    if (ratio != null && !_ratioPattern.hasMatch(ratio)) {
      throw BrewRecipeFormatException('bad ratio $ratio');
    }
    final paper = _optStr(j, 'paper_filter');
    if (paper != null && paper != 'cone' && paper != 'wave') {
      throw BrewRecipeFormatException('bad paper_filter $paper');
    }
    final temp = _num(j, 'water_temp_c', min: 80, max: 100, optional: true);
    final brewTemp = _optStr(j, 'brew_temperature');
    if (brewTemp != null && !_brewTemperatures.contains(brewTemp)) {
      throw BrewRecipeFormatException('bad brew_temperature $brewTemp');
    }
    if (temp == null && brewTemp == null) {
      throw BrewRecipeFormatException('needs water_temp_c or brew_temperature');
    }
    final grind = _str(j, 'grind_size');
    if (!brewRecipeGrindSizes.contains(grind)) {
      throw BrewRecipeFormatException('bad grind_size $grind');
    }

    final rawPhases = j['phases'];
    if (rawPhases is! List || rawPhases.isEmpty || rawPhases.length > 10) {
      throw BrewRecipeFormatException('phases must have 1–10 entries');
    }
    final phases = <BrewPhase>[];
    for (final p in rawPhases) {
      if (p is! Map) throw BrewRecipeFormatException('phase is not an object');
      final m = Map<String, dynamic>.from(p);
      for (final k in m.keys) {
        if (!const {
          'label',
          'water_g',
          'wait_seconds',
          'pours',
          'note',
        }.contains(k)) {
          throw BrewRecipeFormatException('unknown phase field $k');
        }
      }
      final pours = m['pours'];
      if (pours != null && (pours is! int || pours < 1 || pours > 10)) {
        throw BrewRecipeFormatException('bad pours $pours');
      }
      phases.add(
        BrewPhase(
          label: _str(m, 'label'),
          waterG: _num(m, 'water_g', min: 0)!,
          waitSeconds: _num(
            m,
            'wait_seconds',
            min: 0,
            max: 86400,
            optional: true,
          ),
          pours: pours as int?,
          note: _optStr(m, 'note'),
        ),
      );
    }

    final source = j['source'];
    if (source is! Map) throw BrewRecipeFormatException('source missing');
    final src = Map<String, dynamic>.from(source);
    for (final k in src.keys) {
      if (!const {'name', 'url', 'competition'}.contains(k)) {
        throw BrewRecipeFormatException('unknown source field $k');
      }
    }

    final rawTags = j['tags'];
    if (rawTags != null && rawTags is! List) {
      throw BrewRecipeFormatException('bad tags');
    }

    return BrewRecipe(
      id: id,
      name: _str(j, 'name'),
      brewer: brewer,
      doseG: dose,
      waterMl: water,
      ratio: ratio,
      variant: _optStr(j, 'variant'),
      paperFilter: paper,
      waterTempC: temp,
      brewTemperature: brewTemp,
      grindSize: grind,
      description: _optStr(j, 'description')?.trim(),
      phases: phases,
      sourceName: _str(src, 'name'),
      sourceUrl: _optStr(src, 'url'),
      competition: _optStr(src, 'competition'),
      tags: [for (final t in (rawTags as List?) ?? const []) t.toString()],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brewer': brewer,
    'dose_g': doseG,
    'water_ml': waterMl,
    if (ratio != null) 'ratio': ratio,
    if (variant != null) 'variant': variant,
    if (paperFilter != null) 'paper_filter': paperFilter,
    if (waterTempC != null) 'water_temp_c': waterTempC,
    if (brewTemperature != null) 'brew_temperature': brewTemperature,
    'grind_size': grindSize,
    if (description != null) 'description': description,
    'phases': [for (final p in phases) p.toJson()],
    'source': {
      'name': sourceName,
      if (sourceUrl != null) 'url': sourceUrl,
      if (competition != null) 'competition': competition,
    },
    if (tags.isNotEmpty) 'tags': tags,
  };
}

/// Validates a list of raw recipes; invalid ones and duplicate IDs are dropped.
({List<BrewRecipe> recipes, List<String> rejected}) parseBrewRecipes(
  Iterable<Map<String, dynamic>> raw,
) {
  final recipes = <BrewRecipe>[];
  final rejected = <String>[];
  final ids = <String>{};
  for (final r in raw) {
    try {
      final recipe = BrewRecipe.fromJson(r);
      if (!ids.add(recipe.id)) {
        rejected.add('${recipe.id}: duplicate id');
        continue;
      }
      recipes.add(recipe);
    } on BrewRecipeFormatException catch (e) {
      rejected.add('${r['id'] ?? '?'}: ${e.message}');
    }
  }
  return (recipes: recipes, rejected: rejected);
}

String _str(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is! String || v.isEmpty) {
    throw BrewRecipeFormatException('$key missing');
  }
  return v;
}

String? _optStr(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! String) throw BrewRecipeFormatException('$key is not a string');
  return v;
}

double? _num(
  Map<String, dynamic> m,
  String key, {
  double? min,
  double? max,
  bool optional = false,
}) {
  final v = m[key];
  if (v == null) {
    if (optional) return null;
    throw BrewRecipeFormatException('$key missing');
  }
  if (v is! num) throw BrewRecipeFormatException('$key is not a number');
  final d = v.toDouble();
  if ((min != null && d < min) || (max != null && d > max)) {
    throw BrewRecipeFormatException('$key out of range: $d');
  }
  return d;
}
