import 'dart:async';
import 'dart:math' as math;

import '../models/brew_plan.dart';
import 'brew_scale.dart';

/// Scale without hardware — only for tests and debug builds (Pour Over
/// never runs for users without a real scale). Can "pour" a plan: ideal
/// flow with some jitter, pauses per recipe.
class SimulatedScale extends BrewScale {
  SimulatedScale({this.speed = 1.0, this.autoPour, math.Random? random})
    : _random = random ?? math.Random(7);

  /// When set: every tare starts pouring this plan (debug mode).
  final BrewPlan? Function()? autoPour;

  /// >1 plays faster (e.g. 4 = brew in a quarter of the time).
  final double speed;
  final math.Random _random;

  ScaleConnection _connection = ScaleConnection.disconnected;
  @override
  ScaleConnection get connection => _connection;

  @override
  String? get deviceName => isConnected ? 'SIMULATED' : null;

  double _raw = 0;
  double _offset = 0;
  @override
  double? get grams => isConnected ? _raw - _offset : null;

  @override
  String? get error => null;
  @override
  int? get batteryPercent => isConnected ? 87 : null;

  final _readings = StreamController<ScaleReading>.broadcast();
  @override
  Stream<ScaleReading> get readings => _readings.stream;

  Timer? _emit;
  Timer? _pour;

  @override
  Future<void> connect() async {
    _connection = ScaleConnection.connected;
    _emit ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _send());
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _emit?.cancel();
    _emit = null;
    _pour?.cancel();
    _connection = ScaleConnection.disconnected;
    notifyListeners();
  }

  @override
  Future<void> tare() async {
    _pour?.cancel();
    _raw = 0;
    _offset = 0;
    _send();
    final plan = autoPour?.call();
    if (plan != null) simulate(plan);
  }

  /// Set the weight directly (tests).
  void setGrams(double g) {
    _raw = _offset + g;
    _send();
  }

  /// Pours [plan], starting after [delay].
  void simulate(BrewPlan plan, {Duration delay = const Duration(seconds: 2)}) {
    _pour?.cancel();
    var step = 0;
    var waitLeft = delay.inMilliseconds / 1000;
    var pouring = false;
    const dt = 0.1;
    _pour = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final sdt = dt * speed;
      if (step >= plan.steps.length) {
        t.cancel();
        return;
      }
      final s = plan.steps[step];
      if (!pouring) {
        waitLeft -= sdt;
        if (waitLeft <= 0) pouring = true;
        return;
      }
      final flow = idealPourFlow + (_random.nextDouble() - 0.4) * 2;
      final current = _raw - _offset;
      final next = math.min(s.targetTotalG, current + flow * sdt);
      _raw = _offset + next;
      if (next >= s.targetTotalG) {
        pouring = false;
        waitLeft = s.waitSeconds ?? 0;
        step++;
      }
    });
  }

  void _send() {
    if (!isConnected) return;
    // Jitter like a real scale (±0.1 g).
    final g =
        ((_raw - _offset) * 10).round() / 10 + ((_random.nextInt(3) - 1) / 10);
    _readings.add(ScaleReading(g, DateTime.now()));
    notifyListeners();
  }

  @override
  void dispose() {
    _emit?.cancel();
    _pour?.cancel();
    _readings.close();
    super.dispose();
  }
}
