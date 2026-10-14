import '../../services/live_shot_service.dart';
import '../espresso_machine.dart';
import 'gaggimate_service.dart';
import 'gaggimate_status.dart';

// Drives the same three cards (Pre/Live/Post) as for the Meticulous, just
// from the GaggiMate's state. The cards only know the base class and
// therefore stay unchanged.
//
// The machine has no session concept like the Meticulous ("start profile
// -> heat -> click to start -> brew -> purge"), only an operating mode and
// a running process. Mapping:
//
//   mode != Brew                  -> idle      (Pre card: "Start Profile")
//   mode Brew, not yet hot        -> heating   (Pre card: "Heating…")
//   mode Brew, at temperature     -> ready     (Pre card: "Start Shot")
//   process running               -> running   (Live card)
//   process finished, not cleared -> purging   (Post card)
//
// The finished process stays in the machine until someone clears it with
// `req:process:clear` — exactly the hold point the Post card needs. So it
// is only cleared with the save button.
class GaggiMateLiveShotService extends LiveShotService {
  GaggiMateLiveShotService(this._machine);

  final GaggiMateService _machine;

  @override
  String get machineKey => 'gaggimate';

  // The GaggiMate has no "start a profile and heat for it": Brew is its
  // normal operating mode, in which it stays at temperature permanently.
  // The Meticulous rule "locked once no longer idle" would have locked the
  // profile here practically all the time. So it is only locked while a
  // brew is actually running or its result is still on the Post card.
  @override
  bool get profileLocked =>
      stage == ShotStage.running || stage == ShotStage.purging;

  // For the same reason the start button doesn't pulse here: in Brew mode
  // the machine is almost always ready, so constant pulsing signals
  // nothing.
  @override
  bool get pulsesWhenReady => false;

  // And for the same reason there is no "Auto Start" here: it would not
  // wait for a moment but trigger a brew immediately when ticked.
  @override
  bool get supportsAutoStart => false;

  // One boiler sensor that visibly drops during the brew — the curve is
  // the interesting part here.
  @override
  bool get tracksTemperature => true;

  // One sensor instead of four, so only one band; hold time same as for
  // the Meticulous.
  static const _stableBand = 3.0;
  static const _stableHold = Duration(seconds: 10);
  static const _readyMargin = 2.0;

  DateTime? _inBandSince;
  bool _processWasActive = false;

  @override
  double? get targetTemperature => _machine.status.targetTemp;

  @override
  void start() {
    _machine.addListener(_onStatus);
    _onStatus();
  }

  @override
  void dispose() {
    _machine.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    final status = _machine.status;
    final connected =
        _machine.connectionState == MachineConnectionState.connected;

    _updateStability(status, connected);
    _updateReadings(status);
    applyStage(_stageFor(status, connected));
    maybeAutoStart();
    notifyListeners();
  }

  ShotStage _stageFor(GaggiMateStatus status, bool connected) {
    if (!connected) return ShotStage.idle;
    final process = status.process;
    // Flushes, steam and hot-water runs go through the same process block
    // but are not coffee brews — they must not trigger the Pre/Live/Post
    // cycle.
    if (process != null && process.isShot) {
      return process.active ? ShotStage.running : ShotStage.purging;
    }
    if (status.mode != GaggiMateMode.brew) return ShotStage.idle;
    final temp = status.currentTemp;
    final target = status.targetTemp;
    if (temp == null || target == null || target <= 0) return ShotStage.idle;
    return temp >= target - _readyMargin ? ShotStage.ready : ShotStage.heating;
  }

  void _updateStability(GaggiMateStatus status, bool connected) {
    final temp = status.currentTemp;
    final target = status.targetTemp;
    if (!connected ||
        temp == null ||
        target == null ||
        target <= 0 ||
        status.mode != GaggiMateMode.brew) {
      _inBandSince = null;
      stabilized = false;
      return;
    }
    if ((temp - target).abs() <= _stableBand) {
      _inBandSince ??= DateTime.now();
    } else {
      _inBandSince = null;
    }
    stabilized =
        _inBandSince != null &&
        DateTime.now().difference(_inBandSince!) >= _stableHold;
  }

  void _updateReadings(GaggiMateStatus status) {
    final process = status.process;
    final active = process != null && process.active && process.isShot;

    if (active) {
      // New brew: discard the old curve. Detected by the switch from "no
      // running process" to "running".
      if (!_processWasActive) resetReadings();
      _processWasActive = true;
      // "infusion" is the pre-infusion, "brew" the actual brew — only the
      // latter counts for extraction time.
      markExtracting(process.stage == 'brew');
      addReading(
        timeMs: process.elapsed.inMilliseconds,
        pressure: status.pressure ?? 0,
        flow: status.flow ?? 0,
        weight: status.weight ?? 0,
        temperature: status.currentTemp,
        stage: process.label,
      );
      return;
    }

    _processWasActive = false;
    // A steam, water or flush run is like "nothing running" for the curve:
    // it must neither extend the last brew's curve nor delete it early.
    if (process != null && !process.isShot) return;
    if (process == null && hasReadings) {
      // Process cleared -> the last brew's curve is done.
      markExtracting(false);
      resetReadings();
    } else if (process != null && wasExtracting) {
      markExtracting(false);
    }
  }

  @override
  Future<bool> startShot() => _machine.sendCommand(MachineCommand.start);

  @override
  Future<bool> stopShot() => _machine.sendCommand(MachineCommand.stop);

  // The GaggiMate doesn't purge after the brew — the final step is clearing
  // the finished process.
  @override
  Future<bool> purge() async {
    _machine.clearProcess();
    return true;
  }

  // Saving completes the cycle: first release the card, then clear the
  // finished process in the machine.
  @override
  void confirmPostShot() {
    final wasPost = activeCard == ActiveCard.post;
    super.confirmPostShot();
    if (wasPost) _machine.clearProcess();
  }
}
