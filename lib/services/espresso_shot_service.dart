import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;

import '../database/database.dart';
import '../machines/espresso_machine.dart';
import '../models/machine_profile.dart';
import '../scale/brew_scale.dart';
import '../sensors/pressure_sensor.dart';
import 'connection_log.dart';
import 'live_shot_service.dart';
import 'shot_setup.dart';

/// Shots on an espresso machine the app does not talk to (Home → Espresso).
///
/// The user starts and stops the shot in the app; the app is the clock.
/// What is connected is recorded alongside: the Bluetooth scale gives the
/// yield and its flow, a pressure sensor (Pressensor) the pressure. With
/// neither, only the time is measured, and yield and time can be entered in
/// the Post card.
///
/// Cycle as on the machines: PRE → Start → LIVE → Stop saves → POST → Save
/// → PRE.
class EspressoShotService extends LiveShotService {
  EspressoShotService({
    required this.scale,
    required this.sensor,
    required this.setup,
    required this.database,
  });

  final BrewScale scale;
  final PressureSensor sensor;
  final ShotSetup setup;
  final AppDatabase database;

  static const key = 'espresso';

  /// Stored as the profile name: dose and grind are carried over from the
  /// last shot by profile name (PreShotCard), and this mode has one.
  static const profileName = 'Espresso';

  /// Sampling of the live curve.
  static const sampleEvery = Duration(milliseconds: 200);

  /// Shorter than this counts as a mis-tap, not a shot.
  static const minShot = Duration(seconds: 2);

  @override
  String get machineKey => key;

  @override
  double? get targetTemperature => null;

  @override
  bool get supportsAutoStart => false;

  @override
  bool get pulsesWhenReady => false;

  @override
  bool get startsByHand => true;

  @override
  bool get profileLocked => stage == ShotStage.running;

  // ---- Live values for the hero ----

  DateTime? _startedAt;
  Timer? _ticker;
  bool _saving = false;
  String? _lastError;
  String? get lastError => _lastError;

  double? _grams;
  double? _flow;

  /// Weight in the cup during the shot; before it what is on the scale.
  double? get grams => stage == ShotStage.running ? _grams : scale.grams;

  /// Gravimetric flow in g/s (scale only).
  double? get flow => stage == ShotStage.running ? _flow : null;

  double? get bar => sensor.bar;

  int get elapsedMs {
    final start = _startedAt;
    if (start == null) return 0;
    if (stage != ShotStage.running) {
      return liveReadings.isEmpty ? 0 : liveReadings.last.timeMs;
    }
    return clock.now().difference(start).inMilliseconds;
  }

  bool get hasDevice => scale.isConnected || sensor.isConnected;

  @override
  void start() {
    if (setup.profileName != profileName) setup.setProfile(key, profileName);
    scale.addListener(_onDevice);
    sensor.addListener(_onDevice);
    stabilized = true;
  }

  void _onDevice() => notifyListeners();

  Future<void> tare() async {
    if (!scale.isConnected) return;
    try {
      await scale.tare();
    } catch (e) {
      _lastError = 'Could not tare the scale.';
      notifyListeners();
    }
  }

  // Weights of the last second for the flow.
  final _recent = <({int ms, double g})>[];

  @override
  Future<bool> startShot() async {
    if (stage == ShotStage.running) return false;
    _lastError = null;
    if (scale.isConnected) {
      try {
        await scale.tare();
      } catch (_) {
        // The shot still runs; the yield may start off by the cup.
      }
      _scaleTimer(scale.resetTimer);
      _scaleTimer(scale.startTimer);
    }
    resetReadings();
    _recent.clear();
    _grams = null;
    _flow = null;
    _startedAt = clock.now();
    markExtracting(true);
    _ticker = Timer.periodic(sampleEvery, (_) => _sample());
    applyStage(ShotStage.running);
    notifyListeners();
    return true;
  }

  void _sample() {
    final start = _startedAt;
    if (start == null) return;
    final ms = clock.now().difference(start).inMilliseconds;
    double? weight;
    double? flow;
    if (scale.isConnected && scale.grams != null) {
      // The first packets after the tare may still carry the cup.
      weight = math.max(0, scale.grams!);
      _recent.add((ms: ms, g: weight));
      _recent.removeWhere((r) => ms - r.ms > 1000);
      final first = _recent.first;
      flow = ms - first.ms >= 400
          ? math.max(0, (weight - first.g) / ((ms - first.ms) / 1000))
          : 0;
    }
    _grams = weight;
    _flow = flow;
    addReading(
      timeMs: ms,
      pressure: sensor.isConnected ? sensor.bar : null,
      flow: flow,
      weight: weight,
      stage: profileName,
    );
    notifyListeners();
  }

