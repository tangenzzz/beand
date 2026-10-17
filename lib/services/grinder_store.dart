import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/sync_ids.dart';
import '../models/grinder.dart';

// The user's grinders, kept as one JSON setting so they travel with sync
// (whitelist in setting_codec.dart) and with the backup like every other
// setting. Which grinder is in use is chosen per machine (ShotSetup).
class GrinderStore extends ChangeNotifier {
  GrinderStore._(this._prefs, this._grinders);

  static const prefKey = 'my_setup_grinders';

  final SharedPreferences? _prefs;
  List<Grinder> _grinders;

  /// Without prefs (tests): in memory only.
  factory GrinderStore.inMemory([List<Grinder> grinders = const []]) =>
      GrinderStore._(null, List.of(grinders));

  static Future<GrinderStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return GrinderStore._(prefs, decode(prefs.getString(prefKey)));
  }

  static List<Grinder> decode(String? json) {
    if (json == null) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list.map(Grinder.fromJson).whereType<Grinder>().toList();
    } on FormatException {
      return [];
    }
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
  List<String> get brandSuggestions {
    final seen = <String>{};
    return [
      for (final g in _grinders)
        if (g.brand != null && seen.add(g.brand!.toLowerCase())) g.brand!,
    ];
  }

  Grinder add(String name, List<String> burrs, {String? brand}) {
    final grinder = Grinder(
      id: newSyncId(),
      name: name.trim(),
      brand: _blankToNull(brand),
      burrs: _clean(burrs),
    );
    _grinders = [..._grinders, grinder];
    _save();
    return grinder;
  }

  void update(Grinder grinder) {
    _grinders = [
      for (final g in _grinders)
        g.id == grinder.id
            ? Grinder(
                id: grinder.id,
                name: grinder.name.trim(),
                brand: _blankToNull(grinder.brand),
                burrs: _clean(grinder.burrs),
                activeBurr: grinder.activeBurr,
              )
            : g,
    ];
    _save();
  }

  void remove(String id) {
    _grinders = [
      for (final g in _grinders)
        if (g.id != id) g,
    ];
    _save();
  }

  void setActiveBurr(String id, String burr) {
    final g = byId(id);
    if (g == null || !g.burrs.contains(burr) || g.activeBurrs == burr) return;
    update(g.copyWith(activeBurr: burr));
  }

  /// After adopting data from sync: re-read from the prefs.
  Future<void> reload() async {
    final prefs = _prefs;
    if (prefs == null) return;
    // Sync writes through the same SharedPreferences instance, so its
    // cache is already current.
    final fresh = decode(prefs.getString(prefKey));
    if (listEquals(fresh, _grinders)) return;
    _grinders = fresh;
    notifyListeners();
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

  void _save() {
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    if (_grinders.isEmpty) {
      prefs.remove(prefKey);
    } else {
      prefs.setString(
        prefKey,
        jsonEncode([for (final g in _grinders) g.toJson()]),
      );
    }
  }
}
