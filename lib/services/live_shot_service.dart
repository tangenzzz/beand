import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../models/machine_sensors.dart';
import '../models/machine_status.dart';
import '../models/shot_phases.dart';
import 'live_gap_log.dart';
import 'meticulous_socket_service.dart';

// State of the Pre-Shot/Shot/Post-Shot cards, derived purely from
// `status.name` (`MachineStatus.phase`) — never from a local "I clicked"
// flag. That way the cards switch along automatically, even when
// start/purge is triggered on the machine itself or from another app.
// Phase order verified live on real captures: idle -> starting... ->
// heating -> click to start -> retracting -> Water Filling -> closing
// valve -> [profile stages, extracting=true] -> retracting -> click to
// purge -> purge -> finished -> idle.
enum ShotStage { idle, heating, ready, running, awaitingPurge, purging }

// Which of the three cards is currently "up" — highlighted in the accent
// color in the title and also the page the carousel jumps to: PRE until the
// shot starts, LIVE until after the purge, POST until the save button is
// pressed, then PRE again. Unlike [ShotStage] this is not a pure mirror of
// the machine phase: POST stays beyond 'finished'/'idle' until the user
// has saved (or the next profile starts).
enum ActiveCard { pre, live, post }

// Shared part for all machines: card state, live curve, carousel jumps,
// auto start. How the machine state becomes a [ShotStage], on the other
// hand, is machine-specific and lives in the subclasses — the Meticulous
// reads phase names, the GaggiMate its process block (see
// gaggimate_live_shot_service.dart). The three cards themselves only know
// this base and therefore work unchanged on both machines.
abstract class LiveShotService extends ChangeNotifier {
  ShotStage stage = ShotStage.idle;
  ShotStage? _previousStage;
  ActiveCard activeCard = ActiveCard.pre;

  // A finished shot waits in the Post-Shot card for its Save. Stays true
  // when the next shot is started on the machine first (then PRE/LIVE is
  // the active card again), so Save still has something to complete.
  bool postShotPending = false;

  // Key of the machine in the `Shots.machine` column (see ShotMachine).
  // The Post-Shot card thus shows the last shot of THIS machine — so never
  // a Meticulous brew on the GaggiMate Home.
  String get machineKey;

  // The machine's temperature target — the live card shows it in the value row.
  double? get targetTemperature;

  // Has the temperature been right long enough (see the respective
  // subclass)? Enables the "Start Shot" button of the Pre-Shot card.
  bool stabilized = false;

  // May the profile in the Pre-Shot card still be changed?
  //
  // On the Meticulous, "no longer idle" means a specific profile is loaded
  // and the machine heats FOR THIS profile — from then on it is locked in.
  // Machines without this notion override this; see
  // GaggiMateLiveShotService.
  bool get profileLocked => stage != ShotStage.idle;

  // Does the start button pulse once the machine is ready? The pulse means
  // "the machine is waiting for you now" — it is only worth it where that
  // is a moment in the flow and not a permanent state.
  bool get pulsesWhenReady => true;

  // Does this machine deliver a temperature per data point? Then the Shot
  // card also draws the red temperature curve and shows a TEMP column. The
  // Meticulous has its own temperature card with four sensors for that —
  // there the chart stays at yield/flow/pressure.
  bool get tracksTemperature => false;

  // Does the Pre-Shot card show the "Auto Start" checkbox? It only makes
  // sense where "ready" is a moment in the flow: on a machine that is
  // permanently ready in standby mode, checking it would immediately
  // trigger a brew (see GaggiMateLiveShotService).
  bool get supportsAutoStart => true;

  // Starts listening to the machine state.
  void start();

  // ---- Live readings for the Shot card ----
  final List<ShotReading> _readings = [];
  UnmodifiableListView<ShotReading> get liveReadings =>
      UnmodifiableListView(_readings);
  List<ShotPhase> get livePhases => computePhases(_readings);
  DateTime? _extractionStartedAt;
  DateTime? _extractionEndedAt;
  int _nextReadingId = 0;
  bool _wasExtracting = false;

  // Purely informational for the time card: duration of the actual
  // extraction (between first and last extracting=true), keeps running
  // until it ends, frozen afterwards.
  int get elapsedExtractionMs {
    final start = _extractionStartedAt;
    if (start == null) return 0;
    final end = _extractionEndedAt ?? DateTime.now();
    return end.difference(start).inMilliseconds;
  }

  /// When the extraction started (null before) — for a clock that counts
  /// up by itself, e.g. in the status notification.
  DateTime? get extractionStartedAt => _extractionStartedAt;

  @protected
  void markExtracting(bool extracting) {
    if (extracting && !_wasExtracting) _extractionStartedAt = DateTime.now();
    if (!extracting && _wasExtracting) _extractionEndedAt = DateTime.now();
    _wasExtracting = extracting;
  }

