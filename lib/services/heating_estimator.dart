import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../models/machine_sensors.dart';
import 'meticulous_socket_service.dart';

// The Meticulous hero's heating model: hero value, ring fill, ETA and the
// "stabilized" outer ring. Moved out of TemperatureTile on 2026-10-21 so it
// keeps running while the app is in the background (the status notification
// shows its ETA, see machine_notifications.dart) — in the tile it only ran
// while frames were drawn. The calculation itself moved over unchanged;
// test/heating_reference_test.dart replays a heating run against values
// recorded before the move.
//
// Hero value = mean of the 4 "bar" sensors, EMA-smoothed.
// Physical mapping see machine_sensors.dart: barUp = brew chamber top,
// barMidUp = middle, barMidDown = bottom, barDown = group head.
//
// _emaAlpha=0.3 checked against real captures: the raw signal of the bar
// sensors only jitters ~0.04°C between samples (~9Hz) — the EMA smooths it
// barely visibly differently than stronger alphas, so 0.3 stays (reacts
// faster to real changes without a measurable difference in
// "nervousness").
//
// The ETA runs in two phases, see _estimateEta: up to 3/4 of the way a fixed
// S-curve prior (_estimateEtaPrior), then an exponential fit to the running
// curve (_estimateEtaExponential). Both calibrated on real captures. The
// reference point is "machine ready" (target − readyMargin, i.e.
// `click to start`), NOT the stabilized value — according to captures that
// comes another 29…117s later (outer ring, see _stableBand).
class HeatingEstimator extends ChangeNotifier {
  HeatingEstimator(this.socket);

  final MeticulousSocketService socket;

  void start() {
    socket.addListener(_onSocket);
    _onSocket();
  }

  @override
  void dispose() {
    socket.removeListener(_onSocket);
    super.dispose();
  }

  void _onSocket() {
    update();
    notifyListeners();
  }

  // ---- Results of the last update ----

  /// EMA-smoothed mean of the four bars; null without sensors.
  double? heroValue;

  /// The target the session heats to (profile target, or the assumed one
  /// for a plain preheat); null without one.
  double? sessionTarget;

  /// A profile session or a plain preheat is running.
  bool isHeatingSession = false;
  bool atTarget = false;

  /// Heating in the narrow sense (the ring's heating colour).
  bool isHeatingState = false;

  /// Inner ring, 0…1, over the whole heating run.
  double ringProgress = 0;

  /// Outer ring ("stabilized"): shown from Ready on, fill and done.
  bool stabilityShown = false;
  double stabilityProgress = 0;
  bool stabilized = false;

  /// ETA as shown ("~3:38"; throttled, see _displayUpdateInterval).
  String? eta;

  /// The seconds behind [eta] and when it was computed — the notification
  /// counts down from there between two estimates.
  double? etaSeconds;
  DateTime? etaAt;

