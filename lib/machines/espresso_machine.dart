import 'package:flutter/foundation.dart';

import '../models/machine_profile.dart';
import '../models/profile_draft.dart';

// Common interface for all espresso machines. The Meticulous
// (Socket.IO + REST) is the first implementation, GaggiMate (raw
// WebSocket) the second.
//
// Intent: everything the UI needs across machines (connection status,
// live values, profiles, start/stop) lives here in normalized form.
// Whatever only one machine can do stays on its concrete class — the
// Meticulous home screen may keep talking to MeticulousSocketService
// directly (four temperature sensors, preheat countdown, profileHover)
// instead of forcing everything into a common denominator that fits
// neither machine.

enum MachineConnectionState { disconnected, connecting, connected, error }

// Machine system state, coarse enough that both machines can fill it:
// GaggiMate reports it directly (sys.s); for the Meticulous we derive it
// from the phase field.
enum MachineSystemStatus {
  unknown,
  starting,
  waiting,
  ready,
  busy,
  updating,
  error,
}

// What the machine can do. Controls which cards and buttons the home
// screen shows — instead of checking the machine type directly. GaggiMate
// reports pressure and dimming capability at runtime (cp/cd), so this is
// not something that could be fixed in the type.
@immutable
class MachineCapabilities {
  const MachineCapabilities({
    required this.temperatureSensors,
    this.pressure = false,
    this.flow = false,
    this.weight = false,
    this.profiles = false,
    this.flush = false,
    this.steam = false,
  });

  final int temperatureSensors;
  final bool pressure;
  final bool flow;
  final bool weight;
  final bool profiles;
  final bool flush;
  final bool steam;

  MachineCapabilities copyWith({bool? pressure, bool? flow, bool? weight}) {
    return MachineCapabilities(
      temperatureSensors: temperatureSensors,
      pressure: pressure ?? this.pressure,
      flow: flow ?? this.flow,
      weight: weight ?? this.weight,
      profiles: profiles,
      flush: flush,
      steam: steam,
    );
  }
}

// A machine warning (GaggiMate: warn[]). `severity` is the CONFIGURED
// severity (0 off, 1 notice, 2 error), `active` says whether the condition
// currently applies — both must hold for the warning to count.
@immutable
class MachineWarning {
  const MachineWarning({
    required this.key,
    required this.severity,
    required this.active,
  });

  final String key;
  final int severity;
  final bool active;

  bool get isBlocking => active && severity >= 2;
  bool get isVisible => active && severity >= 1;

  // Plain text for the UI. Unknown keys are passed through raw instead of
  // being swallowed — new firmware may add some at any time.
  String get label {
    switch (key) {
      case 'water':
        return 'Water tank empty';
      case 'flush':
        return 'Flush needed';
      case 'switch':
        return 'Brew switch is on';
      case 'scaleConnected':
        return 'Scale not connected';
      case 'scaleBattery':
        return 'Scale battery low';
      case 'temperature':
        return 'Temperature not reached';
      default:
        return key;
    }
  }
}

// Normalized live state. Everything nullable: what a machine does not
// measure (GaggiMate Standard has neither pressure nor flow) stays empty —
// the UI then hides the field instead of showing 0.
@immutable
class MachineLiveState {
  const MachineLiveState({
    this.temperature,
    this.targetTemperature,
    this.pressure,
    this.targetPressure,
    this.flow,
    this.weight,
    this.phase = '',
    this.extracting = false,
    this.shotTime,
    this.activeProfileName,
    this.activeProfileId,
    this.systemStatus = MachineSystemStatus.unknown,
    this.systemMessage,
    this.warnings = const [],
  });

  static const empty = MachineLiveState();

