import 'parsing_utils.dart';

// Condensed `status` event (every ~100ms). For live display only, does not
// need to be complete — the full time series comes from the debug file after
// the shot ends (see the ShotReadings table).
//
// `state` and `phase` are NOT the same (verified live during a profile
// start): `state` is the overall session status (e.g. "idle", "brewing" —
// stays "brewing" during the whole preheat/brew sequence), `phase` (raw field
// `name`) is the fine-grained intermediate stage (e.g. "idle", "heating",
// "extracting"). For UI states like "currently heating" use `phase`, not
// `state`.
class MachineStatus {
  final String state;
  final String phase;
  final double pressure;
  final double flow;
  final double weight;
  final double temp;
  final double gravimetricFlow;
  final int timeMs;
  final int profileTimeMs;
  final bool extracting;
  final String loadedProfile;
  final String profileId;

  const MachineStatus({
    required this.state,
    required this.phase,
    required this.pressure,
    required this.flow,
    required this.weight,
    required this.temp,
    required this.gravimetricFlow,
    required this.timeMs,
    required this.profileTimeMs,
    required this.extracting,
    required this.loadedProfile,
    required this.profileId,
  });

  factory MachineStatus.fromJson(Map<String, dynamic> json) {
    final sensors = Map<String, dynamic>.from(json['sensors'] as Map? ?? {});
    return MachineStatus(
      state: (json['state'] ?? json['name'] ?? 'unknown').toString(),
      phase: (json['name'] ?? json['state'] ?? 'unknown').toString(),
      pressure: parseDouble(sensors['p']),
      flow: parseDouble(sensors['f']),
      weight: parseDouble(sensors['w']),
      temp: parseDouble(sensors['t']),
      gravimetricFlow: parseDouble(sensors['g']),
      timeMs: (json['time'] as num?)?.toInt() ?? 0,
      profileTimeMs: (json['profile_time'] as num?)?.toInt() ?? 0,
      extracting: json['extracting'] as bool? ?? false,
      loadedProfile: (json['loaded_profile'] ?? '').toString(),
      profileId: (json['id'] ?? '').toString(),
    );
  }
}