  /// When the machine should be ready by the current estimate.
  DateTime? get readyAt {
    final seconds = etaSeconds, at = etaAt;
    if (seconds == null || at == null) return null;
    return at.add(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Seconds left at [now] by the current estimate.
  double? remainingSeconds(DateTime now) {
    final seconds = etaSeconds, at = etaAt;
    if (seconds == null || at == null) return null;
    final left = seconds - now.difference(at).inMilliseconds / 1000;
    return left < 0 ? 0 : left;
  }

  // ---- Model state ----

  static const double _emaAlpha = 0.3;

  double? _emaHero;
  MachineSensors? _lastProcessedSensors;

  // "Stabilized" (outer ring): from "Ready" (target−2°C, i.e. the machine's
  // `click to start`) until the shot starts. `_readyExcess` = worst excess
  // over the tolerance band at the Ready moment (denominator of the ring
  // fill), `_emaExcess` the smoothed current value, `_inBandSince` start of
  // the uninterrupted phase in which all four bars are within the band.
  bool _readyLatched = false;
  double? _readyExcess;
  double? _emaExcess;
  DateTime? _inBandSince;
  MachineSensors? _lastStabilitySensors;

  // Anchor for the ETA estimate: value + time at session start ("state"
  // becomes "brewing"). Average rate since this anchor instead of a sliding
  // window over the last N sensor samples — so there is an ETA right from
  // the first sample after profile start, instead of only after a few
  // seconds of window build-up. Uses real wall-clock time (DateTime), no
  // assumed sample rate.
  double? _sessionStartHero;
  DateTime? _sessionStartAt;

  // Start value ONLY for the ring, if the app joined in the middle of
  // preheating (profile started on the machine, app opened later). Then
  // the real start is unknown: the session anchor above would be the
  // temperature at opening — the ring would sit at 0 and fill in fast
  // motion. Instead the last known resting temperature or
  // [_nominalColdStart]. null = start seen ourselves, session anchor applies.
  double? _ringAnchor;

  // Last seen without a running session (machine's resting temperature).
  double? _lastIdleHero;
  DateTime? _lastIdleSeenAt;

  // How fresh the resting observation must be for the start to count as
  // seen ourselves (sensors arrive ~9x/s; after background/restart they are
  // missing). Assumption without any observation: room temperature.
  static const _joinedLateAfter = Duration(seconds: 30);
  static const _nominalColdStart = 25.0;

  // History (seconds since session anchor, hero value) for the exponential
  // ETA fit, see _estimateEta. Throttled to 1 sample/s (independent of the
  // ~9Hz sensor rate) — enough for the curve shape, and it keeps the list
  // small in long sessions.
  static const _sessionSampleInterval = Duration(seconds: 1);
  final List<(double elapsedSeconds, double heroValue)> _sessionSamples = [];
  DateTime? _lastSessionSampleAt;

  // Displayed (throttled) ETA (the ring is no longer throttled, it glides in
  // TemperatureRing): the raw rate/ratio calculation reacts sensitively to
  // small fluctuations shortly after session start, and we re-render on
  // every sensor sample (~10x/s) — that looked "nervous". So only update
  // every 10s; the very first available value appears immediately, though,
  // and at session end it resets immediately (not throttled).
  static const _displayUpdateInterval = Duration(seconds: 10);
  DateTime? _lastDisplayUpdateAt;

  // Mean of the 4 bar sensors — matches the machine's `status.sensors.t`
  // (deviation ~0.1°C in captures), which it also bases its
  // "click to start" on (hero = same value as Ready to brew).
  static double _barMean(MachineSensors s) =>
      (s.barUp + s.barMidUp + s.barMidDown + s.barDown) / 4;

  // The machine switches to "click to start" as soon as this mean reaches
  // target −2°C (+~5s hold time, identical in all captures). "Target
  // reached" (ring full, ETA 0) therefore depends on target − readyMargin
  // instead of the full target.
  static const readyMargin = 2.0;

  // "Stabilized": UP/MID/DOWN within target ±3°C, group head (`barDown`)
  // within ±4°C, 10s uninterrupted (replay of 6 captures: 29–106s after
  // Ready, always before shot start). `barDown` gets a wider band because
  // it lags behind as the coldest sensor in all runs — but the machine
  // weights it fully in its own mean, so it stays equally weighted in the
  // hero.
  static const _stableBand = 3.0;
  static const _stableBandGroupHead = 4.0;
  static const _stableHold = Duration(seconds: 10);
  // Lower bound for the outer ring fill's denominator, so a tiny excess at
  // the Ready moment doesn't make the ring jump with every bit of noise.
  static const _minReadyExcess = 1.0;

  // Largest excess of a bar over its tolerance band (0 = all within band).
  static double _worstBandExcess(MachineSensors s, double target) {
    final excesses = [
      (s.barUp - target).abs() - _stableBand,
      (s.barMidUp - target).abs() - _stableBand,
      (s.barMidDown - target).abs() - _stableBand,
      (s.barDown - target).abs() - _stableBandGroupHead,
    ];
    return math.max(0.0, excesses.reduce(math.max));
  }

  // The seconds behind the last ETA text (see [etaSeconds]).
  double? _etaSecondsRaw;

  String _etaText(double seconds) {
    _etaSecondsRaw = seconds;
    return formatEtaSeconds(seconds);
  }

  static String formatEtaSeconds(double seconds) {
    final total = seconds.round().clamp(0, 999999);
    if (total >= 60) {
      final minutes = total ~/ 60;
      final secs = total % 60;
      return '~$minutes:${secs.toString().padLeft(2, '0')}';
    }
    return '~${total}s';
  }

  // From here on we trust the exponential fit instead of the linear rate —
  // calibrated on real curves (a clean heating run and a cold start up to
  // the shot, noisier). Both needed about 3/4 of the way to the target
  // before the fit was reliably closer to the real arrival time than the
  // simple linear rate — before that too little curvature is visible and
  // the fit overreacts.
  static const _minEtaFraction = 0.75;
  static const _minEtaElapsedSeconds = 60;
  // Time constants observed from the same two curves were ~90s and ~140s;
  // anything far outside is discarded as noise instead of showing an absurd
  // ETA.
  static const _minTauSeconds = 15;
  static const _maxTauSeconds = 600;
  static const _atTargetThreshold = 0.5;
  // Exp ETA may be at most linear ETA × this factor.
  static const _expEtaCapFactor = 4.0;
  // S-curve prior, calibrated on 10 heating runs.
  //
  // The heating curve is NOT an exponential curve with one time constant —
  // that was the earlier assumption (_priorTauSeconds = 45.0, mean error
  // 36.7s in this phase). Pooled measurement of the local heating rate over
  // all runs shows two independent effects:
  //   * Ramp-up inertia: the rate climbs to full rate over ~90s
  //     (0.084 → 0.175 → 0.358 → 0.462 → 0.508 C/s in 20s steps).
  //   * Final approach: below ~15C remaining distance it flattens again
  //     (0.429 → 0.238 → 0.054 C/s at 10-15 / 5-10 / 0-5C remaining).
  // Both applied multiplicatively to the full rate and integrated forward
  // give a mean error of 24.6s (max 64.5s) instead of 36.7s (max 97.5s).
  //
  // Also explains the three populations in the captures without extra
  // assumptions: cold starts go through the whole S-curve, warm starts
  // after a shot pay the ramp-up but skip plateau distance, runs after
  // preheat already start in the final approach and are slow in absolute
  // terms.
  //
  // Known remaining weakness: warm starts after a shot (anchor ~40-45C) are
  // really ~55s faster than this model, nearly constant across the whole
  // prior phase. The ramp-up inertia itself varies 20…71s per run and
  // correlates with nothing known at profile start (in particular not the
  // anchor temperature — the two warmest anchors have the longest inertia).
  // The next step would be a capture with several identical warm starts, to
  // clarify whether the inertia is reproducible.
  // Machine hold time: after the hero reaches target − readyMargin, it
  // takes a constant ~4.8s until the machine itself switches to
  // `click to start` (all 10 captures: 4.3…5.3s, very tight spread).
  // Without this offset the countdown hit 0 while you were still waiting
  // (measured with a stopwatch up to `click to start`). Applies to both
  // phases; the preheat countdown is unaffected, it comes directly from the
  // machine.
  static const _machineHoldSeconds = 4.8;

  static const _vMaxDegreesPerSecond = 0.52;
  static const _priorIntegrationStep = 1.0;

  // Fraction of full rate after `elapsedSeconds` of heating (ramp-up).
  static double _startupRateFraction(double elapsedSeconds) {
    if (elapsedSeconds < 20) return 0.16;
    if (elapsedSeconds < 40) return 0.34;
    if (elapsedSeconds < 60) return 0.69;
    if (elapsedSeconds < 80) return 0.89;
    if (elapsedSeconds < 100) return 0.98;
    return 1.0;
  }

  // Fraction of full rate at `remaining` degrees to go (final approach).
  static double _approachRateFraction(double remaining) {
    if (remaining < 5) return 0.10;
    if (remaining < 10) return 0.46;
    if (remaining < 15) return 0.83;
    return 1.0;
  }

  // Forward integration of the S-curve: simulates heating in 1s steps until
  // the remaining distance drops below _atTargetThreshold. Runs at most
  // 3600 steps and only once per second (throttled display, see
  // [eta]), so it's uncritical.
  static double _estimateEtaPrior(double elapsedSeconds, double diff) {
    var elapsed = elapsedSeconds;
    var remaining = diff;
    var eta = 0.0;
    while (remaining > _atTargetThreshold && eta < 3600) {
      final rate = math.max(
        _vMaxDegreesPerSecond *
            _startupRateFraction(elapsed) *
            _approachRateFraction(remaining),
        0.005,
      );
      remaining -= rate * _priorIntegrationStep;
      elapsed += _priorIntegrationStep;
      eta += _priorIntegrationStep;
    }
    return eta;
  }

  // Plain preheat (without profile) provides no real target temperature
  // field via the API (only the seconds countdown) — so for the ring/red
  // line during preheat a fixed assumed value (~70°C, not API-verified) is
  // used deliberately. The numeric ETA text is unaffected and still uses
  // only the real heater_status countdown.
  static const _assumedPreheatTarget = 70.0;

  String? _estimateEta(double target, double currentHero) {
    _etaSecondsRaw = null;
    if (currentHero >= target) {
      _etaSecondsRaw = 0;
      return 'at target';
    }
    final startHero = _sessionStartHero;
    final startAt = _sessionStartAt;
    if (startHero == null || startAt == null || target <= startHero) {
      return null;
    }

    final elapsedSeconds =
        clock.now().difference(startAt).inMilliseconds / 1000;
    if (elapsedSeconds <= 0) return null;

    final rate = (currentHero - startHero) / elapsedSeconds;
    final linearEtaSeconds = rate > 0.01 ? (target - currentHero) / rate : null;

    final fraction = (currentHero - startHero) / (target - startHero);
    if (elapsedSeconds >= _minEtaElapsedSeconds &&
        fraction >= _minEtaFraction) {
      final expEtaSeconds = _estimateEtaExponential(target, currentHero);
      if (expEtaSeconds != null) {
        // Cap against overestimation right after switching from linear to
        // exponential (replay of captures: first exp value was +63…+255s
        // off). k=4 chosen: mean error in the window from the switch point
        // 55s → 24s, largest error 255s → 50s; k=3…5 are similarly good,
        // k≥6 gets worse again.
        final capped = linearEtaSeconds == null
            ? expEtaSeconds
            : math.min(expEtaSeconds, linearEtaSeconds * _expEtaCapFactor);
        return _etaText(capped + _machineHoldSeconds);
      }
    }

    // Before switching (start of the session, where the exponential fit has
    // not yet seen reliable curvature): S-curve prior from remaining
    // distance AND elapsed heating time — so an ETA appears right from the
    // first sample.
    //
    // The measured rate must deliberately not feed in here: during ramp-up
    // inertia it is near zero and the ETA then explodes (the earlier linear
    // rate gave up to 5312s for a real 296s). Also tested as a hybrid (fixed
    // prior until the measured rate exceeds a threshold, observed after
    // that): worse than the fixed prior alone at every threshold
    // 0.25…0.40 C/s.
    final diff = target - currentHero;
    if (diff <= _atTargetThreshold) {
      return _etaText(_machineHoldSeconds);
    }
    return _etaText(
      _estimateEtaPrior(elapsedSeconds, diff) + _machineHoldSeconds,
    );
  }

  // Fit of ln(target - hero) against time since session anchor (least
  // squares) — the slope gives the time constant tau of a model
  // hero(t) = target - (target - anchor) * exp(-t/tau). Real heating curves
  // flatten towards the target (see class comment), so a purely linear rate
  // systematically underestimates the arrival time, especially at the
  // start of the session.
  double? _estimateEtaExponential(double target, double currentHero) {
    if (_sessionSamples.length < 20) return null;

    var n = 0;
    var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0;
    for (final (elapsed, hero) in _sessionSamples) {
      final diff = target - hero;
      if (diff <= 0.05) continue;
      final y = math.log(diff);
      sumX += elapsed;
      sumY += y;
      sumXX += elapsed * elapsed;
      sumXY += elapsed * y;
      n++;
    }
    if (n < 20) return null;

    final denominator = n * sumXX - sumX * sumX;
    if (denominator.abs() < 1e-6) return null;
    final slope = (n * sumXY - sumX * sumY) / denominator;
    if (slope >= -1e-6) return null; // no decay detectable

    final tau = -1 / slope;
    if (tau < _minTauSeconds || tau > _maxTauSeconds) return null;

    final diffNow = target - currentHero;
    if (diffNow <= _atTargetThreshold) return 0;
    final remaining = tau * math.log(diffNow / _atTargetThreshold);
    if (remaining.isNaN ||
        remaining.isInfinite ||
        remaining < 0 ||
        remaining > 3600) {
      return null;
    }
    return remaining;
  }

  /// One step of the model with the socket's current data (on every socket
  /// update; formerly in TemperatureTile.build).
  @visibleForTesting
  void update() {
    final service = socket;
    final sensors = service.latestSensors;
    final target = service.targetTemperature;
    final phase = service.latestStatus?.phase ?? 'idle';
    // `state` is the overall session status ("idle"/"brewing") and jumps
    // back to "idle" immediately on cancel — unlike the rate estimate below,
    // which can lag for minutes due to residual heat/noise. So the profile
    // ETA is additionally coupled to it, so it disappears immediately on
    // cancel instead of running out.
    // From a live capture: `action/reset` (cancel preheat) takes ~5s until
    // the machine reacts, then passes through `state=brewing, name=boot` for
    // ~2s (internal reset sequence of the brew unit) before returning to
    // idle — not an outlier, but a real yet misleading signal. Explicitly
    // exclude `name=="boot"`, otherwise the app takes it for a real profile
    // session.
    final isProfileSessionActive =
        service.confirmedSessionState == 'brewing' && phase != 'boot';
    // Preheat also counts as an "active heating session" for anchor/ring
    // purposes (see _assumedPreheatTarget above) — only the numeric ETA
    // estimate below stays strictly limited to isProfileSessionActive, so
    // profile and preheat targets are never mixed.
    final isHeatingSession = isProfileSessionActive || service.isPreheatActive;
    final sessionTarget = isProfileSessionActive
        ? target
        : (service.isPreheatActive ? _assumedPreheatTarget : target);

    if (sensors != null && !identical(sensors, _lastProcessedSensors)) {
      final raw = _barMean(sensors);
      _emaHero = _emaHero == null
          ? raw
          : _emaAlpha * raw + (1 - _emaAlpha) * _emaHero!;
      _lastProcessedSensors = sensors;
    }
    final heroValue = sensors == null ? null : _emaHero;

    if (isHeatingSession && heroValue != null) {
      // Move the anchor to the LOWEST point since session start, not the
      // very first value: profile start first pumps cold water through the
      // circuit (temperature drops briefly) before it really starts to
      // rise. An anchor on the still-warm start value would have made the
      // rate negative first and then permanently silent until the
      // temperature climbs back above the start value (the ETA flashed
      // briefly, then disappeared for good). Once the temperature really
      // rises, the anchor stays at the low point by itself.
      final now = clock.now();
      if (_sessionStartHero == null) {
        final lastIdle = _lastIdleSeenAt;
        final joinedLate =
            lastIdle == null || now.difference(lastIdle) > _joinedLateAfter;
        _ringAnchor = joinedLate
            ? math.min(heroValue, _lastIdleHero ?? _nominalColdStart)
            : null;
      } else if (_ringAnchor != null && heroValue < _ringAnchor!) {
        _ringAnchor = heroValue;
      }
      if (_sessionStartHero == null || heroValue < _sessionStartHero!) {
        _sessionStartHero = heroValue;
        _sessionStartAt = now;
        // Anchor moved: previous samples ran against the old anchor, their
        // elapsedSeconds would now be wrong — discard and collect anew,
        // otherwise it skews the exponential fit.
        _sessionSamples.clear();
        _lastSessionSampleAt = null;
      } else if (_lastSessionSampleAt == null ||
          now.difference(_lastSessionSampleAt!) >= _sessionSampleInterval) {
        final elapsed = now.difference(_sessionStartAt!).inMilliseconds / 1000;
        _sessionSamples.add((elapsed, heroValue));
        _lastSessionSampleAt = now;
      }
    } else if (!isHeatingSession && _sessionStartHero != null) {
      _sessionStartHero = null;
      _sessionStartAt = null;
      _sessionSamples.clear();
      _lastSessionSampleAt = null;
      _ringAnchor = null;
    }
    if (!isHeatingSession && heroValue != null) {
      _lastIdleHero = heroValue;
      _lastIdleSeenAt = clock.now();
    }

    // Ring/ETA run up to target − readyMargin (= the machine's Ready to
    // brew); the target line in ring/chart stays at the full target.
    final readyTarget = sessionTarget == null
        ? null
        : sessionTarget - readyMargin;
    final atTarget =
        sensors != null &&
        readyTarget != null &&
        heroValue != null &&
        heroValue >= readyTarget;

    // Outer ring "Stabilized": only in a real profile session (the preheat
    // target ~70°C is not API-verified) and only until shot start — after
    // that the temperatures drop due to the incoming water.
    final isPreShot =
        phase == 'starting...' ||
        phase == 'heating' ||
        phase == 'click to start';
    final stabilityActive =
        isProfileSessionActive &&
        isPreShot &&
        sensors != null &&
        target != null;
    double stabilityProgress = 0;
    var stabilized = false;
    if (!stabilityActive) {
      _readyLatched = false;
      _readyExcess = null;
      _emaExcess = null;
      _inBandSince = null;
    } else {
      final excess = _worstBandExcess(sensors, target);
      // Latch "Ready" (even if the hero briefly dips below target−2°C
      // afterwards); the machine itself latches `click to start` the same way.
      if (!_readyLatched && (atTarget || phase == 'click to start')) {
        _readyLatched = true;
        _readyExcess = excess;
        _emaExcess = excess;
      }
      if (_readyLatched) {
        if (!identical(sensors, _lastStabilitySensors)) {
          _emaExcess = _emaAlpha * excess + (1 - _emaAlpha) * _emaExcess!;
          _lastStabilitySensors = sensors;
        }
        if (excess <= 0) {
          _inBandSince ??= clock.now();
        } else {
          _inBandSince = null;
        }
        stabilized =
            _inBandSince != null &&
            clock.now().difference(_inBandSince!) >= _stableHold;
        final denominator = math.max(_readyExcess!, _minReadyExcess);
        stabilityProgress = stabilized
            ? 1.0
            : (1 - _emaExcess! / denominator).clamp(0.0, 0.97);
      }
    }
    final stabilityShown = stabilityActive && _readyLatched;

    // isPreheatActive covers the case where `phase` wrongly stays "idle"
    // for a plain preheat action (see MeticulousSocketService).
    final isHeatingState =
        phase == 'heating' || phase == 'preheating' || service.isPreheatActive;

    // Progress over the complete heating process: from the water
    // temperature at profile start (session low-point anchor, see above) to
    // the target — not just the last few degrees before it.
    // Without an active session (idle, or only plain preheat with a
    // different target) the ring stays empty instead of showing misleading
    // progress.
    double ringProgress = 0;
    final sessionStart = _ringAnchor ?? _sessionStartHero;
    if (heroValue != null && readyTarget != null) {
      if (heroValue >= readyTarget) {
        ringProgress = 1.0;
      } else if (isHeatingSession &&
          sessionStart != null &&
          readyTarget > sessionStart) {
        ringProgress =
            ((heroValue - sessionStart) / (readyTarget - sessionStart)).clamp(
              0.0,
              1.0,
            );
      }
    }

    final sessionEnded = !isHeatingSession;
    final now = clock.now();
    // The ring follows every reading (previously only every 10 s with the
    // ETA — it stuck and jumped); it looks calm thanks to the gliding in
    // TemperatureRing, not throttling.
    if (sessionEnded) {
      eta = null;
      etaSeconds = null;
      etaAt = null;
      _lastDisplayUpdateAt = null;
      ringProgress = 0;
    } else if (service.isPreheatActive && !isProfileSessionActive) {
      // A profile started during a preheat heats to its own target: the
      // countdown below would then be the preheat's (~70°, ~10 min), not
      // the profile's — the iOS "Should be ready" came minutes late.
      // Preheat countdown (real machine event, heater_status) is already
      // throttled by itself (~1x/s) — take it over directly here WITHOUT the
      // 10s throttling below, otherwise the display "hangs" in 10s steps
      // instead of really counting down every second.
      // Heats to a different target (~70°C) than the profile target, hence
      // a strict either-or with the exponential fit below, never mix.
      final preheatCountdown = service.preheatCountdownSeconds;
      eta = preheatCountdown != null
          ? formatEtaSeconds(preheatCountdown)
          : null;
      etaSeconds = preheatCountdown;
      etaAt = preheatCountdown == null ? null : now;
      _lastDisplayUpdateAt = now;
    } else if (eta == null ||
        _lastDisplayUpdateAt == null ||
        now.difference(_lastDisplayUpdateAt!) >= _displayUpdateInterval) {
      // Compute rawEta only here (throttled), not on each of the ~9Hz
      // sensor samples — the exponential fit runs over the collected
      // session samples and is therefore more expensive than one division.
      final rawEta =
          (isProfileSessionActive && heroValue != null && target != null)
          ? _estimateEta(target - readyMargin, heroValue)
          : null;
      eta = rawEta;
      etaSeconds = rawEta == null ? null : _etaSecondsRaw;
      etaAt = rawEta == null ? null : now;
      _lastDisplayUpdateAt = now;
    }

    this.heroValue = heroValue;
    this.sessionTarget = sessionTarget;
    this.isHeatingSession = isHeatingSession;
    this.atTarget = atTarget;
    this.isHeatingState = isHeatingState;
    this.ringProgress = ringProgress;
    this.stabilityShown = stabilityShown;
    this.stabilityProgress = stabilityProgress;
    this.stabilized = stabilized;
  }
}
