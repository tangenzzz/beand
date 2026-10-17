import 'package:flutter/foundation.dart';

// One of the user's own grinders (Settings → My Setup → Grinders). All free
// text — there is no maintained open list of grinders or burr sets to pick
// from, so suggestions come from the user's own entries.
//
// A grinder can have several burr sets (e.g. stock and SSP); exactly one is
// the one currently fitted ([activeBurrs]). Shots store the grinder name and
// the fitted burrs as text at brewing time, like the profile name — renaming
// later doesn't rewrite old shots.
@immutable
class Grinder {
  const Grinder({
    required this.id,
    required this.name,
    this.brand,
    this.burrs = const [],
    this.activeBurr,
  });

  final String id;
  // Shown in the pre-shot card on its own; [brand] only in My Setup.
  final String name;
  final String? brand;
  final List<String> burrs;
  // The fitted burr set; falls back to the first one if it was removed.
  final String? activeBurr;

  String? get activeBurrs => burrs.contains(activeBurr)
      ? activeBurr
      : (burrs.isEmpty ? null : burrs.first);

  Grinder copyWith({
    String? name,
    String? brand,
    List<String>? burrs,
    String? activeBurr,
  }) => Grinder(
    id: id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    burrs: burrs ?? this.burrs,
    activeBurr: activeBurr ?? this.activeBurr,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (brand != null) 'brand': brand,
    if (burrs.isNotEmpty) 'burrs': burrs,
    if (activeBurrs != null) 'active': activeBurrs,
  };

  /// Null for an entry that doesn't look like a grinder (e.g. from a newer
  /// app version with a different shape) — skipped instead of failing.
  static Grinder? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    final burrs = json['burrs'];
    final active = json['active'];
    final brand = json['brand'];
    return Grinder(
      id: id,
      name: name,
      brand: brand is String && brand.trim().isNotEmpty ? brand : null,
      burrs: burrs is List ? burrs.whereType<String>().toList() : const [],
      activeBurr: active is String ? active : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Grinder &&
      other.id == id &&
      other.name == name &&
      other.brand == brand &&
      listEquals(other.burrs, burrs) &&
      other.activeBurrs == activeBurrs;

  @override
  int get hashCode =>
      Object.hash(id, name, brand, Object.hashAll(burrs), activeBurrs);
}
