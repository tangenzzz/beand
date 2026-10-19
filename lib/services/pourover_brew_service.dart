import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../models/brew_plan.dart';
import '../models/brew_recipe.dart';
import '../scale/brew_scale.dart';
import 'brew_recipe_store.dart';
import 'live_shot_service.dart';
import 'shot_setup.dart';

/// Where the running brew currently is.
enum BrewState {
  /// Tared, waiting for the first water (the timer is not running yet).
  armed,

  /// Pouring up to the target weight of the current pour.
  pouring,

  /// Pause after a pour (wait_seconds in the recipe).
  waiting,

  /// Last pour reached, drawdown.
  drawdown,
}

// Pour over on the shared card base (LiveShotService): carousel jumps, the
// active card and the post card work exactly as for the machines (one shot
// card for all machines). The "machine" here is the scale: no start without
// a connected scale.
//
// Flow: Start → tare → [armed] → first water starts the timer (also the
// scale's own) → [pouring] until target weight → [waiting] pause from the
// recipe → next pour … → [drawdown] → runs on while the water drips through
// and is only saved via "Finish" → Post Brew. (Until 2026-10-17 it ended by
// itself once the weight was still — but the dripping water stays on the
// scale, so the weight is still long before the brew is done.)
class PourOverBrewService extends LiveShotService {
  PourOverBrewService({
    required this.scale,
    required this.recipes,
    required this.setup,
    required this.database,
  });

  final BrewScale scale;
  final BrewRecipeStore recipes;
  final ShotSetup setup;
  final AppDatabase database;

  /// Weight from which the first pour counts as started.
  static const startThreshold = 1.0;

  @override
  String get machineKey => 'pourover';

  @override
  bool get supportsAutoStart => false;

  @override
  bool get pulsesWhenReady => false;

  // The recipe may be changed until start.
  @override
  bool get profileLocked => stage != ShotStage.idle;

  double? _temperature;

  /// Water temperature: recipe value unless changed by hand.
  double? get temperature =>
      _temperature ?? (_manual ? null : recipe?.waterTempC);

  // ---- Manual ("freestyle") ----
  //
  // Without a recipe: no pour sequence, just a target water amount (toggle
  // in the command row). Internally this is a plan with ONE pour up to the
  // target — so the ring, the drawdown and the history work without
  // special cases. Like every brew it only ends via "Finish".
  static const manualPrefKey = 'pourover_manual';
  static const manualWaterPrefKey = 'pourover_manual_water';
  static const manualStepLabel = 'Free pour';
  static const _defaultManualRatio = 16.0;

  bool _manual = false;
  bool get manual => _manual;

  double? _manualWater;

  /// Target water in manual mode; without a custom setting dose × 16.
  double get manualWaterG =>
      _manualWater ??
      ((setup.doseGrams ?? 15) * _defaultManualRatio).roundToDouble();

  void setManual(bool value) {
    if (profileLocked || value == _manual) return;
    _manual = value;
    notifyListeners();
    _persist((p) => p.setBool(manualPrefKey, value));
  }

  void setManualWater(double grams) {
    _manualWater = grams.roundToDouble();
    notifyListeners();
    _persist((p) => p.setDouble(manualWaterPrefKey, _manualWater!));
  }

  static void _persist(Future<bool> Function(SharedPreferences) write) {
    SharedPreferences.getInstance().then(write).catchError((Object _) => false);
  }

