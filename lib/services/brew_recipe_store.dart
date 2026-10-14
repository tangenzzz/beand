import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brew_recipe.dart';
import 'brew_recipes_source.dart';

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

  /// Checked profiles: first in custom order, then the rest in list order.
  List<BrewRecipe> get enabledRecipes {
    final enabled = [
      for (final r in _recipes)
        if (isEnabled(r.id)) r,
    ];
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
    if (name == null || dir == null) return null;
    final f = File(p.join(dir, name));
    return f.existsSync() ? f : null;
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
    setEnabled(id, false);
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
    for (final r in _recipes) {
      if (r.name == name) return photoFor(r.id);
    }
    return null;
  }

  BrewRecipe? byId(String id) {
    for (final r in _recipes) {
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