  /// Stop: saves the shot and goes on to Post. A mis-tap (under
  /// [minShot]) goes back to Pre without a shot.
  @override
  Future<bool> stopShot() async {
    if (stage != ShotStage.running || _saving) return false;
    _saving = true;
    try {
      _sample();
      _ticker?.cancel();
      _ticker = null;
      markExtracting(false);
      if (scale.isConnected) _scaleTimer(scale.stopTimer);
      final ms = liveReadings.isEmpty ? 0 : liveReadings.last.timeMs;
      if (ms < minShot.inMilliseconds) {
        resetReadings();
        _startedAt = null;
        applyStage(ShotStage.idle);
        notifyListeners();
        return true;
      }
      await _save(ms);
      applyStage(ShotStage.purging);
      notifyListeners();
      return true;
    } catch (e) {
      ConnectionLog.failure('espresso save', e);
      _lastError = 'Could not save the shot.';
      applyStage(ShotStage.idle);
      notifyListeners();
      return false;
    } finally {
      _saving = false;
    }
  }

  // Nothing to purge on a machine the app does not run.
  @override
  Future<bool> purge() async => false;

  @override
  void confirmPostShot() {
    super.confirmPostShot();
    if (stage == ShotStage.purging) applyStage(ShotStage.idle);
    notifyListeners();
  }

  Future<void> _save(int durationMs) async {
    final readings = List.of(liveReadings);
    final snap = setup.snapshot();
    final weights = readings.map((r) => r.weight).whereType<double>();
    await database.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: _startedAt!,
        machine: const Value(key),
        beanId: Value(snap.beanId),
        profileName: const Value(profileName),
        doseGrams: Value(snap.doseGrams),
        grindSize: Value(snap.grindText),
        grindZero: Value(snap.grindZero),
        grindMarker: Value(snap.grindMarker),
        grinder: Value(snap.grinder),
        burrs: Value(snap.burrs),
        brewedWith: Value(snap.brewedWith),
        brewChainId: Value(snap.brewChainId),
        finalWeight: Value(weights.isEmpty ? null : weights.last),
        durationMs: Value(durationMs),
      ),
      // Without any device there is no curve worth keeping.
      [
        if (readings.any((r) => r.weight != null || r.pressure != null))
          for (final r in readings)
            (shotId) => ShotReadingsCompanion.insert(
              shotId: shotId,
              timeMs: r.timeMs,
              weight: Value(r.weight),
              gravimetricFlow: Value(r.flow),
              flow: Value(r.flow),
              pressure: Value(r.pressure),
              stage: Value(r.stage),
            ),
      ],
    );
  }

  static void _scaleTimer(Future<void> Function() command) {
    unawaited(command().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    scale.removeListener(_onDevice);
    sensor.removeListener(_onDevice);
    super.dispose();
  }
}

/// Stand-in for the machine in the Espresso home: the shared cards ask the
/// machine for its profiles and key. There is none to talk to, so it has
/// no profiles and is always "connected".
class ManualEspressoMachine extends EspressoMachine {
  @override
  String get displayName => 'Espresso';

  @override
  String get machineKey => EspressoShotService.key;

  @override
  String get host => '';

  @override
  MachineConnectionState get connectionState =>
      MachineConnectionState.connected;

  @override
  String? get lastError => null;

  @override
  MachineCapabilities get capabilities =>
      const MachineCapabilities(temperatureSensors: 0);

  @override
  MachineLiveState get liveState => MachineLiveState.empty;

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void updateHost(String host) {}

  @override
  Future<List<MachineProfile>> fetchProfiles() async => const [];

  @override
  Future<bool> selectProfile(String id) async => false;

  @override
  Future<bool> sendCommand(MachineCommand command) async => false;

  @override
  Future<ProfileSaveResult> uploadProfile(Map<String, dynamic> json) async =>
      const ProfileSaveResult.failed('No machine');

  @override
  Future<ProfileSaveResult> deleteProfile(String id) async =>
      const ProfileSaveResult.failed('No machine');

  @override
  Future<ProfileSaveResult> reorderProfiles(List<String> ids) async =>
      const ProfileSaveResult.failed('No machine');

  @override
  List<({String label, String url})> get profileSites => const [];
}
