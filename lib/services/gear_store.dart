import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/sync_ids.dart';
import '../models/gear.dart';
import '../models/grinder.dart';
import '../models/water.dart';

// All of the user's gear and brew chains (Settings → My Coffee Desk), kept
// as two JSON settings so they travel with sync (whitelist in
// setting_codec.dart) and with the backup like every other setting.
//
// Grinders and waters live here too, with the IDs they had in My Setup:
// ShotSetup remembers the chosen grinder by ID. GrinderStore and WaterStore
// are views on this store, so the pre-shot card and the dialogs keep their
// shape.
//
// Photos are files in the app folder under gear_photos/; the setting holds
// only the path relative to the app folder, so a restored backup on another
// phone still finds them.
class GearStore extends ChangeNotifier {
  GearStore._(this._prefs, this.docsPath, this._gear, this._chains);

  static const gearPrefKey = 'desk_gear';
  static const chainsPrefKey = 'desk_chains';

  // Where My Setup kept grinders and waters until 2026-10-19. Read once and
  // moved over; no longer synced.
  static const legacyGrinderKey = 'my_setup_grinders';
  static const legacyWaterKey = 'my_setup_waters';

  static const photoFolder = 'gear_photos';

  final SharedPreferences? _prefs;

  /// The app's documents folder; null in tests (no photos then).
  final String? docsPath;
  List<Gear> _gear;
  List<BrewChain> _chains;

  /// Without prefs (tests): in memory only.
  factory GearStore.inMemory({
    List<Gear> gear = const [],
    List<BrewChain> chains = const [],
    String? docsPath,
  }) => GearStore._(null, docsPath, List.of(gear), List.of(chains));

  static Future<GearStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    String? docs;
    try {
      docs = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {}
    final store = GearStore._(
      prefs,
      docs,
      decodeGear(prefs.getString(gearPrefKey)),
      decodeChains(prefs.getString(chainsPrefKey)),
    );
    store.migrateLegacy(
      grinders: prefs.getString(legacyGrinderKey),
      waters: prefs.getString(legacyWaterKey),
    );
    await prefs.remove(legacyGrinderKey);
    await prefs.remove(legacyWaterKey);
    return store;
  }

  static List<Gear> decodeGear(String? json) =>
      _decodeList(json, Gear.fromJson);

  static List<BrewChain> decodeChains(String? json) =>
      _decodeList(json, BrewChain.fromJson);

