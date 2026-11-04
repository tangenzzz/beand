import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../models/brew_plan.dart';
import '../models/brew_recipe.dart';
import '../models/gear.dart';
import '../scale/brew_scale.dart';
import 'brew_recipe_store.dart';
import 'live_shot_service.dart';
import 'meticulous_dial_brews.dart';
import 'pourover_setup.dart';
import 'shot_setup.dart';

/// Who leads a Pour Over brew on the Meticulous' scale (Settings → Pour
/// Over → Meticulous). The machine's own Pour Over mode can't be steered
/// from outside (no profile choice, steps stay in the dial — checked
/// 2026-11-04), so the two are kept apart instead of mixed.
enum MeticulousPourMode {
  /// The dial leads: the app shows weight, flow and time live and takes
  /// the finished brew from the machine, combined with Pre Brew.
  machine,

  /// Only the scale: the app leads with its own steps, tare and timer.
  scaleOnly,
}

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

  /// Brewer lifted off (Meticulous): the timer has stopped. Scale only:
  /// waiting for the server with the coffee to weigh the beverage. Machine:
  /// waiting for the dial to finish and send the brew.
  measuring,
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
      final auto = prefs.getBool(autoPrefKey) ?? _auto;
      if (auto != _auto) {
        _auto = auto;
        if (auto) prep.restart();
        _syncPrep();
      }
      final mode = MeticulousPourMode.values
          .where((m) => m.name == prefs.getString(meticulousModePrefKey))
          .firstOrNull;
      if (mode != null && mode != _meticulousMode) {
        _meticulousMode = mode;
        _applyMode();
      }
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

  // Stand-in plan while the dial leads: one open pour the app never
  // reaches, so it shows weight and flow without targets.
  static final _dialRecipe = BrewRecipe(
    id: 'meticulous-dial',
    name: 'Meticulous',
    brewer: '',
    doseG: 15,
    waterMl: 2000,
    grindSize: '',
    phases: const [BrewPhase(label: 'Pour', waterG: 2000)],
    sourceName: '',
  );

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

  // ---- Setup steps on the Meticulous' scale ----
  //
  // Server → tare → brewer → tare → coffee → tare, like the machine's own
  // Pour Over mode. Only while the Pour Over view is on screen
  // ([setPrepVisible]) — otherwise putting a cup on the tray for an
  // espresso would tare the machine. Start Brew works at any step.
  //
  // With the Meticulous the machine's dial leads (user wish 2026-11-03):
  // the app follows its tares instead of taring itself, then starts the
  // brew by itself with the first water — like the machine does.
  late final PourOverSetup prep = PourOverSetup(
    tare: () => scale.tare(),
    targetDose: () => setup.doseGrams ?? recipe?.doseG,
  )..addListener(_onPrep);

  bool _prepVisible = false;
  StreamSubscription<ScaleReading>? _prepSub;
  StreamSubscription<ScaleReading>? _armSub;

  // ---- Who leads on the Meticulous ----
  static const meticulousModePrefKey = 'pourover_meticulous_mode';
  MeticulousPourMode _meticulousMode = MeticulousPourMode.machine;
  MeticulousPourMode get meticulousMode => _meticulousMode;

  /// The Meticulous' dial leads the brew (Machine mode).
  bool get dialLeads =>
      scale.isMachineScale && _meticulousMode == MeticulousPourMode.machine;

  void setMeticulousMode(MeticulousPourMode mode) {
    if (mode == _meticulousMode || stage != ShotStage.idle) return;
    _meticulousMode = mode;
    _applyMode();
    if (_auto && scale.isMachineScale && mode == MeticulousPourMode.scaleOnly) {
      prep.restart();
    }
    notifyListeners();
    _persist((p) => p.setString(meticulousModePrefKey, mode.name));
  }

  // Machine mode: only the machine's profiles (the dial picks one anyway);
  // Scale only: the machine's profiles AND the checked recipes.
  void _applyMode() {
    recipes.setUseMachine(
      scale.isMachineScale,
      alsoRecipes: _meticulousMode == MeticulousPourMode.scaleOnly,
    );
    _syncPrep();
    _syncDial();
  }

  /// Grams of water that start the brew by themselves after the steps.
  static const autoStartGrams = 2.0;

  // ---- Auto (any scale the app leads with) ----
  //
  // On: the steps weigh server, brewer and coffee by themselves (tare after
  // each), the coffee becomes the dose, the first water starts the brew and
  // lifting the brewer ends it with the coffee weighed (the yield). Off:
  // enter everything by hand, Start Brew waits for the water, Finish ends.
  // Same for a Bluetooth scale and the Meticulous in Scale only mode (user
  // 2026-11-04).
  static const autoPrefKey = 'pourover_auto';
  bool _auto = false;
  bool get auto => _auto;

  void setAuto(bool value) {
    if (value == _auto || stage != ShotStage.idle) return;
    _auto = value;
    if (value) prep.restart();
    _syncPrep();
    notifyListeners();
    _persist((p) => p.setBool(autoPrefKey, value));
  }

  /// The steps went through to the coffee: the scale stands at zero with
  /// everything on it, the next weight is water.
  bool get prepComplete =>
      _auto && !dialLeads && prep.done && prep.coffeeG != null;
  double? _prepCoffeeTaken;

  /// Steps are shown/running.
  bool get prepActive =>
      _auto &&
      !dialLeads &&
      scale.isConnected &&
      stage == ShotStage.idle &&
      !prep.done;

  void setPrepVisible(bool visible) {
    if (visible == _prepVisible) return;
    _prepVisible = visible;
    if (visible) {
      prep.resume();
      if (dialLeads && stage == ShotStage.idle) {
        unawaited(importLastDialBrew());
      }
      // Profiles may have been added on the machine in the meantime.
      if (recipes.useMachine && scale.isConnected) {
        unawaited(recipes.refreshMachine());
      }
    }
    _syncPrep();
  }

  /// Long press on "Auto": start the steps again.
  void restartPrep() {
    if (stage != ShotStage.idle || !_auto) return;
    prep.restart();
    _syncPrep();
  }

  /// Tare in the command row: during the steps it records the current step
  /// (and tares), otherwise a plain tare.
  Future<void> tare() async {
    if (prepActive) return prep.confirm();
    try {
      await scale.tare();
    } catch (_) {
      _lastError = 'Could not tare the scale.';
      notifyListeners();
    }
  }

  void _syncPrep() {
    final listen = prepActive && _prepVisible;
    if (listen && _prepSub == null) {
      _prepSub = scale.readings.listen(prep.feed);
    } else if (!listen && _prepSub != null) {
      _prepSub!.cancel();
      _prepSub = null;
    }
    // After the steps: the first water starts the brew (timer, ring, Live
    // card) — like the machine's own Pour Over mode.
    final arm = prepComplete && stage == ShotStage.idle && scale.isConnected;
    if (arm && _armSub == null) {
      _armSub = scale.readings.listen((r) {
        if (r.grams >= autoStartGrams && stage == ShotStage.idle) {
          _armSub?.cancel();
          _armSub = null;
          unawaited(_autoStart(r));
        }
      });
    } else if (!arm && _armSub != null) {
      _armSub!.cancel();
      _armSub = null;
    }
  }

  Future<void> _autoStart(ScaleReading first) async {
    if (await startShot()) _onReading(first);
  }

  /// The brewer recognised by its weight in the setup steps (My Coffee
  /// Desk → brewer → Weight), null if none matched.
  Gear? _detectedBrewer;
  Gear? get detectedBrewer => _detectedBrewer;
  double? _prepBrewerTaken;

  void _onPrep() {
    // Weighed brewer: which one is it? Its chain goes into Pre Brew (user
    // 2026-11-04).
    final brewer = prep.brewerG;
    if (brewer == null) {
      _detectedBrewer = null;
      _prepBrewerTaken = null;
    } else if (brewer != _prepBrewerTaken) {
      _prepBrewerTaken = brewer;
      final store = setup.gear;
      final found = store?.brewerByWeight(brewer);
      _detectedBrewer = found;
      if (found != null) {
        final chain = store!.chainForBrewer(found, currentId: setup.chain?.id);
        if (chain != null) setup.setChain(chain.id);
      }
    }
    // Weighed coffee becomes the dose of this brew.
    final coffee = prep.coffeeG;
    if (coffee != null &&
        coffee != _prepCoffeeTaken &&
        prep.step.index > SetupStep.coffee.index) {
      _prepCoffeeTaken = coffee;
      setup.setDose((coffee * 10).roundToDouble() / 10);
    }
    _syncPrep();
    notifyListeners();
  }

  bool? _wasMachineScale;

  // Switching to the Meticulous: its profiles instead of brew-recipes, and
  // the steps from the start.
  void _onSourceChange() {
    final machine = scale.isMachineScale;
    if (machine == _wasMachineScale) return;
    final first = _wasMachineScale == null;
    _wasMachineScale = machine;
    _applyMode();
    // Another scale: the steps from the start.
    if (_auto && !first) prep.restart();
  }

  // The chosen profile belongs to the other list (scale switched) or is
  // gone: take the first one of the list in use.
  void _ensureRecipe() {
    if (profileLocked || _manual || recipe != null) return;
    if (recipes.useMachine && !recipes.machineLoaded) return;
    final list = recipes.enabledRecipes;
    if (list.isEmpty) return;
    selectRecipe(list.first);
  }

  /// Plan from recipe + configured dose. Frozen during the brew.
  BrewPlan? get plan => _runningPlan ?? _currentPlan();

  BrewPlan? _currentPlan() {
    // The dial picks the profile; live only weight, flow and time.
    if (dialLeads) return BrewPlan(_dialRecipe);
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
  Map<String, Object?>? _runningPrep;
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

  /// Brew over and saved, the Live card shows the result until "Rate brew"
  /// (no automatic jump to Post Brew — user 2026-11-04).
  bool get brewDone => stage == ShotStage.awaitingPurge;

  // Duration of the finished brew (as saved), for the Live card.
  int? _finalMs;

  int get elapsedMs {
    if (brewDone && _finalMs != null) return _finalMs!;
    final start = _startedAt;
    if (start == null) return 0;
    // Stopped at the lift of the brewer.
    if (_phase == BrewState.measuring && liveReadings.isNotEmpty) {
      return liveReadings.last.timeMs;
    }
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
      BrewState.drawdown || BrewState.measuring => 0,
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

  bool _wasConnected = false;

  void _onScale() {
    _onSourceChange();
    // Machine (re)connected: fetch its profiles again (e.g. app started
    // before the machine was reachable).
    final connectedNow = scale.isConnected && !_wasConnected;
    _wasConnected = scale.isConnected;
    if (connectedNow && recipes.useMachine) {
      unawaited(recipes.refreshMachine());
    }
    // A brew made on the dial while the app was away.
    if (connectedNow && dialLeads) unawaited(importLastDialBrew());
    _ensureRecipe();
    stabilized = scale.isConnected && plan != null;
    _syncPrep();
    _syncDial();
    notifyListeners();
  }

  @override
  Future<bool> startShot() async {
    final p = _currentPlan();
    if (p == null || !scale.isConnected || stage != ShotStage.idle) {
      return false;
    }
    _lastError = null;
    // Keep what the setup steps weighed (also when started before the
    // last step).
    _runningPrep = _auto && !dialLeads ? prep.toJson() : null;
    // After the dial's steps the scale is already at zero with everything
    // on it (a tare now would also hit the first water when started by
    // the water itself).
    final tareFirst = !prepComplete;
    _setupG = prepComplete ? prep.setupG : null;
    if (_auto && !prep.done) prep.skip();
    if (tareFirst) {
      try {
        await scale.tare();
      } catch (e) {
        _lastError = 'Could not tare the scale.';
        notifyListeners();
        return false;
      }
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
    var tared = !tareFirst;
    _peakWater = 0;
    _liftSince = null;
    _serverMissing = false;
    _beverageG = null;
    _finalMs = null;
    _measureWindow.clear();
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
    if (_phase == BrewState.measuring) {
      _measure(r);
      return;
    }
    if (_phase != BrewState.armed && _watchLift(r)) return;
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

  // ---- Machine mode: the dial leads ----
  //
  // Live the app only knows the weight: [DialBrewDetector] recognises the
  // first water (after a dial tare) and the lift of the brewer. The real
  // brew comes from the machine afterwards (`/history/pour-over/last`) and
  // is saved combined with Pre Brew (bean, grinder, grind, chain).

  /// Fetches the dial's brews; set in main.dart.
  MeticulousDialBrews? dialBrews;

  final _detector = DialBrewDetector();
  StreamSubscription<ScaleReading>? _dialIdleSub;
  StreamSubscription<double>? _dialTareSub;
  bool _dialLive = false;
  Timer? _dialPoll;
  DateTime? _dialWaitSince;
  bool _importing = false;

  /// How long the app waits for the machine's brew after the lift.
  static const dialWait = Duration(minutes: 5);
  Duration dialPollEvery = const Duration(seconds: 2);

  /// The live brew is waiting for the machine to send it.
  bool get waitingForMachine => _dialLive && _phase == BrewState.measuring;

  void _syncDial() {
    final listen = dialLeads && stage == ShotStage.idle && scale.isConnected;
    if (listen && _dialIdleSub == null) {
      _detector.reset();
      _dialIdleSub = scale.readings.listen(_onDialIdle);
      _dialTareSub = scale.deviceTares.listen((_) => _detector.deviceTared());
    } else if (!listen && _dialIdleSub != null) {
      _dialIdleSub!.cancel();
      _dialIdleSub = null;
      _dialTareSub?.cancel();
      _dialTareSub = null;
    }
  }

  void _onDialIdle(ScaleReading r) {
    final rise = _detector.feedIdle(r);
    if (rise != null) _beginDial(rise);
  }

  void _beginDial(List<ScaleReading> rise) {
    if (stage != ShotStage.idle) return;
    _runningPlan = BrewPlan(_dialRecipe);
    _runningPrep = null;
    _setupG = null;
    _dialLive = true;
    _beverageG = null;
    _finalMs = null;
    _phase = BrewState.pouring;
    _stepIndex = 0;
    _startedAt = rise.first.at;
    _waitUntil = null;
    _grams = 0;
    _flow = 0;
    _flowEstimator.reset();
    resetReadings();
    _syncDial();
    applyStage(ShotStage.running);
    markExtracting(true);
    for (final r in rise) {
      _onDialReading(r);
    }
    _readingSub = scale.readings.listen(_onDialReading);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    notifyListeners();
  }

  void _onDialReading(ScaleReading r) {
    if (_phase == BrewState.measuring || _startedAt == null) return;
    final liftAt = _detector.feedRunning(r);
    if (liftAt != null) {
      _awaitDialBrew();
      return;
    }
    // Lifting: hold back until confirmed or back on the scale.
    if (r.grams < _grams - DialBrewDetector.liftDrop) return;
    final ms = r.at.difference(_startedAt!).inMilliseconds;
    _grams = math.max(0, r.grams);
    _flowEstimator.add(ms, _grams);
    _flow = _flowEstimator.gramsPerSecond;
    addReading(timeMs: ms, pressure: 0, flow: _flow, weight: _grams, stage: '');
    notifyListeners();
  }

  void _awaitDialBrew() {
    _phase = BrewState.measuring;
    markExtracting(false);
    _flow = 0;
    _dialWaitSince = clock.now();
    _readingSub?.cancel();
    _readingSub = null;
    _dialPoll?.cancel();
    _dialPoll = Timer.periodic(dialPollEvery, (_) => _pollDialBrew());
    unawaited(_pollDialBrew());
    notifyListeners();
  }

  Future<void> _pollDialBrew() async {
    if (!waitingForMachine || _importing) return;
    final source = dialBrews;
    final since = _dialWaitSince ?? clock.now();
    if (source != null) {
      _importing = true;
      try {
        final brew = await source.fetchLast();
        final start = _startedAt;
        if (brew != null &&
            start != null &&
            brew.startedAt.difference(start).abs() <
                const Duration(minutes: 10) &&
            !(await database.knownExternalIds()).contains(brew.externalId)) {
          await _saveDialBrew(brew);
          // The machine's numbers on the Live card.
          _finalMs = brew.durationMs ?? _finalMs;
          if (brew.waterG != null) _grams = brew.waterG!;
          _beverageG = brew.beverageG;
          _finishDialLive();
          return;
        }
      } catch (e) {
        debugPrint('PourOverBrewService: dial brew not fetched: $e');
      } finally {
        _importing = false;
      }
    }
    if (clock.now().difference(since) >= dialWait) {
      // The machine sent nothing — keep what the app measured.
      _lastError = 'No brew from the machine — saved what the app measured.';
      await stopShot();
    }
  }

  void _finishDialLive() {
    _dialPoll?.cancel();
    _dialPoll = null;
    _dialLive = false;
    _stopListening();
    _finalMs ??= liveReadings.isEmpty ? null : liveReadings.last.timeMs;
    applyStage(ShotStage.awaitingPurge);
    _syncDial();
    notifyListeners();
  }

  /// Takes the machine's latest Pour Over brew into the history if it is
  /// new (e.g. brewed on the dial while the app was away). True when one
  /// was added.
  Future<bool> importLastDialBrew() async {
    final source = dialBrews;
    if (source == null || _importing || stage != ShotStage.idle) return false;
    _importing = true;
    try {
      final brew = await source.fetchLast();
      if (brew == null) return false;
      if ((await database.knownExternalIds()).contains(brew.externalId)) {
        return false;
      }
      if (stage != ShotStage.idle) return false;
      await _saveDialBrew(brew);
      return true;
    } catch (e) {
      debugPrint('PourOverBrewService: dial brew not fetched: $e');
      return false;
    } finally {
      _importing = false;
    }
  }

  // The machine's brew + Pre Brew: what was weighed and brewed comes from
  // the machine, bean / grinder / grind / chain from the app.
  Future<void> _saveDialBrew(DialBrew b) async {
    final snap = setup.snapshot();
    final dose = b.doseG ?? setup.doseGrams;
    await database.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: b.startedAt,
        machine: const Value('pourover'),
        externalId: Value(b.externalId),
        beanId: Value(snap.beanId),
        profileName: Value(b.profileName),
        doseGrams: Value(dose),
        grindSize: Value(snap.grindText),
        grindZero: Value(snap.grindZero),
        grindMarker: Value(snap.grindMarker),
        grinder: Value(snap.grinder),
        burrs: Value(snap.burrs),
        brewedWith: Value(snap.brewedWith),
        brewChainId: Value(snap.brewChainId),
        finalWeight: Value(b.waterG),
        beverageGrams: Value(b.beverageG),
        durationMs: Value(b.durationMs),
        profileTemp: Value(b.temperatureC),
        rawDebugJson: Value(b.raw),
      ),
      [
        for (final r in b.samples)
          (shotId) => ShotReadingsCompanion.insert(
            shotId: shotId,
            timeMs: r.ms,
            weight: Value(r.grams),
            gravimetricFlow: Value(r.flow),
            stage: Value(b.stageAt(r.ms)),
          ),
      ],
    );
    if (dose != null) setup.setDose(dose);
  }

  // ---- End by lifting the brewer (Meticulous, after the steps) ----
  //
  // Like the machine's own Pour Over mode (meticulous-dial,
  // brewWeightFilter.ts): lifting the brewer takes brewer, grounds and
  // retained water away — the weight falls by more than
  // max(28 g, 55 % of brewer + coffee) below the most water poured and
  // stays there for 3 s. The time stops at the lift. Then the server with
  // the coffee has to stand still on the scale: beverage = weight + brewer
  // + coffee (the zero was set with all of them on it).
  static const liftConfirm = Duration(seconds: 3);
  static const measureSteady = Duration(milliseconds: 700);
  static const measureBand = 1.5;

  double? _setupG;
  double _peakWater = 0;
  DateTime? _liftSince;
  bool _serverMissing = false;
  double? _beverageG;
  final _measureWindow = <ScaleReading>[];

  /// After the lift nothing usable stands on the scale (everything taken
  /// off) — the server with the coffee has to go back.
  bool get serverMissing => _serverMissing;

  /// Weighed beverage (null until measured).
  double? get beverageG => _beverageG;

  bool get _autoEnd => _setupG != null;

  double get _liftThreshold => math.max(28, (_setupG ?? 0) * 0.55);

  /// True while a lift is being confirmed (the reading is held back).
  bool _watchLift(ScaleReading r) {
    if (!_autoEnd) return false;
    final g = r.grams;
    if (_liftSince == null) _peakWater = math.max(_peakWater, g);
    final below = _peakWater >= 20 && g <= _peakWater - _liftThreshold;
    if (!below) {
      _liftSince = null;
      return false;
    }
    final since = _liftSince ??= r.at;
    if (r.at.difference(since) >= liftConfirm) _beginMeasuring();
    return true;
  }

  void _beginMeasuring() {
    _phase = BrewState.measuring;
    markExtracting(false);
    if (_startedAt != null) _scaleTimer(scale.stopTimer);
    _flow = 0;
    _measureWindow.clear();
    notifyListeners();
  }

  void _measure(ScaleReading r) {
    _measureWindow.add(r);
    while (_measureWindow.length > 2 &&
        r.at.difference(_measureWindow.first.at) > measureSteady) {
      _measureWindow.removeAt(0);
    }
    if (_measureWindow.length < 3 ||
        r.at.difference(_measureWindow.first.at) <
            measureSteady - const Duration(milliseconds: 150)) {
      return;
    }
    var lo = double.infinity, hi = -double.infinity;
    for (final m in _measureWindow) {
      lo = math.min(lo, m.grams);
      hi = math.max(hi, m.grams);
    }
    if (hi - lo > measureBand) return;
    final water = _grams;
    final beverage = r.grams + (_setupG ?? 0);
    if (beverage > water + 8) {
      // Everything is still on the scale — it was a wobble, not a lift.
      _phase = _stepIndex >= (_runningPlan?.steps.length ?? 0)
          ? BrewState.drawdown
          : BrewState.pouring;
      _peakWater = math.max(0, r.grams);
      _liftSince = null;
      markExtracting(true);
      notifyListeners();
      return;
    }
    if (beverage < math.max(8, water * 0.2)) {
      if (!_serverMissing) {
        _serverMissing = true;
        notifyListeners();
      }
      return;
    }
    _beverageG = (beverage * 10).roundToDouble() / 10;
    _serverMissing = false;
    unawaited(stopShot());
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
    if (_startedAt != null && _phase != BrewState.measuring) {
      _flowEstimator.add(now.difference(_startedAt!).inMilliseconds, _grams);
      _flow = _flowEstimator.gramsPerSecond;
    }
    notifyListeners();
  }

  /// "Finish": saves immediately. No water poured = abort.
  @override
  Future<bool> stopShot() async {
    if (stage != ShotStage.running || _saving) return false;
    // Dial leads: "Finish" means the pouring is over — wait for the
    // machine's brew; a second Finish keeps what the app measured.
    if (_dialLive && _phase != BrewState.measuring) {
      _awaitDialBrew();
      return true;
    }
    _dialPoll?.cancel();
    _dialLive = false;
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
      _finalMs = liveReadings.isEmpty ? elapsedMs : liveReadings.last.timeMs;
      await _save();
      // The Live card keeps the result; "Rate brew" goes on to Post Brew.
      applyStage(ShotStage.awaitingPurge);
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

  // No purge for pour over: the step that completes the Live card is
  // "Rate brew" — on to Post Brew.
  @override
  Future<bool> purge() async {
    if (!brewDone) return false;
    _runningPlan = null;
    applyStage(ShotStage.purging);
    notifyListeners();
    return true;
  }

  @override
  void confirmPostShot() {
    super.confirmPostShot();
    // Only end the finished brew — a new one may already be running when
    // the old one is saved late.
    if (stage == ShotStage.purging) {
      applyStage(ShotStage.idle);
      // Next brew on the Meticulous: the steps again.
      if (_auto) prep.restart();
    }
    _syncPrep();
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
        grindMarker: Value(snap.grindMarker),
        grinder: Value(snap.grinder),
        burrs: Value(snap.burrs),
        brewedWith: Value(snap.brewedWith),
        brewChainId: Value(snap.brewChainId),
        finalWeight: Value(_grams),
        beverageGrams: Value(_beverageG),
        durationMs: Value(readings.isEmpty ? elapsedMs : readings.last.timeMs),
        profileTemp: Value(temperature),
        // Server and brewer weights from the setup steps (Meticulous) —
        // local only, kept for a later beverage-weight calculation.
        rawDebugJson: Value(
          _runningPrep == null
              ? null
              : jsonEncode({'pourOverSetup': _runningPrep}),
        ),
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
    _prepSub?.cancel();
    _armSub?.cancel();
    _dialIdleSub?.cancel();
    _dialTareSub?.cancel();
    _dialPoll?.cancel();
    prep.removeListener(_onPrep);
    scale.removeListener(_onScale);
    setup.removeListener(_onScale);
    recipes.removeListener(_onScale);
    super.dispose();
  }
}