  @protected
  bool get wasExtracting => _wasExtracting;

  @protected
  void addReading({
    required int timeMs,
    required double pressure,
    required double flow,
    required double weight,
    required String stage,
    double? temperature,
  }) {
    _readings.add(
      ShotReading(
        id: _nextReadingId++,
        shotId: 0,
        timeMs: timeMs,
        pressure: pressure,
        flow: flow,
        weight: weight,
        // Boiler temperature in the same column where the GaggiMate import
        // stores it (gaggimate_shot_sync_service): on the Meticulous barUp
        // is the upper boiler sensor, on the GaggiMate the only one. So the
        // chart reads the same field live and in the History.
        barUp: temperature,
        stage: stage,
      ),
    );
  }

  @protected
  bool get hasReadings => _readings.isNotEmpty;

  @protected
  void resetReadings() {
    _readings.clear();
    _extractionStartedAt = null;
    _extractionEndedAt = null;
    _wasExtracting = false;
    _nextReadingId = 0;
  }

  final StreamController<int> _pageJumps = StreamController<int>.broadcast();
  // Card index the carousel should jump to (0 = Pre Shot, 1 = Shot,
  // 2 = Post Shot) — exactly once per real transition, not on every status
  // tick.
  Stream<int> get pageJumps => _pageJumps.stream;

  // "Auto Start": checkbox in the Pre-Shot card. Triggers the brew exactly
  // once per preheat, as soon as the machine is ready AND the temperature
  // is stabilized (the outer ring).
  //
  // The checkbox stays set until the user clears it (it is a setting, not
  // a one-shot trigger); `_autoStartFired` makes sure only one start goes
  // out per cycle anyway.
  bool autoStartEnabled = false;
  bool _autoStartFired = false;

  void setAutoStart(bool enabled) {
    if (enabled == autoStartEnabled) return;
    autoStartEnabled = enabled;
    if (!enabled) _autoStartFired = false;
    notifyListeners();
  }

  @protected
  void maybeAutoStart() {
    if (!supportsAutoStart) return;
    if (!autoStartEnabled || _autoStartFired) return;
    if (!stabilized || stage != ShotStage.ready) return;
    _autoStartFired = true;
    unawaited(startShot());
  }

  // The Post-Shot card's save button: completes the cycle and releases PRE
  // again.
  //
  // If the next shot was already started on the machine, the cycle has
  // moved on by itself: then Save only completes the old shot and jumps back
  // to the card of the running one instead of doing nothing.
  void confirmPostShot() {
    final pending = postShotPending;
    postShotPending = false;
    if (activeCard == ActiveCard.post) {
      activeCard = ActiveCard.pre;
      _pageJumps.add(0);
    } else if (pending) {
      _pageJumps.add(activeCard == ActiveCard.live ? 1 : 0);
    } else {
      return;
    }
    notifyListeners();
  }

  // Adopt the new card state and derive the carousel jump and active card
  // from it.
  @protected
  void applyStage(ShotStage next) {
    if (next == stage) return;
    _previousStage = stage;
    stage = next;

    if (stage == ShotStage.running && _previousStage != ShotStage.running) {
      _pageJumps.add(1);
    } else if (stage == ShotStage.purging &&
        (_previousStage == ShotStage.awaitingPurge ||
            _previousStage == ShotStage.running)) {
      _pageJumps.add(2);
    }
    _updateActiveCard();
  }

  // PRE -> LIVE at shot start, LIVE -> POST at purge, POST -> PRE only via
  // confirmPostShot() (save button) or when the next profile is started
  // without saving. An abort before the purge falls back to PRE, because
  // then there is no shot to rate.
  void _updateActiveCard() {
    switch (stage) {
      case ShotStage.heating:
      case ShotStage.ready:
        activeCard = ActiveCard.pre;
        _autoStartFired = false;
      case ShotStage.running:
      case ShotStage.awaitingPurge:
        activeCard = ActiveCard.live;
      case ShotStage.purging:
        activeCard = ActiveCard.post;
        postShotPending = true;
      case ShotStage.idle:
        if (activeCard == ActiveCard.live) activeCard = ActiveCard.pre;
        _autoStartFired = false;
    }
  }

  // ---- Machine actions ----
  Future<bool> startShot();
  Future<bool> stopShot();
  // On the Meticulous the purge run, on the GaggiMate clearing the finished
  // process — both the step that completes the live card.
  Future<bool> purge();

  @override
  void dispose() {
    unawaited(_pageJumps.close());
    super.dispose();
  }
}

class MeticulousLiveShotService extends LiveShotService {
  MeticulousLiveShotService(this._socket);

  final MeticulousSocketService _socket;

  @override
  String get machineKey => 'meticulous';

