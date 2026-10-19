import 'package:flutter/foundation.dart';

import 'grind_scale.dart';

// One of the user's own grinders (My Coffee Desk → Grinders). All free
// text — there is no maintained open list of grinders or burr sets to pick
// from, so suggestions come from the user's own entries.
//
// A grinder can have several burr sets (e.g. stock and SSP); exactly one is
// the one currently fitted ([activeBurrs]). Shots store the grinder name and
// the fitted burrs as text at brewing time, like the profile name — renaming
// later doesn't rewrite old shots.
//
// [scale] says how the dial is read (unit, step, range) — the grind ruler
// follows it. [zeros] is the zero point per burr set ('' = before any burrs
// were named), with its history: each re-zeroing adds an entry.
@immutable
class Grinder {
  const Grinder({
    required this.id,
    required this.name,
    this.brand,
    this.burrs = const [],
    this.activeBurr,
    this.hand = false,
    this.scale,
    this.zeros = const {},
  });

  final String id;
  // Shown in the pre-shot card on its own; [brand] only on the desk.
  final String name;
  final String? brand;
  final List<String> burrs;
  // The fitted burr set; falls back to the first one if it was removed.
  final String? activeBurr;

  /// A hand grinder (else electric) — picks the icon.
  final bool hand;

  /// Null = not set; the ruler then works as before (0–20 in 0.1).
  final GrindScale? scale;

  /// Zero point history per burr set, oldest first.
  final Map<String, List<ZeroPoint>> zeros;

  String? get activeBurrs => burrs.contains(activeBurr)
      ? activeBurr
      : (burrs.isEmpty ? null : burrs.first);

  GrindScale get scaleOrStandard => scale ?? GrindScale.standard;

  /// The zero point of the fitted burrs now: their own last setting, else
  /// the one set before any burrs were named; null = never set (= 0).
  ZeroPoint? get zeroPoint =>
      zeros[activeBurrs ?? '']?.lastOrNull ?? zeros['']?.lastOrNull;

  /// The setting relative to the burrs' touch point.
  double effective(double dial) => dial - (zeroPoint?.value ?? 0);

  /// Adds a re-zeroing of the fitted burrs (unchanged value: nothing).
  Grinder withZero(double value, DateTime at) {
    if (zeroPoint?.value == value && zeros.containsKey(activeBurrs ?? '')) {
      return this;
    }
    final key = activeBurrs ?? '';
    return copyWith(
      zeros: {
        ...zeros,
        key: [...?zeros[key], ZeroPoint(value, at)],
      },
    );
  }

  Grinder copyWith({
    String? name,
    String? brand,
    List<String>? burrs,
    String? activeBurr,
    bool? hand,
    GrindScale? scale,
    bool clearScale = false,
    Map<String, List<ZeroPoint>>? zeros,
  }) => Grinder(
    id: id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    burrs: burrs ?? this.burrs,
    activeBurr: activeBurr ?? this.activeBurr,
    hand: hand ?? this.hand,
    scale: clearScale ? null : (scale ?? this.scale),
    zeros: zeros ?? this.zeros,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (brand != null) 'brand': brand,
    if (burrs.isNotEmpty) 'burrs': burrs,
    if (activeBurrs != null) 'active': activeBurrs,
    ...extrasToJson(),
  };

  /// What the grinder adds to the plain gear fields (stored in its specs).
  Map<String, Object> extrasToJson() => {
    if (hand) 'shape': 'hand',
    if (scale != null) 'scale': scale!.toJson(),
    if (zeros.isNotEmpty)
      'zeros': {
        for (final e in zeros.entries)
          e.key: [for (final z in e.value) z.toJson()],
      },
  };

  static bool handOf(Object? shape) => shape == 'hand';

  static Map<String, List<ZeroPoint>> zerosOf(Object? json) => json is Map
      ? {
          for (final e in json.entries)
            if (e.key is String && e.value is List)
              e.key as String: [
                for (final z in e.value as List) ?ZeroPoint.fromJson(z),
              ],
        }
      : const {};

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
      hand: handOf(json['shape']),
      scale: GrindScale.fromJson(json['scale']),
      zeros: zerosOf(json['zeros']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Grinder &&
      other.id == id &&
      other.name == name &&
      other.brand == brand &&
      listEquals(other.burrs, burrs) &&
      other.activeBurrs == activeBurrs &&
      other.hand == hand &&
      other.scale == scale &&
      mapEquals(
        {for (final e in other.zeros.entries) e.key: e.value.length},
        {for (final e in zeros.entries) e.key: e.value.length},
      ) &&
      other.zeroPoint == zeroPoint;

  @override
  int get hashCode =>
      Object.hash(id, name, brand, Object.hashAll(burrs), activeBurrs, scale);
}
