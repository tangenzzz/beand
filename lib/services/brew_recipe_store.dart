import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brew_recipe.dart';
import 'brew_recipes_source.dart';
import 'meticulous_pourover_profiles.dart';

const brewRecipesAsset = 'assets/brew_recipes.json';

/// Holds the pour-over recipes. Read-only — creating your own is not
/// supported.
///
/// Source: the bundled version (works offline) or, if newer, the cache last
/// fetched from GitHub. An update only replaces the current version if it
/// provides at least one valid recipe — otherwise the old one stays.
class BrewRecipeStore extends ChangeNotifier {
  BrewRecipeStore({
    required this.cacheFile,
    Future<String> Function()? loadBundled,
    BrewRecipesSource Function()? source,
  }) : _loadBundled =
           loadBundled ?? (() => rootBundle.loadString(brewRecipesAsset)),
       _source = source ?? BrewRecipesSource.new;

  final File cacheFile;
  final Future<String> Function() _loadBundled;
  final BrewRecipesSource Function() _source;

  List<BrewRecipe> _recipes = const [];
  List<BrewRecipe> get recipes => _recipes;

  String? _commit;
  String? get commit => _commit;

  DateTime? _fetchedAt;
  DateTime? get fetchedAt => _fetchedAt;

  bool _updating = false;
  bool get updating => _updating;

  // ---- Selection (Settings → Home → Pour Over → Profiles) ----
  //
  // Which profiles appear below the brew cards and in the pre-brew picker.
  // After a fresh install NONE is checked — everyone picks their own
  // profiles into the view. Whatever comes from GitHub later is NOT checked
  // and counts as new until the settings page has been opened once
  // ([markAllSeen]).
  static const enabledPrefKey = 'pourover_enabled_recipes';
  static const knownPrefKey = 'pourover_known_recipes';
  // Custom order of the profile row (long press and drag). Profiles not
  // listed follow after it in list order.
  static const orderPrefKey = 'pourover_recipe_order';

  Set<String>? _enabled;
  Set<String>? _known;
  List<String> _order = const [];

  bool isEnabled(String id) => _enabled?.contains(id) ?? false;

  // ---- Own profiles ----
  //
  // Everyone gathers their own (user 2026-11-04, via "+" on the profile
  // row): the Meticulous' Pour Over profiles (cached, so they are there
  // with a Bluetooth scale too), profiles from .json files and the checked
  // brew-recipes. With the Meticulous in Machine mode only the machine's
  // (its dial picks one of them anyway).
  static const machineCachePrefKey = 'pourover_machine_profiles';
  static const importedPrefKey = 'pourover_imported_profiles';

  List<Map<String, dynamic>> _importedRaw = [];
  List<BrewRecipe> _imported = const [];
  List<BrewRecipe> get importedRecipes => _imported;
  bool isImported(String id) => _imported.any((r) => r.id == id);
  final Map<String, File> _importPhotos = {};

  static String importPhotoName(String id) => 'imported_pourover_$id.jpg';

