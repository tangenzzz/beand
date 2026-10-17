import 'package:flutter/foundation.dart';

// What the water is meant for.
enum WaterUse {
  espresso('Espresso'),
  pourOver('Pour Over'),
  both('Both');

  const WaterUse(this.label);
  final String label;
}

// A brew water from My Setup: a recipe name plus hardness. GH and KH are in
// ppm, each with where it comes from (e.g. GH from Epsom salt, KH from
// baking soda) — free text with suggestions from the user's own entries.
@immutable
class Water {
  const Water({
    required this.id,
    required this.recipe,
    this.gh,
    this.ghSource,
    this.kh,
    this.khSource,
    this.ppm,
    this.use,
  });

  final String id;
  final String recipe;
  final double? gh;
  final String? ghSource;
  final double? kh;
  final String? khSource;
  // Total dissolved solids.
  final double? ppm;
  final WaterUse? use;

  Map<String, Object?> toJson() => {
    'id': id,
    'recipe': recipe,
    'gh': ?gh,
    'ghSource': ?ghSource,
    'kh': ?kh,
    'khSource': ?khSource,
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

    String? text(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    return Water(
      id: id,
      recipe: recipe,
      gh: number('gh'),
      ghSource: text('ghSource'),
      kh: number('kh'),
      khSource: text('khSource'),
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
      other.ghSource == ghSource &&
      other.kh == kh &&
      other.khSource == khSource &&
      other.ppm == ppm &&
      other.use == use;

  @override
  int get hashCode =>
      Object.hash(id, recipe, gh, ghSource, kh, khSource, ppm, use);
}
