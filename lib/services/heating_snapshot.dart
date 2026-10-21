// The hero ring's last heating estimate, for the machine notification
// (machine_notifications.dart).
//
// The ETA model lives in TemperatureTile and is calibrated there on real
// captures; it runs while the tile builds. In the background the app draws
// no frames, so the notification counts down from the last estimate
// instead of running a second copy of the model. Back in the app the tile
// takes over again.
class HeatingSnapshot {
  HeatingSnapshot._();

  static final instance = HeatingSnapshot._();

  double? _etaSeconds;
  DateTime? _etaAt;

  /// Ring progress over the whole heating run, 0…1.
  double progress = 0;

  /// Called by the tile whenever it shows a new ETA (null: none).
  void publishEta(double? seconds, DateTime at) {
    _etaSeconds = seconds;
    _etaAt = seconds == null ? null : at;
  }

  /// Seconds left at [now], counted down from the last estimate; null when
  /// there is none.
  double? remainingSeconds(DateTime now) {
    final seconds = _etaSeconds, at = _etaAt;
    if (seconds == null || at == null) return null;
    final left = seconds - now.difference(at).inMilliseconds / 1000;
    return left < 0 ? 0 : left;
  }

  void clear() {
    _etaSeconds = null;
    _etaAt = null;
    progress = 0;
  }
}