  /// Adds a profile from a .json file (same ID: replaced). Throws
  /// [BrewRecipeFormatException] when it is no pour over profile.
  BrewRecipe importProfile(Map<String, dynamic> json) {
    final recipe = parsePourOverProfile(json);
    final image = embeddedImage(json);
    final dir = _photoDir;
    if (image != null && dir != null) {
      try {
        Directory(dir).createSync(recursive: true);
        final f = File(p.join(dir, importPhotoName(recipe.id)))
          ..writeAsBytesSync(image);
        _importPhotos[recipe.id] = f;
      } catch (_) {}
    }
    _importedRaw = [
      for (final r in _importedRaw)
        if ('${r['id']}' != recipe.id) r,
      withoutImage(json),
    ];
    _imported = [
      for (final r in _imported)
        if (r.id != recipe.id) r,
      recipe,
    ];
    notifyListeners();
    final raw = jsonEncode(_importedRaw);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(importedPrefKey, raw))
        .catchError((Object _) => false);
    return recipe;
  }

  static BrewRecipe? _tryParse(Map<String, dynamic> json) {
    try {
      return parsePourOverProfile(json);
    } on BrewRecipeFormatException {
      return null;
    }
  }

  void _removeImported(String id) {
    _importedRaw = [
      for (final r in _importedRaw)
        if ('${r['id']}' != id) r,
    ];
    _imported = [
      for (final r in _imported)
        if (r.id != id) r,
    ];
    final photo = _importPhotos.remove(id);
    try {
      photo?.deleteSync();
    } catch (_) {}
    notifyListeners();
    final raw = jsonEncode(_importedRaw);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(importedPrefKey, raw))
        .catchError((Object _) => false);
  }

  // ---- Meticulous filter profiles ----

  /// Loads the machine's profiles; set in main.dart.
  MeticulousPourOverProfiles? machineSource;

  bool _useMachine = false;
  bool get useMachine => _useMachine;

  List<BrewRecipe> _machineRecipes = const [];
  List<BrewRecipe> get machineRecipes => _machineRecipes;

  bool _machineLoading = false;
  bool get machineLoading => _machineLoading;

  /// Whether the list was fetched at least once (empty list ≠ not loaded).
  bool _machineLoaded = false;
  bool get machineLoaded => _machineLoaded;

  String? _machineError;
  String? get machineError => _machineError;

  final Map<String, File> _machinePhotos = {};

  /// Machine mode: only the machine's profiles in the row and picker.
  void setUseMachine(bool value) {
    if (value == _useMachine) return;
    _useMachine = value;
    notifyListeners();
    if (value) unawaited(refreshMachine());
  }

  Future<void>? _machineFetch;

  /// Fetches the machine's Pour Over profiles (and their images). A call
  /// while a fetch runs waits for that one.
  Future<void> refreshMachine() {
    if (machineSource == null) return Future.value();
    final running = _machineFetch;
    if (running != null) return running;
    // Set before anything notifies: listeners may call this again.
    _machineLoading = true;
    final fetch = _machineFetch = _fetchMachine();
    notifyListeners();
    return fetch;
  }

  Future<void> _fetchMachine() async {
    final source = machineSource!;
    // Let refreshMachine store the future first.
    await Future<void>.value();
    try {
      final raw = await source.fetchRaw();
      setMachineRecipes(parseMachineProfiles(raw));
      _machineError = null;
      // Kept for when the machine is out of reach (Bluetooth scale).
      final cache = jsonEncode(raw);
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(machineCachePrefKey, cache))
          .catchError((Object _) => false);
    } catch (e) {
      _machineError = 'Could not load the profiles from the Meticulous.';
      debugPrint('BrewRecipeStore: machine profiles failed: $e');
    } finally {
      _machineLoading = false;
      _machineFetch = null;
      notifyListeners();
    }
    for (final r in _machineRecipes) {
      final file = await source.fetchPhoto(r.id);
      if (file != null && _machinePhotos[r.id]?.path != file.path) {
        _machinePhotos[r.id] = file;
        notifyListeners();
      }
    }
  }

  void setMachineRecipes(List<BrewRecipe> recipes) {
    _machineRecipes = List.unmodifiable(recipes);
    _machineLoaded = true;
    notifyListeners();
  }

  /// Checked profiles: first in custom order, then the rest in list order.
  /// With the Meticulous as the scale: the machine's profiles.
  List<BrewRecipe> get enabledRecipes =>
      _useMachine ? _sorted(_machineRecipes) : ownRecipes;

  /// All own profiles: the machine's, from files, checked brew-recipes —
  /// whatever the scale (also the profile list of a brew added by hand).
  List<BrewRecipe> get ownRecipes =>
      _sorted([..._machineRecipes, ..._imported, ..._githubEnabled]);

  /// Checked brew-recipes (Settings → Pour Over → Profiles), whatever scale
  /// is in use.
  List<BrewRecipe> get checkedRecipes => _sorted(_githubEnabled);

  List<BrewRecipe> get _githubEnabled => [
    for (final r in _recipes)
      if (isEnabled(r.id)) r,
  ];

  List<BrewRecipe> _sorted(List<BrewRecipe> list) {
    final enabled = List.of(list);
    final rank = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    final listIndex = {
      for (var i = 0; i < enabled.length; i++) enabled[i].id: i,
    };
    int key(BrewRecipe r) => rank[r.id] ?? _order.length + listIndex[r.id]!;
    return enabled..sort((a, b) => key(a).compareTo(key(b)));
  }

  /// New order of the profile row.
  void setOrder(List<String> ids) {
    _order = List.unmodifiable(ids);
    notifyListeners();
    _savePrefs();
  }

  bool isNew(String id) => _known != null && !_known!.contains(id);

  int get newCount => _recipes.where((r) => isNew(r.id)).length;

  void setEnabled(String id, bool value) {
    final set = _enabled ??= <String>{};
    if (value ? !set.add(id) : !set.remove(id)) return;
    notifyListeners();
    _savePrefs();
  }

  void markAllSeen() {
    if (newCount == 0) return;
    _known = {...?_known, for (final r in _recipes) r.id};
    notifyListeners();
    _savePrefs();
  }

  // ---- Custom photos (profile view header, card) ----
  //
  // Only the FILE NAME in the profile_photos folder is stored, not the full
  // path: after a restore on another device the app folder is somewhere
  // else, the name stays the same.
  static const photosPrefKey = 'pourover_profile_photos';
  static const photoFolder = 'profile_photos';
  Map<String, String> _photos = {};
  String? _photoDir;

  /// Custom photo of the profile, null without photo (or if the file is
  /// missing).
  File? photoFor(String id) {
    final name = _photos[id];
    final dir = _photoDir;
    if (name != null && dir != null) {
      final f = File(p.join(dir, name));
      if (f.existsSync()) return f;
    }
    // Machine profiles and imported files bring their own image.
    return _machinePhotos[id] ?? _importPhotos[id];
  }

  /// Sets (or clears with null) the photo; [path] is already in the photo
  /// folder. The old photo is deleted.
  void setPhoto(String id, String? path) {
    final old = photoFor(id);
    if (path == null) {
      _photos.remove(id);
    } else {
      _photos[id] = p.basename(path);
    }
    if (old != null && old.path != path) {
      try {
        old.deleteSync();
      } catch (_) {}
    }
    notifyListeners();
    _savePrefs();
  }

  /// "Delete profile": remove from the own selection and discard the custom
  /// photo. The profile itself stays in the list (Settings) — it comes from
  /// brew-recipes and can be checked again at any time.
  void remove(String id) {
    setPhoto(id, null);
    if (isImported(id)) {
      _removeImported(id);
    } else {
      setEnabled(id, false);
    }
  }

  Future<void> _loadPrefs() async {
    try {
      _photoDir = p.join(
        (await getApplicationDocumentsDirectory()).path,
        photoFolder,
      );
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final photos = prefs.getString(photosPrefKey);
      if (photos != null) {
        _photos = Map<String, String>.from(jsonDecode(photos) as Map);
      }
      // Own profiles from files, and the machine's last list.
      final imported = prefs.getString(importedPrefKey);
      if (imported != null) {
        _importedRaw = [
          for (final r in jsonDecode(imported) as List)
            Map<String, dynamic>.from(r as Map),
        ];
        _imported = [
          for (final r in _importedRaw)
            if (_tryParse(r) case final BrewRecipe recipe) recipe,
        ];
      }
      final machine = prefs.getString(machineCachePrefKey);
      if (machine != null && _machineRecipes.isEmpty) {
        _machineRecipes = List.unmodifiable(
          parseMachineProfiles([
            for (final r in jsonDecode(machine) as List)
              Map<String, dynamic>.from(r as Map),
          ]),
        );
        _machineLoaded = true;
      }
      final dir = _photoDir;
      if (dir != null) {
        for (final r in _machineRecipes) {
          final f = File(
            p.join(dir, MeticulousPourOverProfiles.photoName(r.id)),
          );
          if (f.existsSync()) _machinePhotos[r.id] = f;
        }
        for (final r in _imported) {
          final f = File(p.join(dir, importPhotoName(r.id)));
          if (f.existsSync()) _importPhotos[r.id] = f;
        }
      }
      final enabled = prefs.getStringList(enabledPrefKey);
      final known = prefs.getStringList(knownPrefKey);
      if (enabled != null) _enabled = enabled.toSet();
      _order = prefs.getStringList(orderPrefKey) ?? const [];
      if (known != null) _known = known.toSet();
    } catch (e) {
      debugPrint('BrewRecipeStore: prefs unreadable: $e');
    }
  }

  void _savePrefs() {
    final enabled = _enabled?.toList();
    final known = _known?.toList();
    final photos = jsonEncode(_photos);
    final order = _order;
    SharedPreferences.getInstance()
        .then((prefs) async {
          await prefs.setStringList(orderPrefKey, order);
          if (enabled != null) {
            await prefs.setStringList(enabledPrefKey, enabled);
          }
          if (known != null) await prefs.setStringList(knownPrefKey, known);
          await prefs.setString(photosPrefKey, photos);
        })
        .catchError((Object e) {
          debugPrint('BrewRecipeStore: prefs not saved: $e');
        });
  }

  // First start: nothing checked, everything present now counts as known
  // (otherwise everything would show as "NEW").
  void _initSelection() {
    if (_recipes.isEmpty || (_enabled != null && _known != null)) return;
    _enabled ??= <String>{};
    _known ??= {for (final r in _recipes) r.id};
    _savePrefs();
  }

  /// Custom photo of the recipe with this name — pour-over shots only store
  /// the name (`Shots.profileName`), not the recipe ID.
  File? photoForName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final r in [..._recipes, ..._machineRecipes, ..._imported]) {
      if (r.name == name) return photoFor(r.id);
    }
    return null;
  }

  /// Recipe from the list in use (machine profiles with the Meticulous as
  /// the scale, brew-recipes otherwise).
  BrewRecipe? byId(String id) {
    for (final r in [
      ..._machineRecipes,
      if (!_useMachine) ..._imported,
      if (!_useMachine) ..._recipes,
    ]) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> load() async {
    await _loadPrefs();
    BrewRecipeBundle? bundled;
    BrewRecipeBundle? cached;
    try {
      bundled = BrewRecipeBundle.fromJson(
        jsonDecode(await _loadBundled()) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('BrewRecipeStore: bundled recipes unreadable: $e');
    }
    try {
      if (await cacheFile.exists()) {
        cached = BrewRecipeBundle.fromJson(
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('BrewRecipeStore: cache unreadable: $e');
    }
    // After an app update the bundled version can be newer than the cache —
    // then it wins.
    final pick =
        (cached != null &&
            (bundled == null || cached.fetchedAt.isAfter(bundled.fetchedAt)))
        ? cached
        : bundled;
    if (pick != null) _apply(pick);
    _initSelection();
  }

  /// Fetches the latest version from GitHub. Returns the number of valid
  /// recipes, or null if already up to date. Throws on network errors.
  Future<int?> updateFromGitHub() async {
    if (_updating) return null;
    _updating = true;
    notifyListeners();
    final source = _source();
    try {
      final latest = await source.latestCommit();
      if (latest == _commit) return null;
      final bundle = await source.fetch(commit: latest);
      final parsed = parseBrewRecipes(bundle.raw);
      if (parsed.recipes.isEmpty) {
        throw const FormatException('update contained no valid recipes');
      }
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(jsonEncode(bundle.toJson()));
      _apply(bundle);
      return parsed.recipes.length;
    } finally {
      source.close();
      _updating = false;
      notifyListeners();
    }
  }

  void _apply(BrewRecipeBundle bundle) {
    final parsed = parseBrewRecipes(bundle.raw);
    if (parsed.recipes.isEmpty) return;
    for (final r in parsed.rejected) {
      debugPrint('BrewRecipeStore: skipped $r');
    }
    _recipes = parsed.recipes
      ..sort((a, b) {
        final byBrewer = a.brewer.compareTo(b.brewer);
        return byBrewer != 0 ? byBrewer : a.name.compareTo(b.name);
      });
    _commit = bundle.commit;
    _fetchedAt = bundle.fetchedAt;
    notifyListeners();
  }
}
