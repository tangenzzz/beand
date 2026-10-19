import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../models/gear.dart';
import '../models/grinder.dart';
import 'gear_store.dart';

// What is set in the pre-shot card (profile, bean, dose, grind size). Lives
// as a service so the shot import can take a snapshot of it when a shot
// starts; persists across app restarts and is additionally updated from
// the last shot at startup (restoreFromLastShot).
//
// **Each machine has its own store**: profiles only belong to one machine
// anyway, and dose/grind size belong to the profile. Previously both shared
// one — so the GaggiMate home showed the Meticulous profile. The separation
// lies solely in the prefix of the prefs keys; the Meticulous keeps its old
// keys and thus its saved state.
class ShotSetupSnapshot {
  const ShotSetupSnapshot({
    required this.beanId,
    required this.doseGrams,
    required this.grindSize,
    this.grinder,
    this.burrs,
    this.brewedWith,
    this.brewChainId,
  });

  // Dose and grind size are empty as long as nothing has been brewed with
  // this profile yet — then the shot gets no value attached either, instead
  // of a made-up one.
  final int? beanId;
  final double? doseGrams;
  final double? grindSize;
  // Name and fitted burrs of the chain's grinder at this moment.
  final String? grinder;
  final String? burrs;
  // The chain's gear, one piece per line in desk order (Shots.brewedWith).
  final String? brewedWith;
  final String? brewChainId;
}

class ShotSetup extends ChangeNotifier {
  ShotSetup._(
    this._prefs,
    this.machineKey,
    this._beanId,
    this._doseGrams,
    this._grindSize,
    this._profileId,
    this._profileName,
  );

  // Default values of the rulers when nothing is set yet. They only end up
  // in the setup once the user actually moves the ruler.
  static const defaultDose = 18.0;
  static const defaultGrind = 3.2;

  // Key of the machine (like Shots.machine).
  final String machineKey;

  // The Meticulous keeps the original keys without prefix, so an update
  // doesn't lose the saved state.
  String _key(String name) =>
      machineKey == 'meticulous' ? name : '${machineKey}_$name';

  static const _beanKey = 'shot_setup_bean_id';
  static const _doseKey = 'shot_setup_dose';
  static const _grindKey = 'shot_setup_grind';
  static const _profileIdKey = 'shot_setup_profile_id';
  static const _profileNameKey = 'shot_setup_profile_name';
  // Until 2026-10-19 a grinder was chosen here ('shot_setup_grinder_id');
  // now the brew chain, whose grinder goes on the shot.
  static const _chainKey = 'shot_setup_chain_id';

  final SharedPreferences? _prefs;
  int? _beanId;
  double? _doseGrams;
  double? _grindSize;
  String? _profileId;
  String? _profileName;
  String? _chainId;
  Timer? _saveTimer;

  /// The user's gear and brew chains, to turn the chosen chain into what
  /// goes on the shot. Set by main(); without it (tests) shots get none.
  GearStore? gear;

  // Without prefs (tests): in memory only.
  factory ShotSetup.inMemory({
    String machineKey = 'meticulous',
    int? beanId,
    double? doseGrams,
    double? grindSize,
    String? profileId,
    String? profileName,
  }) => ShotSetup._(
    null,
    machineKey,
    beanId,
    doseGrams,
    grindSize,
    profileId,
    profileName,
  );

  static Future<ShotSetup> load({String machineKey = 'meticulous'}) async {
    final prefs = await SharedPreferences.getInstance();
    final setup = ShotSetup._(prefs, machineKey, null, null, null, null, null);
    setup._beanId = prefs.getInt(setup._key(_beanKey));
    setup._doseGrams = prefs.getDouble(setup._key(_doseKey));
    setup._grindSize = prefs.getDouble(setup._key(_grindKey));
    setup._profileId = prefs.getString(setup._key(_profileIdKey));
    setup._profileName = prefs.getString(setup._key(_profileNameKey));
    setup._chainId = prefs.getString(setup._key(_chainKey));
    return setup;
  }

  int? get beanId => _beanId;
  double? get doseGrams => _doseGrams;
  double? get grindSize => _grindSize;
  String? get profileId => _profileId;
  String? get profileName => _profileName;

  /// The chosen brew chain, null if none is chosen or it was deleted. With
  /// exactly one chain that one counts as chosen.
  BrewChain? get chain {
    final store = gear;
    if (store == null) return null;
    final chains = store.chains;
    final chosen = chains.where((c) => c.id == _chainId).firstOrNull;
    if (chosen != null) return chosen;
    return chains.length == 1 ? chains.single : null;
  }

  /// The chain's grinder (the first one, should it hold several).
  Grinder? get grinder {
    final chain = this.chain;
    final store = gear;
    if (chain == null || store == null) return null;
    final g = store
        .gearOf(chain)
        .where((g) => g.type == GearType.grinder)
        .firstOrNull;
    return g == null ? null : grinderFromGear(g);
  }

  void setChain(String? id) {
    if (id == _chainId) return;
    _chainId = id;
    _changed();
  }