  final double? temperature;
  final double? targetTemperature;
  final double? pressure;
  final double? targetPressure;
  final double? flow;
  final double? weight;
  // Machine-specific plain text ("heating", "extracting", …) — display
  // only, not for logic. For logic use `systemStatus`/`extracting`.
  final String phase;
  final bool extracting;
  final Duration? shotTime;
  final String? activeProfileName;
  // Profile currently loaded on the machine — the pre-shot card marks it
  // in the selection list.
  final String? activeProfileId;
  final MachineSystemStatus systemStatus;
  final String? systemMessage;
  final List<MachineWarning> warnings;

  List<MachineWarning> get visibleWarnings => [
    for (final w in warnings)
      if (w.isVisible) w,
  ];

  bool get hasBlockingWarning => warnings.any((w) => w.isBlocking);
}

// What you can tell a machine. Not every machine can do everything —
// `sendCommand` returns false if the command means nothing on this machine.
enum MachineCommand { start, stop, tare, preheat, flushStart, flushStop }

// Result of a profile upload or delete: the machine may reject either
// (format, storage full, profile currently active); the reason is then in
// [error].
class ProfileSaveResult {
  const ProfileSaveResult.ok(this.id) : error = null;
  const ProfileSaveResult.failed(this.error) : id = null;

  final String? id;
  final String? error;

  bool get isOk => error == null;
}

abstract class EspressoMachine extends ChangeNotifier {
  // Name for headings and error messages ("Meticulous", "GaggiMate").
  String get displayName;

  // Key of this machine in the database (Shots.machine,
  // StoredProfiles.machine) — see ShotMachine in history_logic.dart.
  String get machineKey;

  // Hostname or IP, without scheme.
  String get host;

  MachineConnectionState get connectionState;
  String? get lastError;
  MachineCapabilities get capabilities;
  MachineLiveState get liveState;

  void connect();
  void disconnect();
  void updateHost(String host);

  Future<List<MachineProfile>> fetchProfiles();

  // Activate a profile on the machine. WARNING: really starts heating on
  // both machines — never call without confirming there is water in the
  // tank.
  Future<bool> selectProfile(String id);

  Future<bool> sendCommand(MachineCommand command);

  // Highlight a profile on the machine's display WITHOUT loading it or
  // heating — the Meticulous can do this (profileHover), the GaggiMate
  // cannot. Machines that can't do nothing; the selection in the app is
  // unaffected.
  void highlightProfile(String id, String name) {}

  // Put a profile JSON onto the machine ("+" in the profile row). Both
  // machines can do this, just via different routes: the Meticulous via
  // REST, the GaggiMate via `req:profiles:save`.
  Future<ProfileSaveResult> uploadProfile(Map<String, dynamic> json);

  // Delete a profile on the machine (trash can in the profile view). If it
  // is already gone there, that counts as success — the goal is that it no
  // longer exists afterwards, not that this particular call found it.
  Future<ProfileSaveResult> deleteProfile(String id);

  // Set the order of profiles on the machine (long-press and drag in the
  // profile row). [ids] = all profiles in the new order; the machine
  // appends whatever is missing at the end.
  Future<ProfileSaveResult> reorderProfiles(List<String> ids);

  // Where profiles for THIS machine can be downloaded — the
  // "Add profile" dialog shows them as links.
  List<({String label, String url})> get profileSites;

  // Whether the built-in profile editor works for this machine. It produces
  // the Meticulous format (stages with curve, exit triggers, limits); the
  // GaggiMate uses its own format and is therefore left out for now. To add
  // it, it is enough to switch this and translate the format.
  bool get canEditProfiles => false;

  // Translation between THIS machine's profile JSON and the editable
  // version. The Meticulous needs none — its format IS the draft's format;
  // the GaggiMate layers its own on top. That way the editor doesn't need
  // to know which machine it is talking to.
  ProfileDraft draftFromProfile(Map<String, dynamic> json) =>
      ProfileDraft.fromJson(json);

  Map<String, dynamic> profileFromDraft(ProfileDraft draft) => draft.toJson();

  // An empty profile for creating a new one.
  ProfileDraft emptyDraft() => ProfileDraft.empty();
}
