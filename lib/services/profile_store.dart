import '../database/database.dart';
import '../machines/espresso_machine.dart';

// Common denominator of both machines' local profile copies.
//
// Each machine keeps its profiles in the same table (StoredProfiles,
// distinguished by the `machine` column) but fetches them its own way:
// the Meticulous via REST, the GaggiMate via its WebSocket. The profile row
// and profile view only talk to this interface and therefore run unchanged
// for both machines.
abstract class ProfileStore {
  // Key of the machine (like StoredProfiles.machine).
  String get machineKey;

  // Sync all profiles of the machine.
  Future<void> sync();

  // Fetch a single profile fresh (when opening the view).
  // false = machine unreachable or profile no longer there;
  // the local copy stays in both cases.
  Future<bool> refresh(String id);

  // Discard the local copy. Called AFTER the machine has gotten rid of the
  // profile (trash can in the profile view) — the other way round, the next
  // sync would fetch it right back.
  Future<void> forget(String id);
}

// Apply a new order from the profile row (long press and drag).
// [visible] = the cards in the new order; hidden profiles (backflush,
// rinse) keep their positions. Locally first so the row is right
// immediately, then on the machine — if it refuses or is unreachable, the
// old order comes back (the next sync would fetch it from the machine
// anyway).
Future<ProfileSaveResult> reorderMachineProfiles({
  required AppDatabase database,
  required EspressoMachine machine,
  required String machineKey,
  required List<String> visible,
}) async {
  final all =
      (await database.storedProfilesById(machine: machineKey)).values.toList()
        ..sort((a, b) {
          final c = a.position.compareTo(b.position);
          return c != 0 ? c : a.name.compareTo(b.name);
        });
  final before = [for (final p in all) p.id];
  final known = before.toSet();
  final moved = [
    for (final id in visible)
      if (known.contains(id)) id,
  ];
  final movedSet = moved.toSet();
  var next = 0;
  final after = [
    for (final id in before) movedSet.contains(id) ? moved[next++] : id,
  ];
  await database.setStoredProfileOrder(after, machine: machineKey);
  final result = await machine.reorderProfiles(after);
  if (!result.isOk) {
    await database.setStoredProfileOrder(before, machine: machineKey);
  }
  return result;
}