  void setBean(int? id) {
    if (id == _beanId) return;
    _beanId = id;
    _changed();
  }

  void setProfile(String id, String name) {
    if (id == _profileId && name == _profileName) return;
    _profileId = id;
    _profileName = name;
    _changed();
  }

  // On app start: take profile, bean, dose and grind size from the last
  // shot — so after a restart the card looks exactly like at the last
  // brew, even if it was started on the machine itself or the values were
  // corrected in the shot detail afterwards. Only shots of THIS machine
  // count. Fields the shot doesn't know keep the saved value; the profile
  // only if it is known locally (the card needs the ID for loading).
  Future<void> restoreFromLastShot(AppDatabase database) async {
    final shot = await database.lastShot(machine: machineKey);
    if (shot == null) return;
    final profileName = shot.profileName;
    if (profileName != null && profileName.isNotEmpty) {
      final stored = await database.storedProfileByName(
        profileName,
        machine: machineKey,
      );
      if (stored != null) {
        _profileId = stored.id;
        _profileName = profileName;
      }
    }
    // Only a bean that still exists — the shot may point to a deleted one
    // (tombstone).
    final beanId = shot.beanId;
    if (beanId != null && await database.beanExists(beanId)) _beanId = beanId;

    // Dose and grind size not from the very last shot, but from the last one
    // that knows them at all — the same rule by which a profile change
    // carries them over. Otherwise the chain breaks as soon as a brew without
    // values lies in between: after a profile change they would be there,
    // after a restart they would be gone.
    final source = profileName == null || profileName.isEmpty
        ? shot
        : await database.lastShotWithSetup(
                profileName: profileName,
                machine: machineKey,
              ) ??
              shot;
    if (source.doseGrams != null) _doseGrams = source.doseGrams;
    final grind = double.tryParse(source.grindSize ?? '');
    if (grind != null) _grindSize = grind;
    await restoreChainFromLastShot(database, notify: false);
    _changed();
  }

  /// The brew chain of the last shot on this machine that names one still
  /// on the desk — the one last used here (pour over has no other restore,
  /// so it calls this alone).
  Future<void> restoreChainFromLastShot(
    AppDatabase database, {
    bool notify = true,
  }) async {
    final known = {for (final c in gear?.chains ?? const <BrewChain>[]) c.id};
    final ids = await database.recentChainIds(machine: machineKey);
    final id = ids.where(known.contains).firstOrNull;
    if (id == null) return;
    _chainId = id;
    if (notify) _changed();
  }

  void setDose(double? grams) {
    if (grams == _doseGrams) return;
    _doseGrams = grams;
    _changed();
  }

  void setGrind(double? size) {
    if (size == _grindSize) return;
    _grindSize = size;
    _changed();
  }

  ShotSetupSnapshot snapshot() => ShotSetupSnapshot(
    beanId: _beanId,
    doseGrams: _doseGrams,
    grindSize: _grindSize,
    grinder: grinder?.name,
    burrs: grinder?.activeBurrs,
    brewedWith: _brewedWith(),
    brewChainId: chain?.id,
  );

  String? _brewedWith() {
    final chain = this.chain;
    final store = gear;
    if (chain == null || store == null) return null;
    final lines = [for (final g in store.gearOf(chain)) g.label];
    return lines.isEmpty ? null : lines.join('\n');
  }

  // The rulers report every change while dragging: debounce writes.
  void _changed() {
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      void writeInt(String name, int? value) => value == null
          ? prefs.remove(_key(name))
          : prefs.setInt(_key(name), value);
      void writeDouble(String name, double? value) => value == null
          ? prefs.remove(_key(name))
          : prefs.setDouble(_key(name), value);

      writeInt(_beanKey, _beanId);
      writeDouble(_doseKey, _doseGrams);
      writeDouble(_grindKey, _grindSize);
      final chainId = _chainId;
      chainId == null
          ? prefs.remove(_key(_chainKey))
          : prefs.setString(_key(_chainKey), chainId);
      final profileId = _profileId;
      final profileName = _profileName;
      if (profileId == null || profileName == null) {
        prefs.remove(_key(_profileIdKey));
        prefs.remove(_key(_profileNameKey));
      } else {
        prefs.setString(_key(_profileIdKey), profileId);
        prefs.setString(_key(_profileNameKey), profileName);
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

// Both setup stores in one place, so main.dart can create them and the
// home screens can pick the matching one — `Provider<ShotSetup>` alone
// couldn't tell the two instances apart.
class ShotSetups {
  ShotSetups({required this.meticulous, required this.gaggimate});

  final ShotSetup meticulous;
  final ShotSetup gaggimate;

  /// Pour over's setup, created later in main() (it needs the recipes).
  ShotSetup? pourOver;

  ShotSetup forMachine(String machineKey) => switch (machineKey) {
    'gaggimate' => gaggimate,
    'pourover' => pourOver ?? meticulous,
    _ => meticulous,
  };

  void dispose() {
    meticulous.dispose();
    gaggimate.dispose();
  }
}
