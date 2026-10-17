import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/sync_ids.dart';
import '../models/water.dart';

// The user's brew waters (My Setup → Water), kept as one JSON setting so
// they travel with sync and backup like the grinders (GrinderStore).
class WaterStore extends ChangeNotifier {
  WaterStore._(this._prefs, this._waters);

  static const prefKey = 'my_setup_waters';

  final SharedPreferences? _prefs;
  List<Water> _waters;

  /// Without prefs (tests): in memory only.
  factory WaterStore.inMemory([List<Water> waters = const []]) =>
      WaterStore._(null, List.of(waters));

  static Future<WaterStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WaterStore._(prefs, decode(prefs.getString(prefKey)));
  }

  static List<Water> decode(String? json) {
    if (json == null) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list.map(Water.fromJson).whereType<Water>().toList();
    } on FormatException {
      return [];
    }
  }

  List<Water> get waters => List.unmodifiable(_waters);

  /// Sources already used for GH or KH — suggestions for the form.
  List<String> get ghSources => _distinct(_waters.map((w) => w.ghSource));
  List<String> get khSources => _distinct(_waters.map((w) => w.khSource));

  /// Saves [water]; a new ID ('') gets one.
  Water save(Water water) {
    final saved = water.id.isEmpty
        ? Water(
            id: newSyncId(),
            recipe: water.recipe.trim(),
            gh: water.gh,
            ghSource: water.ghSource,
            kh: water.kh,
            khSource: water.khSource,
            ppm: water.ppm,
            use: water.use,
          )
        : water;
    final exists = _waters.any((w) => w.id == saved.id);
    _waters = exists
        ? [for (final w in _waters) w.id == saved.id ? saved : w]
        : [..._waters, saved];
    _save();
    return saved;
  }

  void remove(String id) {
    _waters = [
      for (final w in _waters)
        if (w.id != id) w,
    ];
    _save();
  }

  /// After adopting data from sync: re-read from the prefs.
  Future<void> reload() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final fresh = decode(prefs.getString(prefKey));
    if (listEquals(fresh, _waters)) return;
    _waters = fresh;
    notifyListeners();
  }

  static List<String> _distinct(Iterable<String?> values) {
    final seen = <String>{};
    return [
      for (final v in values)
        if (v != null && seen.add(v.toLowerCase())) v,
    ];
  }

  void _save() {
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    if (_waters.isEmpty) {
      prefs.remove(prefKey);
    } else {
      prefs.setString(
        prefKey,
        jsonEncode([for (final w in _waters) w.toJson()]),
      );
    }
  }
}
