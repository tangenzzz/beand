import 'package:flutter/foundation.dart';

import '../database/sync_ids.dart';
import '../models/gear.dart';
import '../models/grinder.dart';
import 'gear_store.dart';

// The user's grinders — a view on the grinders in [GearStore] (My Coffee
// Desk), with the shape the pre-shot card and the grinder dialog know.
// Which grinder is in use is chosen per machine (ShotSetup, by ID).
class GrinderStore extends ChangeNotifier {
  GrinderStore(this.gear) : _grinders = _read(gear) {
    gear.addListener(_gearChanged);
  }

  /// Without prefs (tests): in memory only.
  factory GrinderStore.inMemory([List<Grinder> grinders = const []]) =>
      GrinderStore(
        GearStore.inMemory(
          gear: [for (final g in grinders) gearFromGrinder(g)],
        ),
      );

  final GearStore gear;
  List<Grinder> _grinders;

  static List<Grinder> _read(GearStore gear) => [
    for (final g in gear.ofType(GearType.grinder)) grinderFromGear(g),
  ];

  void _gearChanged() {
    final fresh = _read(gear);
    if (listEquals(fresh, _grinders)) return;
    _grinders = fresh;
    notifyListeners();
  }

  @override
  void dispose() {
    gear.removeListener(_gearChanged);
    super.dispose();
  }

  List<Grinder> get grinders => List.unmodifiable(_grinders);

  Grinder? byId(String? id) {
    if (id == null) return null;
    for (final g in _grinders) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Burr sets already used on any grinder — suggestions for the form.
  List<String> get burrSuggestions {
    final seen = <String>{};
    return [
      for (final g in _grinders)
        for (final b in g.burrs)
          if (seen.add(b.toLowerCase())) b,
    ];
  }

  /// Brands already used — suggestions for the form.
  List<String> get brandSuggestions => gear.brandSuggestions(GearType.grinder);

  Grinder add(String name, List<String> burrs, {String? brand}) {
    final grinder = Grinder(
      id: newSyncId(),
      name: name.trim(),
      brand: _blankToNull(brand),
      burrs: _clean(burrs),
    );
    gear.save(gearFromGrinder(grinder));
    return grinder;
  }

  void update(Grinder grinder) {
    gear.save(
      gearFromGrinder(
        Grinder(
          id: grinder.id,
          name: grinder.name.trim(),
          brand: _blankToNull(grinder.brand),
          burrs: _clean(grinder.burrs),
          activeBurr: grinder.activeBurr,
          hand: grinder.hand,
          scale: grinder.scale,
          zeros: grinder.zeros,
        ),
        existing: gear.byId(grinder.id),
      ),
    );
  }

  void remove(String id) => gear.remove(id);

  /// Re-zero the fitted burrs (kept with the date; unchanged: nothing).
  void setZero(String id, double value, {DateTime? at}) {
    final g = byId(id);
    if (g == null) return;
    final next = g.withZero(value, at ?? DateTime.now());
    if (!identical(next, g)) update(next);
  }

  void setActiveBurr(String id, String burr) {
    final g = byId(id);
    if (g == null || !g.burrs.contains(burr) || g.activeBurrs == burr) return;
    update(g.copyWith(activeBurr: burr));
  }

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static List<String> _clean(List<String> burrs) {
    final seen = <String>{};
    return [
      for (final b in burrs.map((b) => b.trim()))
        if (b.isNotEmpty && seen.add(b.toLowerCase())) b,
    ];
  }
}