  static List<T> _decodeList<T>(String? json, T? Function(Object?) parse) {
    if (json == null) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list.map(parse).whereType<T>().toList();
    } on FormatException {
      return [];
    }
  }

  /// Takes over grinders and waters from the My Setup settings, keeping
  /// their IDs. Entries already here are left alone.
  @visibleForTesting
  void migrateLegacy({String? grinders, String? waters}) {
    final known = {for (final g in _gear) g.id};
    final moved = [
      for (final g in _decodeList(grinders, Grinder.fromJson))
        if (!known.contains(g.id)) gearFromGrinder(g),
      for (final w in _decodeList(waters, Water.fromJson))
        if (!known.contains(w.id)) gearFromWater(w),
    ];
    if (moved.isEmpty) return;
    _gear = [..._gear, ...moved];
    _save();
  }

  List<Gear> get gear => List.unmodifiable(_gear);
  List<BrewChain> get chains => List.unmodifiable(_chains);

  Iterable<Gear> ofType(GearType type) => _gear.where((g) => g.type == type);

  Gear? byId(String? id) {
    if (id == null) return null;
    for (final g in _gear) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// IDs of the gear some chain uses (in use) — everything else is stored.
  Set<String> get activeIds => activeGearIds(_chains);

  /// The gear of [chain] in desk order (by category, then as on the
  /// shelf); pieces deleted since are left out.
  List<Gear> gearOf(BrewChain chain) => [
    for (final type in GearType.values)
      for (final g in ofType(type))
        if (chain.gearIds.contains(g.id)) g,
  ];

  /// Chains [gearId] belongs to.
  List<BrewChain> chainsOf(String gearId) => [
    for (final c in _chains)
      if (c.gearIds.contains(gearId)) c,
  ];

  /// Brands already used for [type] — suggestions for the form.
  List<String> brandSuggestions(GearType type) =>
      _distinct([for (final g in ofType(type)) ?g.brand]);

  /// Values already entered for a spec field of [type].
  List<String> specSuggestions(GearType type, String key) => _distinct([
    for (final g in ofType(type))
      if (g.specs[key] case final String v) v,
  ]);

  static List<String> _distinct(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final v in values)
        if (v.trim().isNotEmpty && seen.add(v.toLowerCase())) v,
    ];
  }

  /// Saves [gear]; a new one (ID '') gets an ID. Returns what was saved.
  Gear save(Gear gear) {
    final saved = gear.id.isEmpty ? gear.withId(newSyncId()) : gear;
    final exists = _gear.any((g) => g.id == saved.id);
    _gear = exists
        ? [for (final g in _gear) g.id == saved.id ? saved : g]
        : [..._gear, saved];
    _save();
    return saved;
  }

  /// Removes the gear, its photo and its place in every chain.
  void remove(String id) {
    final gone = byId(id);
    if (gone == null) return;
    _deletePhotoFile(gone.photoPath);
    _deletePhotoFile(gone.photoOriginalPath);
    _gear = [
      for (final g in _gear)
        if (g.id != id) g,
    ];
    _chains = [
      for (final c in _chains)
        c.gearIds.contains(id)
            ? c.copyWith(gearIds: [...c.gearIds]..remove(id))
            : c,
    ];
    _save();
  }

  BrewChain saveChain(BrewChain chain) {
    final saved = chain.id.isEmpty
        ? BrewChain(
            id: newSyncId(),
            name: chain.name.trim(),
            gearIds: chain.gearIds,
          )
        : chain;
    final exists = _chains.any((c) => c.id == saved.id);
    _chains = exists
        ? [for (final c in _chains) c.id == saved.id ? saved : c]
        : [..._chains, saved];
    _save();
    return saved;
  }

  void removeChain(String id) {
    _chains = [
      for (final c in _chains)
        if (c.id != id) c,
    ];
    _save();
  }

  // ---- Photos ----

  /// The photo file of [gear], null without one (or when it is missing on
  /// this phone, e.g. synced from another device).
  File? photoFile(Gear gear) => _file(gear.photoPath);

  /// The photo a cut-out was made from.
  File? originalPhotoFile(Gear gear) => _file(gear.photoOriginalPath);

  File? _file(String? path) {
    final docs = docsPath;
    if (path == null) return null;
    final file = File(
      p.isAbsolute(path) || docs == null ? path : p.join(docs, path),
    );
    return file.existsSync() ? file : null;
  }

  /// Copies a picked image into the app folder and sets it as the photo of
  /// [gearId] (the picker's cache file may be deleted by Android any time).
  /// With [cutout] (PNG) that one is shown and the photo kept as original.
  Future<void> setPhoto(
    String gearId,
    String pickedPath, {
    Uint8List? cutout,
  }) async {
    final gear = byId(gearId);
    final dir = _photoDir();
    if (gear == null || dir == null) return;
    final original = _newName(p.extension(pickedPath));
    await File(pickedPath).copy(p.join(docsPath!, original));
    final cut = cutout == null ? null : await _writeCutout(cutout);
    _deletePhotoFile(gear.photoPath);
    _deletePhotoFile(gear.photoOriginalPath);
    save(
      gear.copyWith(
        photoPath: cut ?? original,
        photoOriginalPath: cut == null ? null : original,
      ),
    );
  }

  /// Turns a plain photo into a cut-out, keeping the photo as original.
  Future<void> applyCutout(String gearId, Uint8List cutout) async {
    final gear = byId(gearId);
    if (gear == null || gear.photoPath == null || _photoDir() == null) return;
    final cut = await _writeCutout(cutout);
    if (gear.isCutout) {
      _deletePhotoFile(gear.photoPath);
      save(
        gear.copyWith(
          photoPath: cut,
          photoOriginalPath: gear.photoOriginalPath,
        ),
      );
    } else {
      save(gear.copyWith(photoPath: cut, photoOriginalPath: gear.photoPath));
    }
  }

  /// Back from the cut-out to the photo it was cut from.
  void useOriginalPhoto(String gearId) {
    final gear = byId(gearId);
    if (gear == null || !gear.isCutout) return;
    _deletePhotoFile(gear.photoPath);
    save(gear.copyWith(photoPath: gear.photoOriginalPath));
  }

  void removePhoto(String gearId) {
    final gear = byId(gearId);
    if (gear == null || gear.photoPath == null) return;
    _deletePhotoFile(gear.photoPath);
    _deletePhotoFile(gear.photoOriginalPath);
    save(gear.copyWith(clearPhoto: true));
  }

  Directory? _photoDir() {
    final docs = docsPath;
    if (docs == null) return null;
    return Directory(p.join(docs, photoFolder))..createSync(recursive: true);
  }

  // Relative to the app folder.
  static String _newName(String extension) => p.join(
    photoFolder,
    'gear_${DateTime.now().microsecondsSinceEpoch}$extension',
  );

  Future<String> _writeCutout(Uint8List png) async {
    final name = _newName('_cut.png');
    await File(p.join(docsPath!, name)).writeAsBytes(png);
    return name;
  }

  void _deletePhotoFile(String? path) {
    final docs = docsPath;
    if (path == null || docs == null || p.isAbsolute(path)) return;
    try {
      File(p.join(docs, path)).deleteSync();
    } catch (_) {}
  }

  /// After adopting data from sync: re-read from the prefs.
  Future<void> reload() async {
    final prefs = _prefs;
    if (prefs == null) return;
    // Sync writes through the same SharedPreferences instance, so its
    // cache is already current.
    final gear = decodeGear(prefs.getString(gearPrefKey));
    final chains = decodeChains(prefs.getString(chainsPrefKey));
    if (listEquals(gear, _gear) && listEquals(chains, _chains)) return;
    _gear = gear;
    _chains = chains;
    notifyListeners();
  }

  void _save() {
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    _write(prefs, gearPrefKey, [for (final g in _gear) g.toJson()]);
    _write(prefs, chainsPrefKey, [for (final c in _chains) c.toJson()]);
  }

  static void _write(SharedPreferences prefs, String key, List<Object?> list) {
    final json = jsonEncode(list);
    if (list.isEmpty) {
      prefs.remove(key);
    } else if (prefs.getString(key) != json) {
      prefs.setString(key, json);
    }
  }
}

