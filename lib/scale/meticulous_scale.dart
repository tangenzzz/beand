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
/// No own connection: it rides on the existing [MeticulousSocketService].
class MeticulousScale extends BrewScale {
  MeticulousScale(
    this.socket, {
    this.tareTimeout = const Duration(seconds: 4),
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
        if (!_readings.isClosed) {
          _readings.add(ScaleReading(w - _offset, clock.now()));
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
    final ok = await socket.triggerAction('tare');
    if (ok && await _waitForZero()) {
      _offset = 0;
    } else {
      // Fallback: tare in the app.
      _offset = _raw ?? 0;
    }
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
    super.dispose();
  }
}
