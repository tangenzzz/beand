import 'dart:convert';

import 'package:flutter/foundation.dart';

// The user's equipment on "My Coffee Desk": one shape for every kind of
// gear, so the desk, sync and backup handle grinders, kettles and water
// alike. Type-specific facts (burrs, dose, GH …) live in [Gear.specs] as
// plain JSON values, so a new field never needs a new model.
//
// Whether a piece is in use is NOT stored: a [BrewChain] lists gear IDs, and
// everything no active chain uses counts as stored ([activeGearIds]).

enum BrewMode {
  espresso('Espresso'),
  pourOver('Pour over');

  const BrewMode(this.label);
  final String label;
}

enum GearType {
  grinder('Grinders', 'Grinder', 'grinder_electric'),
  machine('Machines', 'Machine', 'espresso_machine'),
  basket('Baskets', 'Basket', 'basket'),
  tamper('Tampers', 'Tamper', 'tamper'),
  brewer('Brewers', 'Brewer', 'dripper_cone'),
  filter('Filters', 'Filter', 'filter_paper'),
  kettle('Kettles', 'Kettle', 'kettle'),
  scale('Scales', 'Scale', 'scale'),
  water('Water', 'Water', 'water');

  const GearType(this.label, this.single, this._icon);

  /// Section name on the desk.
  final String label;

  /// One piece, e.g. "Add grinder".
  final String single;
  final String _icon;

  /// Line icon in assets/icons/gear/. Some types pick a variant from the
  /// specs: a hand grinder, a flat-bottom dripper or a press.
  String iconAsset(Map<String, Object?> specs) {
    final variant = switch ((this, specs['shape'])) {
      (GearType.grinder, 'hand') => 'grinder_hand',
      (GearType.brewer, 'flat') => 'dripper_flat',
      (GearType.brewer, 'press') => 'press',
      _ => _icon,
    };
    return 'assets/icons/gear/$variant.svg';
  }
}

@immutable
class Gear {
  const Gear({
    required this.id,
    required this.type,
    required this.model,
    this.brand,
    this.brewModes = const {BrewMode.espresso, BrewMode.pourOver},
    this.photoPath,
    this.photoOriginalPath,
    this.specs = const {},
    this.stock,
  });

  final String id;
  final GearType type;
  final String? brand;
  final String model;
  final Set<BrewMode> brewModes;
  final String? photoPath;

  /// Set when [photoPath] is a cut-out (transparent PNG that stands freely
  /// on the shelf): the photo it was cut from, to go back to.
  final String? photoOriginalPath;

  bool get isCutout => photoPath != null && photoOriginalPath != null;

  /// Type-specific values, JSON-safe (strings, numbers, lists).
  final Map<String, Object?> specs;

  /// Consumables on hand, e.g. paper filters.
  final int? stock;

  bool usedFor(BrewMode mode) => brewModes.contains(mode);

  /// One line for "Brewed with": brand and model, a grinder's fitted burrs
  /// in brackets.
  String get label {
    final name = [?brand, model].join(' ');
    final burrs = type == GearType.grinder ? specs['activeBurr'] : null;
    return burrs is String && burrs.isNotEmpty ? '$name ($burrs)' : name;
  }

  Gear withId(String id) => Gear(
    id: id,
    type: type,
    model: model,
    brand: brand,
    brewModes: brewModes,
    photoPath: photoPath,
    photoOriginalPath: photoOriginalPath,
    specs: specs,
    stock: stock,
  );

  /// [clearPhoto] removes both photos; a new [photoPath] without
  /// [photoOriginalPath] is a plain photo.
  Gear copyWith({
    String? photoPath,
    String? photoOriginalPath,
    bool clearPhoto = false,
    Map<String, Object?>? specs,
  }) => Gear(
    id: id,
    type: type,
    model: model,
    brand: brand,
    brewModes: brewModes,
    photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    photoOriginalPath: clearPhoto
        ? null
        : (photoPath != null ? photoOriginalPath : this.photoOriginalPath),
    specs: specs ?? this.specs,
    stock: stock,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'model': model,
    if (brand != null) 'brand': brand,
    'modes': [for (final m in brewModes) m.name],
    if (photoPath != null) 'photo': photoPath,
    if (photoOriginalPath != null) 'photoOriginal': photoOriginalPath,
    if (specs.isNotEmpty) 'specs': specs,
    if (stock != null) 'stock': stock,
  };

  /// Null for anything that doesn't look like gear (e.g. a type from a newer
  /// app version) — skipped instead of failing, as with grinders.
  static Gear? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final model = json['model'];
    final type = GearType.values.asNameMap()[json['type']];
    if (id is! String || model is! String || type == null) return null;
    final modes = json['modes'];
    final specs = json['specs'];
    final brand = json['brand'];
    final photo = json['photo'];
    final original = json['photoOriginal'];
    final stock = json['stock'];
    return Gear(
      id: id,
      type: type,
      model: model,
      brand: brand is String && brand.trim().isNotEmpty ? brand : null,
      brewModes: modes is List
          ? {for (final m in modes) ?BrewMode.values.asNameMap()[m]}
          : const {BrewMode.espresso, BrewMode.pourOver},
      photoPath: photo is String ? photo : null,
      photoOriginalPath: original is String ? original : null,
      specs: specs is Map ? Map<String, Object?>.from(specs) : const {},
      stock: stock is num ? stock.toInt() : null,
    );
  }

  // Compared through the JSON so nested specs (lists, maps) count too.
  @override
  bool operator ==(Object other) =>
      other is Gear && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

// A set of gear used together for one way of brewing, e.g. "Espresso bar":
// machine, grinder, basket, tamper, scale, water. Only IDs — renaming a
// piece of gear never touches the chain.
@immutable
class BrewChain {
  const BrewChain({
    required this.id,
    required this.name,
    required this.gearIds,
  });

  final String id;
  final String name;
  final List<String> gearIds;

  // An "active" flag (chain put away) existed until 2026-10-19; old data
  // may still carry it and it is ignored — being in a chain means in use.
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'gear': gearIds};

  static BrewChain? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final gear = json['gear'];
    if (id is! String || name is! String) return null;
    return BrewChain(
      id: id,
      name: name,
      gearIds: gear is List ? gear.whereType<String>().toList() : const [],
    );
  }

  BrewChain copyWith({String? name, List<String>? gearIds}) => BrewChain(
    id: id,
    name: name ?? this.name,
    gearIds: gearIds ?? this.gearIds,
  );

  @override
  bool operator ==(Object other) =>
      other is BrewChain &&
      other.id == id &&
      other.name == name &&
      listEquals(other.gearIds, gearIds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(gearIds));
}

/// IDs of the gear some chain uses — in use; everything else is stored.
Set<String> activeGearIds(Iterable<BrewChain> chains) => {
  for (final c in chains) ...c.gearIds,
};