  // ---- "Stabilized" detection for the Pre-Shot Start Shot button ----
  // Independent of TemperatureTile._TemperatureTileState (same definition:
  // tolerance band ±3°C / ±4°C brew head, 10s hold), but with the simpler
  // latch trigger `phase == "click to start"` instead of additionally via
  // the EMA heating temperature — that deliberately lives only locally in
  // TemperatureTile (display detail for the ring timing) and is not
  // duplicated here, so as not to touch the logic calibrated live there.
  static const _stableBand = 3.0;
  static const _stableBandGroupHead = 4.0;
  static const _stableHold = Duration(seconds: 10);
  static const _emaAlpha = 0.3;

  bool _readyLatched = false;
  double? _emaExcess;
  DateTime? _inBandSince;
  MachineSensors? _lastStabilitySensors;

  MachineStatus? _lastStatus;
  DateTime? _lastStatusAt;

  // Heartbeat during the brew: if it comes clearly too late, the app itself
  // hung, not the network (see LiveGapLog).
  static const _beatInterval = Duration(milliseconds: 250);
  static const _gapThreshold = Duration(seconds: 1);
  Timer? _heartbeat;
  DateTime? _lastBeat;
  MachineConnectionState? _lastConnection;

  @override
  double? get targetTemperature => _socket.targetTemperature;

  @override
  void start() {
    _socket.addListener(_onSocket);
    _onSocket();
  }

  @override
  void dispose() {
    _socket.removeListener(_onSocket);
    _stopHeartbeat();
    super.dispose();
  }

  void _onSocket() {
    final status = _socket.latestStatus;
    final phase = status?.phase ?? 'idle';
    final sensors = _socket.latestSensors;
    final target = _socket.targetTemperature;

    _updateStability(phase, sensors, target);
    // The listener also fires for sensor and other events. But a data point
    // belongs to a NEW status message, otherwise the same message would
    // appear several times in the curve.
    final freshStatus = !identical(status, _lastStatus);
    _lastStatus = status;
    if (freshStatus) _updateReadings(status, phase);
    _updateStage(phase);
    _watchForGaps(freshStatus ? status : null);

    // Deliberately later than the machine's own setting `auto_start_shot`,
    // which starts brewing on a mere "ready" — what counts here is the
    // stabilized state (see maybeAutoStart in the base).
    maybeAutoStart();

    notifyListeners();
  }

  void _updateStability(String phase, MachineSensors? sensors, double? target) {
    final isProfileSessionActive =
        _socket.confirmedSessionState == 'brewing' && phase != 'boot';
    final isPreShot =
        phase == 'starting...' ||
        phase == 'heating' ||
        phase == 'click to start';
    final active =
        isProfileSessionActive &&
        isPreShot &&
        sensors != null &&
        target != null;

    if (!active) {
      _readyLatched = false;
      _emaExcess = null;
      _inBandSince = null;
      stabilized = false;
      return;
    }

    final excess = _worstBandExcess(sensors, target);
    if (!_readyLatched && phase == 'click to start') {
      _readyLatched = true;
      _emaExcess = excess;
    }
    if (!_readyLatched) return;

    if (!identical(sensors, _lastStabilitySensors)) {
      _emaExcess = _emaAlpha * excess + (1 - _emaAlpha) * _emaExcess!;
      _lastStabilitySensors = sensors;
    }
    if (excess <= 0) {
      _inBandSince ??= DateTime.now();
    } else {
      _inBandSince = null;
    }
    stabilized =
        _inBandSince != null &&
        DateTime.now().difference(_inBandSince!) >= _stableHold;
  }

  static double _worstBandExcess(MachineSensors s, double target) {
    final excesses = [
      (s.barUp - target).abs() - _stableBand,
      (s.barMidUp - target).abs() - _stableBand,
      (s.barMidDown - target).abs() - _stableBand,
      (s.barDown - target).abs() - _stableBandGroupHead,
    ];
    return math.max(0.0, excesses.reduce(math.max));
  }

  static const _preRunPhases = {
    'idle',
    'starting...',
    'heating',
    'click to start',
    'boot',
  };
  static const _postRunPhases = {'click to purge', 'purge', 'finished'};
  // Purge and raise from idle are maintenance moves, not a brew: the
  // machine reports them in the same `phase` as shot stages ('purge' and
  // 'home'), but they belong to no shot cycle. 'home' has no phase name of
  // its own in the shot sequence and is therefore always such a move; for
  // 'purge' the stage it comes from decides (see _updateStage). Raise used
  // to fall into the catch-all case and looked like a running brew — the
  // carousel jumped to the live card.
  static const _maintenancePhases = {'home'};
  static const _resetPhases = {'idle', 'starting...', 'heating'};