  Future<void> _loadManual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _manual = prefs.getBool(manualPrefKey) ?? _manual;
      _manualWater = prefs.getDouble(manualWaterPrefKey) ?? _manualWater;
      notifyListeners();
    } catch (_) {}
  }

  BrewRecipe _manualRecipe(double dose) {
    final water = manualWaterG;
    return BrewRecipe(
      id: 'manual',
      name: 'Manual',
      brewer: '',
      doseG: dose,
      waterMl: water,
      grindSize: '',
      phases: [BrewPhase(label: manualStepLabel, waterG: water)],
      sourceName: '',
    );
  }

  void setTemperature(double? c) {
    _temperature = c;
    notifyListeners();
  }

  @override
  double? get targetTemperature => temperature;

  BrewRecipe? get recipe {
    final id = setup.profileId;
    return id == null ? null : recipes.byId(id);
  }

  /// Plan from recipe + configured dose. Frozen during the brew.
  BrewPlan? get plan => _runningPlan ?? _currentPlan();

  BrewPlan? _currentPlan() {
    if (_manual) {
      final dose = setup.doseGrams ?? 15;
      return BrewPlan(_manualRecipe(dose), doseG: dose);
    }
    final r = recipe;
    if (r == null) return null;
    return BrewPlan(r, doseG: setup.doseGrams ?? r.doseG);
  }

  void selectRecipe(BrewRecipe r) {
    if (profileLocked) return;
    setup.setProfile(r.id, r.name);
    // New recipe: dose and temperature from the recipe.
    setup.setDose(r.doseG);
    _temperature = null;
    notifyListeners();
  }

  // ---- Running brew ----
  BrewPlan? _runningPlan;
  BrewState _phase = BrewState.armed;
  BrewState get phase => _phase;
  int _stepIndex = 0;
  int get stepIndex => _stepIndex;
  DateTime? _startedAt;
  DateTime? _waitUntil;
  double _grams = 0;
  double get grams => _grams;
  double _flow = 0;
  double get flow => _flow;
  final _flowEstimator = FlowEstimator();
  StreamSubscription<ScaleReading>? _readingSub;
  Timer? _ticker;
  bool _saving = false;
  String? _lastError;
  String? get lastError => _lastError;

  BrewStep? get currentStep {
    final p = plan;
    if (p == null || p.steps.isEmpty) return null;
    return p.steps[math.min(_stepIndex, p.steps.length - 1)];
  }

  /// Grams in the current pour (for "11 g of 60 g").
  double get pouredInStep {
    final s = currentStep;
    if (s == null) return 0;
    return (_grams - s.startTotalG).clamp(0, s.waterG);
  }

  int get elapsedMs {
    final start = _startedAt;
    if (start == null) return 0;
    return clock.now().difference(start).inMilliseconds;
  }

  /// Seconds until the next pour is due (only in [BrewState.waiting]).
  double get waitLeftSeconds {
    final until = _waitUntil;
    if (until == null) return 0;
    return math.max(0, until.difference(clock.now()).inMilliseconds / 1000);
  }

  double get remainingSeconds {
    final p = plan;
    if (p == null) return 0;
    if (stage == ShotStage.idle) return p.plannedSeconds;
    return switch (_phase) {
      BrewState.armed => p.plannedSeconds,
      BrewState.pouring => p.remainingSeconds(
        _stepIndex,
        pouredInStep: pouredInStep,
      ),
      // During the pause _stepIndex already points at the next pour.
      BrewState.waiting => waitLeftSeconds + p.remainingSeconds(_stepIndex),
      BrewState.drawdown => 0,
    };
  }

  @override
  void start() {
    unawaited(_loadManual());
    scale.addListener(_onScale);
    setup.addListener(_onScale);
    recipes.addListener(_onScale);
    _onScale();
  }

  void _onScale() {
    stabilized = scale.isConnected && plan != null;
    notifyListeners();
  }

  @override
  Future<bool> startShot() async {
    final p = _currentPlan();
    if (p == null || !scale.isConnected || stage != ShotStage.idle) {
      return false;
    }
    _lastError = null;
    try {
      await scale.tare();
    } catch (e) {
      _lastError = 'Could not tare the scale.';
      notifyListeners();
      return false;
    }
    _scaleTimer(scale.resetTimer);
    _runningPlan = p;
    _phase = BrewState.armed;
    _stepIndex = 0;
    _startedAt = null;
    _waitUntil = null;
    _grams = 0;
    _flow = 0;
    _flowEstimator.reset();
    resetReadings();
    // The first packets after the tare command often still carry the old
    // weight — only count from a value close to 0.
    var tared = false;
    _readingSub = scale.readings.listen((r) {
      if (!tared) {
        if (r.grams.abs() > startThreshold) return;
        tared = true;
      }
      _onReading(r);
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    applyStage(ShotStage.running);
    notifyListeners();
    return true;
  }

  void _onReading(ScaleReading r) {
    final p = _runningPlan;
    if (p == null) return;
    if (_phase == BrewState.armed) {
      if (r.grams < startThreshold) return;
      _startedAt = r.at;
      _phase = BrewState.pouring;
      markExtracting(true);
      _scaleTimer(scale.startTimer);
    }
    final ms = r.at.difference(_startedAt!).inMilliseconds;
    _grams = math.max(0, r.grams);
    _flowEstimator.add(ms, _grams);
    _flow = _flowEstimator.gramsPerSecond;

    final reached = p.stepIndexFor(_grams);
    if (_phase == BrewState.pouring && reached > _stepIndex) {
      final done = p.steps[_stepIndex];
      _stepIndex = reached;
      if (_stepIndex >= p.steps.length) {
        _phase = BrewState.drawdown;
      } else {
        _phase = BrewState.waiting;
        _waitUntil = r.at.add(
          Duration(milliseconds: ((done.waitSeconds ?? 0) * 1000).round()),
        );
      }
    } else if (_phase == BrewState.waiting && reached > _stepIndex) {
      // Kept pouring without waiting for the pause.
      _stepIndex = reached;
      if (_stepIndex >= p.steps.length) _phase = BrewState.drawdown;
    }

    addReading(
      timeMs: ms,
      pressure: 0,
      flow: _flow,
      weight: _grams,
      stage: currentStep?.label ?? '',
    );
    notifyListeners();
  }

  void _tick() {
    final now = clock.now();
    if (_phase == BrewState.waiting) {
      final until = _waitUntil;
      // Pause over → next pour. If water is already coming, _onReading has
      // advanced the step.
      if (until != null && !now.isBefore(until)) {
        _phase = BrewState.pouring;
        _waitUntil = null;
      }
    }
    // Without new packets (scale gone) the flow would otherwise never drop
    // to 0.
    if (_startedAt != null) {
      _flowEstimator.add(now.difference(_startedAt!).inMilliseconds, _grams);
      _flow = _flowEstimator.gramsPerSecond;
    }
    notifyListeners();
  }

  /// "Finish": saves immediately. No water poured = abort.
  @override
  Future<bool> stopShot() async {
    if (stage != ShotStage.running || _saving) return false;
    _saving = true;
    try {
      _stopListening();
      markExtracting(false);
      if (_startedAt != null) _scaleTimer(scale.stopTimer);
      if (_startedAt == null || !hasReadings) {
        _runningPlan = null;
        applyStage(ShotStage.idle);
        notifyListeners();
        return true;
      }
      await _save();
      _runningPlan = null;
      applyStage(ShotStage.purging);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('PourOverBrewService: save failed $e');
      _lastError = 'Could not save the brew.';
      _runningPlan = null;
      applyStage(ShotStage.idle);
      notifyListeners();
      return false;
    } finally {
      _saving = false;
    }
  }

  // No purge for pour over.
  @override
  Future<bool> purge() async => true;

  @override
  void confirmPostShot() {
    super.confirmPostShot();
    // Only end the finished brew — a new one may already be running when
    // the old one is saved late.
    if (stage == ShotStage.purging) applyStage(ShotStage.idle);
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _runningPlan!;
    final readings = List.of(liveReadings);
    final snap = setup.snapshot();
    await database.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: _startedAt!,
        machine: const Value('pourover'),
        beanId: Value(snap.beanId),
        profileName: Value(p.recipe.name),
        doseGrams: Value(p.doseG),
        grindSize: Value(snap.grindText),
        grindZero: Value(snap.grindZero),
        grinder: Value(snap.grinder),
        burrs: Value(snap.burrs),
        brewedWith: Value(snap.brewedWith),
        brewChainId: Value(snap.brewChainId),
        finalWeight: Value(_grams),
        durationMs: Value(readings.isEmpty ? elapsedMs : readings.last.timeMs),
        profileTemp: Value(temperature),
      ),
      [
        for (final r in readings)
          (shotId) => ShotReadingsCompanion.insert(
            shotId: shotId,
            timeMs: r.timeMs,
            weight: Value(r.weight),
            gravimetricFlow: Value(r.flow),
            stage: Value(r.stage),
          ),
      ],
    );
  }

  // The scale's timer is a nice-to-have: a lost command must not disturb
  // the brew.
  static void _scaleTimer(Future<void> Function() command) {
    unawaited(command().catchError((Object _) {}));
  }

  void _stopListening() {
    _readingSub?.cancel();
    _readingSub = null;
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopListening();
    scale.removeListener(_onScale);
    setup.removeListener(_onScale);
    recipes.removeListener(_onScale);
    super.dispose();
  }
}