// ---- Grinders and waters as gear ----
//
// Their own fields go into the specs, so a round trip loses nothing; facts
// only the desk knows (photo, grind scale …) stay when a grinder or water
// is saved through its own dialog.

Gear gearFromGrinder(Grinder g, {Gear? existing}) => Gear(
  id: g.id,
  type: GearType.grinder,
  brand: g.brand,
  model: g.name,
  brewModes:
      existing?.brewModes ?? const {BrewMode.espresso, BrewMode.pourOver},
  photoPath: existing?.photoPath,
  photoOriginalPath: existing?.photoOriginalPath,
  specs: {...?existing?.specs, 'burrs': g.burrs, 'activeBurr': g.activeBurrs}
    ..removeWhere((_, v) => v == null || (v is List && v.isEmpty)),
);

Grinder grinderFromGear(Gear g) {
  final burrs = g.specs['burrs'];
  final active = g.specs['activeBurr'];
  return Grinder(
    id: g.id,
    name: g.model,
    brand: g.brand,
    burrs: burrs is List ? burrs.whereType<String>().toList() : const [],
    activeBurr: active is String ? active : null,
  );
}

Gear gearFromWater(Water w, {Gear? existing}) => Gear(
  id: w.id,
  type: GearType.water,
  model: w.recipe,
  brand: existing?.brand,
  brewModes: switch (w.use) {
    WaterUse.espresso => const {BrewMode.espresso},
    WaterUse.pourOver => const {BrewMode.pourOver},
    _ => const {BrewMode.espresso, BrewMode.pourOver},
  },
  photoPath: existing?.photoPath,
  photoOriginalPath: existing?.photoOriginalPath,
  specs:
      {
          for (final e in (existing?.specs ?? const {}).entries)
            if (!_waterKeys.contains(e.key)) e.key: e.value,
          ...w.toJson(),
        }
        ..remove('id')
        ..remove('recipe'),
);

// What a Water writes into the specs — replaced as a whole on every save,
// so a cleared value doesn't linger.
const _waterKeys = {
  'gh',
  'ghMinerals',
  'kh',
  'khMinerals',
  'amounts',
  'unit',
  'ppm',
  'use',
};

Water? waterFromGear(Gear g) =>
    Water.fromJson({...g.specs, 'id': g.id, 'recipe': g.model});