  // The live curve runs on the machine's own clock (`status.time`): it
  // counts from the start of the extraction, exactly like the timer on the
  // machine and the time series in its history. The lead-in before that
  // (retracting -> water filling -> closing valve) reports time 0 and is
  // left out — it used to be drawn from the tare point on, which put the
  // live time 3–6 s ahead of the machine depending on the profile, and
  // its first point carried a bogus negative flow.
  //
  // Late messages (Wi-Fi delivering a batch at once) need no special care
  // this way: each point carries its time from the machine, not its
  // arrival time.
  //
  // Has really been extracting at least once — distinguishes the final
  // "retracting" stage (piston moves back after the brew, do NOT record
  // here any more) from the short "retracting" right after "click to
  // start" (which reports time 0 and is skipped anyway).
  bool _hasExtracted = false;

  void _updateReadings(MachineStatus? status, String phase) {
    final running =
        !_preRunPhases.contains(phase) &&
        !_postRunPhases.contains(phase) &&
        !_maintenancePhases.contains(phase);
    if (running) {
      final extracting = status?.extracting ?? false;
      markExtracting(extracting);
      if (extracting) _hasExtracted = true;

      final finalRetraction = phase == retractionStage && _hasExtracted;
      if (status != null && status.timeMs > 0 && !finalRetraction) {
        final readings = liveReadings;
        final last = readings.isEmpty ? 0 : readings.last.timeMs;
        addReading(
          // Never backwards, should a message overtake another.
          timeMs: math.max(status.timeMs, last),
          pressure: status.pressure,
          flow: status.flow,
          weight: status.weight,
          stage: phase,
        );
      }
    } else if (_resetPhases.contains(phase)) {
      // New session (or back to idle): discard the old curve. During
      // 'click to purge'/'purge'/'finished', on the other hand, the last
      // recorded curve stays unchanged — the Shot card keeps showing the
      // finished chart until the next profile start.
      if (hasReadings || _hasExtracted || wasExtracting) {
        resetReadings();
        _hasExtracted = false;
      }
    }
  }

  void _watchForGaps(MachineStatus? fresh) {
    final running = stage == ShotStage.running;
    final now = DateTime.now();

    final connection = _socket.connectionState;
    if (running && _lastConnection != null && connection != _lastConnection) {
      LiveGapLog.write(
        'connection',
        '${_lastConnection!.name} -> ${connection.name}',
      );
    }
    _lastConnection = connection;

    if (fresh != null) {
      final previous = _lastStatusAt;
      if (running &&
          previous != null &&
          now.difference(previous) > _gapThreshold) {
        LiveGapLog.write(
          'status',
          'arrival gap ${now.difference(previous).inMilliseconds} ms, '
              'phase "${fresh.phase}", machine time ${fresh.timeMs} ms',
        );
      }
      _lastStatusAt = now;
    }

    if (running) {
      _heartbeat ??= Timer.periodic(_beatInterval, (_) => _beat());
    } else {
      _stopHeartbeat();
      _lastStatusAt = null;
    }
  }

  void _beat() {
    final now = DateTime.now();
    final last = _lastBeat;
    if (last != null && now.difference(last) > _beatInterval + _gapThreshold) {
      LiveGapLog.write(
        'stall',
        'app was blocked ~${now.difference(last).inMilliseconds} ms',
      );
    }
    _lastBeat = now;
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _lastBeat = null;
  }

  // Is the machine currently in a brew? Decides whether a 'purge' is the
  // end of a shot or a maintenance move from idle.
  bool get _inShotCycle =>
      stage == ShotStage.running ||
      stage == ShotStage.awaitingPurge ||
      stage == ShotStage.purging;

  void _updateStage(String phase) {
    final next = switch (phase) {
      'idle' => ShotStage.idle,
      'starting...' || 'heating' => ShotStage.heating,
      'click to start' => ShotStage.ready,
      'click to purge' => ShotStage.awaitingPurge,
      // Only the purge that belongs to a brew completes the live card. A
      // manually triggered one comes from idle and leaves the card state
      // where it is.
      'purge' || 'finished' => _inShotCycle ? ShotStage.purging : stage,
      // Raise (piston up) is a maintenance move like 'boot' — keep the stage.
      'home' => stage,
      // Short reset intermediate state after action/reset — not a real shot
      // state, keep the current stage instead of reacting to it.
      'boot' => stage,
      _ => ShotStage.running,
    };
    applyStage(next);
  }

  // ---- Machine actions ----

  // `continue`, not `start` — see MeticulousSocketService.triggerAction: at
  // the "click to start" gate the machine is in the middle of a sequence
  // and is only waved on (verified live).
  @override
  Future<bool> startShot() => _socket.triggerAction('continue');

  @override
  Future<bool> stopShot() => _socket.triggerAction('stop');

  @override
  Future<bool> purge() => _socket.triggerAction('purge');
}
