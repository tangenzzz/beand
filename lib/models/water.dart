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
enum Mineral {
  epsomSalt('Epsom salt', 'MgSO₄·7H₂O', gh: true),
  calciumChloride('Calcium chloride', 'CaCl₂', gh: true),
  magnesiumChloride('Magnesium chloride', 'MgCl₂·6H₂O', gh: true),
  bakingSoda('Baking soda', 'NaHCO₃', gh: false),
  potassiumBicarbonate('Potassium bicarbonate', 'KHCO₃', gh: false),
  calciumBicarbonate('Calcium bicarbonate', 'Ca(HCO₃)₂', gh: false);

  const Mineral(this.label, this.formula, {required this.gh});
  final String label;
  final String formula;
  final bool gh;

  static List<Mineral> get forGh => [
    for (final m in values)
      if (m.gh) m,
  ];
  static List<Mineral> get forKh => [
    for (final m in values)
      if (!m.gh) m,
  ];
}

// A brew water from My Setup: a recipe name plus hardness. GH and KH are in
// ppm, each with the minerals it comes from (several are common, e.g. GH
// from Epsom salt and calcium chloride).
@immutable
class Water {
  const Water({
    required this.id,
    required this.recipe,
    this.gh,
    this.ghMinerals = const {},
    this.kh,
    this.khMinerals = const {},
    this.ppm,
    this.use,
  });

  final String id;
  final String recipe;
  final double? gh;
  final Set<Mineral> ghMinerals;
  final double? kh;
  final Set<Mineral> khMinerals;
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
    ppm,
    use,
  );
}
