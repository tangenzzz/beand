import 'package:flutter/foundation.dart';

import '../database/database.dart';
import 'shot_setup.dart';

/// Where a suggested setup comes from.
enum SetupSource {
  /// What the Pre-Shot card of that machine holds right now.
  preShot('Pre-Shot'),

  /// An earlier shot with the same profile.
  lastShot('Last shot');

  const SetupSource(this.label);
  final String label;
}

/// A shot that came in without its setup — brewed while the app was closed
/// (user 2026-11-23), a shot added by hand, an old one from the machine's
/// history. The bean is what counts: without it a shot can't be told apart.
bool shotNeedsDetails(Shot shot) =>
    shot.deletedAt == null && shot.beanId == null;

/// Per brew method, from when on its shots are expected to carry a setup:
/// its first shot with a bean. Older ones came from the machine's history
/// before bean'd was used — 257 of them on the test phone — and stay
/// unmarked, or every row of the history would say "Needs details".
Map<String, DateTime> setupSince(Iterable<Shot> shots) {
  final out = <String, DateTime>{};
  for (final s in shots) {
    if (s.deletedAt != null || s.beanId == null) continue;
    final t = out[s.machine];
    if (t == null || s.timestamp.isBefore(t)) out[s.machine] = s.timestamp;
  }
  return out;
}

/// [shotNeedsDetails], counting only shots after [since] of its machine.
bool shotNeedsDetailsSince(Shot shot, Map<String, DateTime> since) {
  final from = since[shot.machine];
  return from != null && shot.timestamp.isAfter(from) && shotNeedsDetails(shot);
}

/// Bean, dose, grind and brew chain to fill a shot with — for every brew
/// method alike (Meticulous, GaggiMate, Pour Over, Espresso and whatever
/// comes): nothing here knows a machine, only the shot's machine key.
@immutable
class SetupSuggestion {
  const SetupSuggestion({
    required this.source,
    this.from,
    this.beanId,
    this.doseGrams,
    this.grindSize,
    this.grindMarker,
    this.grindZero,
    this.grinder,
    this.burrs,
    this.brewedWith,
    this.gearIds,
    this.brewChainId,
  });

  factory SetupSuggestion.fromShot(Shot s) => SetupSuggestion(
    source: SetupSource.lastShot,
    from: s,
    beanId: s.beanId,
    doseGrams: s.doseGrams,
    grindSize: (s.grindSize ?? '').isEmpty ? null : s.grindSize,
    grindMarker: s.grindMarker,
    grindZero: s.grindZero,
    grinder: s.grinder,
    burrs: s.burrs,
    brewedWith: s.brewedWith,
    gearIds: s.gearIds,
    brewChainId: s.brewChainId,
  );

  factory SetupSuggestion.fromSnapshot(ShotSetupSnapshot s) => SetupSuggestion(
    source: SetupSource.preShot,
    beanId: s.beanId,
    doseGrams: s.doseGrams,
    grindSize: s.grindText,
    grindMarker: s.grindMarker,
    grindZero: s.grindZero,
    grinder: s.grinder,
    burrs: s.burrs,
    brewedWith: s.brewedWith,
    gearIds: s.gearIds,
    brewChainId: s.brewChainId,
  );

  final SetupSource source;

  /// The shot the values come from ([SetupSource.lastShot]).
  final Shot? from;

  final int? beanId;
  final double? doseGrams;
  final String? grindSize;
  final String? grindMarker;
  final double? grindZero;
  final String? grinder;
  final String? burrs;
  final String? brewedWith;
  final String? gearIds;
  final String? brewChainId;

  bool get isEmpty => beanId == null && doseGrams == null && grindSize == null;

  /// Writes the values onto [shotId]. [onlyEmpty]: what the shot already has
  /// stays (a suggestion); otherwise it is replaced ("Copy from…").
  Future<void> applyTo(AppDatabase db, int shotId, {bool onlyEmpty = true}) =>
      db.applyShotSetup(
        shotId,
        beanId: beanId,
        doseGrams: doseGrams,
        grindSize: grindSize,
        grindMarker: grindMarker,
        grindZero: grindZero,
        grinder: grinder,
        burrs: burrs,
        brewedWith: brewedWith,
        gearIds: gearIds,
        brewChainId: brewChainId,
        onlyEmpty: onlyEmpty,
      );
}

/// The setups a shot without details can take, best first:
/// 1. the Pre-Shot card of its machine — only for the machine's newest
///    shot and when the card holds the same profile (it was likely set up
///    for exactly this shot);
/// 2. the last earlier shot with the same profile (any profile if the shot
///    has none).
/// Empty when there is nothing to take.
Future<List<SetupSuggestion>> suggestSetups(
  AppDatabase db,
  Shot shot, {
  ShotSetups? setups,
}) async {
  final out = <SetupSuggestion>[];
  final profile = (shot.profileName ?? '').trim();
  final setup = setups?.forMachine(shot.machine);
  if (setup != null &&
      setup.machineKey == shot.machine &&
      profile.isNotEmpty &&
      setup.profileName?.trim() == profile) {
    final newest = await db.lastShot(machine: shot.machine);
    if (newest?.id == shot.id) {
      final pre = SetupSuggestion.fromSnapshot(setup.snapshot());
      if (!pre.isEmpty) out.add(pre);
    }
  }
  final earlier = await db.shotsWithSetup(
    machine: shot.machine,
    profileName: profile.isEmpty ? null : shot.profileName,
    before: shot.timestamp,
    exceptId: shot.id,
  );
  if (earlier.isNotEmpty) out.add(SetupSuggestion.fromShot(earlier.first));
  return out;
}
