import 'dart:async';

import 'package:clock/clock.dart';

import '../models/machine_status.dart';
import '../services/meticulous_socket_service.dart';
import 'brew_scale.dart';

/// The scale built into the Meticulous, used for Pour Over.
///
/// The machine sends its weight in every `status` event (`sensors.w`), also
/// while idle: ~9 values per second with 0.01 g resolution (measured
/// 2026-11-03). It is not zeroed while idle (read −136.5 g with an empty
/// tray), so every brew starts with a tare.
///
/// Tare: `action/tare`, then wait for the weight to settle near 0 — exactly
/// what the machine's own Pour Over mode on the dial does (it emits
/// `action: tare` and waits up to 5 s for |w| ≤ 0.6 g). If the machine does
/// not confirm in time, the app tares in software (subtracts the current
/// value), so a brew never hangs on a lost command.
///
/// Taring on the dial (machine's own Pour Over mode, button press) is
/// recognised by its signature, measured 2026-11-03: 0.3–1.3 s after the
/// press the weight jumps in ONE tick from the steady load to exactly 0.00
/// and stays flat at exactly 0.00. Lifting something off looks different
/// (values in between, then negative with ±0.2 g noise).
///
/// No own connection: it rides on the existing [MeticulousSocketService].
class MeticulousScale extends BrewScale {
  MeticulousScale(
    this.socket, {
    this.tareTimeout = const Duration(seconds: 4),
    this.minReadingGap = const Duration(milliseconds: 30),
  }) {
    socket.addListener(_onSocket);
    _onSocket();
  }

  final MeticulousSocketService socket;
  final Duration tareTimeout;

  /// Weight within which a tare counts as confirmed (like the dial).
  static const zeroTolerance = 0.6;

  static const name = 'Meticulous';

  @override
  bool get isMachineScale => true;

  @override
  ScaleConnection get connection => switch (socket.connectionState) {
    MachineConnectionState.connected =>
      socket.latestStatus == null
          ? ScaleConnection.connecting
          : ScaleConnection.connected,
    MachineConnectionState.connecting => ScaleConnection.connecting,
    _ => ScaleConnection.disconnected,
  };

  @override
  String? get deviceName => name;

  @override
  String? get error => isConnected ? null : socket.lastError;

  double? _raw;
  double _offset = 0;

  @override
  double? get grams {
    final raw = _raw;
    if (raw == null || !isConnected) return null;
    return raw - _offset;
  }

  final _readings = StreamController<ScaleReading>.broadcast();
  @override
  Stream<ScaleReading> get readings => _readings.stream;

  final _deviceTares = StreamController<double>.broadcast();
  @override
  Stream<double> get deviceTares => _deviceTares.stream;

  /// Ticks of exactly 0.00 in a row that make a tare.
  static const zeroStreakForTare = 3;

  /// A jump from at least this much counts (smaller: nothing on the scale).
  static const minTaredLoad = 0.3;

  int _zeroStreak = 0;
  double? _beforeZero;
  double? _prevRaw;
  DateTime? _ownTareUntil;

  // After a network stall the machine's packets arrive all at once — with
  // (nearly) the same receive time they would make absurd flows. Within
  // this gap only the weight is updated, no reading is sent.
  final Duration minReadingGap;
  DateTime? _lastReadingAt;

  void _detectDeviceTare(double raw) {
    final exactZero = raw.abs() < 0.005;
    if (!exactZero) {
      _zeroStreak = 0;
      _prevRaw = raw;
      return;
    }
    if (_zeroStreak == 0) _beforeZero = _prevRaw;
    _prevRaw = raw;
    _zeroStreak++;
    if (_zeroStreak != zeroStreakForTare) return;
    final before = _beforeZero;
    if (before == null || before.abs() < minTaredLoad) return;
    final own = _ownTareUntil;
    if (own != null && clock.now().isBefore(own)) return;
    // The machine's zero is the reference again (also after a fallback
    // tare in the app).
    final grams = before - _offset;
    _offset = 0;
    if (!_deviceTares.isClosed) _deviceTares.add(grams);
  }

  MachineStatus? _lastStatus;
  ScaleConnection? _lastConnection;

  // The socket notifies on every status AND sensors event — only a new
  // status object is a new weight.
  void _onSocket() {
    final status = socket.latestStatus;
    final connection = this.connection;
    final changed = connection != _lastConnection;
    _lastConnection = connection;
    if (status != null && !identical(status, _lastStatus)) {
      _lastStatus = status;
      final w = status.weight;
      if (w.isFinite) {
        _raw = w;
        _detectDeviceTare(w);
        final now = clock.now();
        final last = _lastReadingAt;
        if (last == null || now.difference(last) >= minReadingGap) {
          _lastReadingAt = now;
          if (!_readings.isClosed) {
            _readings.add(ScaleReading(w - _offset, now));
          }
        }
        notifyListeners();
        return;
      }
    }
    if (changed) notifyListeners();
  }

  /// The machine is in an espresso session (heating, brewing, purging):
  /// then its scale belongs to the shot, a tare would disturb it.
  bool get machineBusy {
    final s = socket.latestStatus;
    if (s == null) return false;
    return s.state != 'idle' && s.phase != 'idle';
  }

  @override
  Future<void> connect() async {
    if (socket.connectionState == MachineConnectionState.connected ||
        socket.connectionState == MachineConnectionState.connecting) {
      return;
    }
    socket.connect();
  }

  // The machine connection stays up — it also serves the espresso mode.
  @override
  Future<void> disconnect() async {}

  @override
  Future<void> tare() async {
    if (!isConnected) throw StateError('Meticulous not connected');
    if (machineBusy) throw StateError('Meticulous is busy');
    // Our own tare is no dial tare.
    _ownTareUntil = clock.now().add(tareTimeout + const Duration(seconds: 2));
    final ok = await socket.triggerAction('tare');
    if (ok && await _waitForZero()) {
      _offset = 0;
    } else {
      // Fallback: tare in the app.
      _offset = _raw ?? 0;
    }
    _ownTareUntil = clock.now().add(const Duration(seconds: 1));
    final g = grams;
    if (g != null && !_readings.isClosed) {
      _readings.add(ScaleReading(g, clock.now()));
    }
    notifyListeners();
  }

  // Raw weight (without our offset) settles near 0 once the machine has
  // tared.
  Future<bool> _waitForZero() async {
    bool zero() => (_raw ?? double.infinity).abs() <= zeroTolerance;
    if (zero()) return true;
    final done = Completer<bool>();
    void check() {
      if (!done.isCompleted && zero()) done.complete(true);
    }

    socket.addListener(check);
    final timer = Timer(tareTimeout, () {
      if (!done.isCompleted) done.complete(false);
    });
    try {
      return await done.future;
    } finally {
      timer.cancel();
      socket.removeListener(check);
    }
  }

  @override
  void dispose() {
    socket.removeListener(_onSocket);
    _readings.close();
    _deviceTares.close();
    super.dispose();
  }
}
