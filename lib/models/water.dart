import 'package:flutter/foundation.dart';

// What the water is meant for.
enum WaterUse {
  espresso('Espresso'),
  pourOver('Pour Over'),
  both('Both');

  const WaterUse(this.label);
  final String label;
}

// The salts commonly used to build coffee water — the same set
// coffeewater.app offers (Roberto Asami's "Water you doing" also names
// calcium bicarbonate). GH ones add hardness, KH ones buffer.
//
// [mgPerPpm]: milligrams of the salt per litre that add 1 ppm (as CaCO₃) of
// GH or KH — molar mass of the salt over that of CaCO₃ (100.09), per
// hardness/alkalinity equivalent. Same factors as coffeewater.app.
enum Mineral {
  epsomSalt('Epsom salt', 'MgSO₄·7H₂O', 2.4627, gh: true),
  calciumChloride('Calcium chloride', 'CaCl₂', 1.1088, gh: true),
  magnesiumChloride('Magnesium chloride', 'MgCl₂·6H₂O', 2.0312, gh: true),
  bakingSoda('Baking soda', 'NaHCO₃', 1.6787, gh: false),
  potassiumBicarbonate('Potassium bicarbonate', 'KHCO₃', 2.0006, gh: false),
  // 162.11 / 100.09: two bicarbonates per formula unit.
  calciumBicarbonate('Calcium bicarbonate', 'Ca(HCO₃)₂', 1.6197, gh: false);

  const Mineral(this.label, this.formula, this.mgPerPpm, {required this.gh});
  final String label;
  final String formula;
  final double mgPerPpm;
  final bool gh;

  /// g/L → ppm as CaCO₃ and back.
  double ppmFromGramsPerLitre(double g) => g * 1000 / mgPerPpm;
  double gramsPerLitreFromPpm(double ppm) => ppm * mgPerPpm / 1000;

  static List<Mineral> get forGh => [
    for (final m in values)
      if (m.gh) m,
  ];
  static List<Mineral> get forKh => [
    for (final m in values)
      if (!m.gh) m,
  ];
}

// How mineral amounts are entered and shown in the water form.
enum MineralUnit {
  gramsPerLitre('g/L'),
  ppm('ppm');

  const MineralUnit(this.label);
  final String label;
}

// A brew water from My Setup: a recipe name plus hardness. GH and KH are in
// ppm, each with the minerals it comes from (several are common, e.g. GH
// from Epsom salt and calcium chloride) and optionally how much of each —
// stored in g/L, shown in [unit].
@immutable
class Water {
  const Water({
    required this.id,
    required this.recipe,
    this.gh,
    this.ghMinerals = const {},
    this.kh,
    this.khMinerals = const {},
    this.amounts = const {},
    this.unit = MineralUnit.gramsPerLitre,
    this.ppm,
    this.use,
  });

  final String id;
  final String recipe;
  final double? gh;
  final Set<Mineral> ghMinerals;
  final double? kh;
  final Set<Mineral> khMinerals;
  // Grams per litre per ticked mineral (missing = not given).
  final Map<Mineral, double> amounts;
  final MineralUnit unit;
  // Total dissolved solids.
  final double? ppm;
  final WaterUse? use;

  Map<String, Object?> toJson() => {
    'id': id,
    'recipe': recipe,
    'gh': ?gh,
    if (ghMinerals.isNotEmpty)
      'ghMinerals': [for (final m in ghMinerals) m.name],
    'kh': ?kh,
    if (khMinerals.isNotEmpty)
      'khMinerals': [for (final m in khMinerals) m.name],
    if (amounts.isNotEmpty)
      'amounts': {for (final e in amounts.entries) e.key.name: e.value},
    'unit': unit.name,
    'ppm': ?ppm,
    'use': ?use?.name,
  };

  /// Null for an entry that doesn't look like a water (skipped).
  static Water? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final recipe = json['recipe'];
    if (id is! String || recipe is! String || recipe.trim().isEmpty) {
      return null;
    }
    double? number(String key) {
      final v = json[key];
      return v is num ? v.toDouble() : null;
    }

    // Unknown names (a later app version) are skipped.
    Set<Mineral> minerals(String key) {
      final v = json[key];
      if (v is! List) return const {};
      final byName = Mineral.values.asNameMap();
      return {
        for (final n in v)
          if (byName[n] != null) byName[n]!,
      };
    }

    return Water(
      id: id,
      recipe: recipe,
      gh: number('gh'),
      ghMinerals: minerals('ghMinerals'),
      kh: number('kh'),
      khMinerals: minerals('khMinerals'),
      amounts: () {
        final v = json['amounts'];
        if (v is! Map) return const <Mineral, double>{};
        final byName = Mineral.values.asNameMap();
        return {
          for (final e in v.entries)
            if (byName[e.key] != null && e.value is num)
              byName[e.key]!: (e.value as num).toDouble(),
        };
      }(),
      unit:
          MineralUnit.values.asNameMap()[json['unit']] ??
          MineralUnit.gramsPerLitre,
      ppm: number('ppm'),
      use: WaterUse.values.asNameMap()[json['use']],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Water &&
      other.id == id &&
      other.recipe == recipe &&
      other.gh == gh &&
      setEquals(other.ghMinerals, ghMinerals) &&
      other.kh == kh &&
      setEquals(other.khMinerals, khMinerals) &&
      mapEquals(other.amounts, amounts) &&
      other.unit == unit &&
      other.ppm == ppm &&
      other.use == use;

  @override
  int get hashCode => Object.hash(
    id,
    recipe,
    gh,
    Object.hashAllUnordered(ghMinerals),
    kh,
    Object.hashAllUnordered(khMinerals),
    Object.hashAllUnordered(
      amounts.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    unit,
    ppm,
    use,
  );
}
