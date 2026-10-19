import 'package:flutter/foundation.dart';

import '../database/sync_ids.dart';
import '../models/gear.dart';
import '../models/water.dart';
import 'gear_store.dart';

// The user's brew waters — a view on the waters in [GearStore] (My Coffee
// Desk), with the shape the water dialog knows.
class WaterStore extends ChangeNotifier {
  WaterStore(this.gear) : _waters = _read(gear) {
    gear.addListener(_gearChanged);
  }

  /// Without prefs (tests): in memory only.
  factory WaterStore.inMemory([List<Water> waters = const []]) => WaterStore(
    GearStore.inMemory(gear: [for (final w in waters) gearFromWater(w)]),
  );

  final GearStore gear;
  List<Water> _waters;

  static List<Water> _read(GearStore gear) => [
    for (final g in gear.ofType(GearType.water)) ?waterFromGear(g),
  ];

  void _gearChanged() {
    final fresh = _read(gear);
    if (listEquals(fresh, _waters)) return;
    _waters = fresh;
    notifyListeners();
  }

  @override
  void dispose() {
    gear.removeListener(_gearChanged);
    super.dispose();
  }

  List<Water> get waters => List.unmodifiable(_waters);

  Water? byId(String? id) {
    for (final w in _waters) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Saves [water]; a new ID ('') gets one.
  Water save(Water water) {
    final saved = water.id.isEmpty
        ? Water(
            id: newSyncId(),
            recipe: water.recipe.trim(),
            gh: water.gh,
            ghMinerals: water.ghMinerals,
            kh: water.kh,
            khMinerals: water.khMinerals,
            amounts: water.amounts,
            unit: water.unit,
            ppm: water.ppm,
            use: water.use,
          )
        : water;
    gear.save(gearFromWater(saved, existing: gear.byId(saved.id)));
    return saved;
  }

  void remove(String id) => gear.remove(id);
}
