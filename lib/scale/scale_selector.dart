import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'brew_scale.dart';

/// Which scale Pour Over uses.
enum ScaleSource { bluetooth, meticulous }

/// The one [BrewScale] the app sees: forwards everything to the chosen
/// scale (Bluetooth scale or the Meticulous' built-in one). Switching keeps
/// the Bluetooth scale connected (like switching the pills), so switching
/// back is instant.
class ScaleSelector extends BrewScale {
  ScaleSelector({
    required this.bluetooth,
    required this.meticulous,
    ScaleSource initial = ScaleSource.bluetooth,
  }) : _source = initial {
    bluetooth.addListener(_onBluetooth);
    meticulous.addListener(_onMeticulous);
    _subscribe();
  }

  static const prefKey = 'pourover_scale_source';

  final BrewScale bluetooth;
  final BrewScale meticulous;

  ScaleSource _source;
  ScaleSource get source => _source;

  BrewScale get active =>
      _source == ScaleSource.meticulous ? meticulous : bluetooth;

  /// Reads the stored choice (call once at startup).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(prefKey);
      final s = ScaleSource.values.where((v) => v.name == stored).firstOrNull;
      if (s != null && s != _source) {
        _source = s;
        _subscribe();
        notifyListeners();
      }
    } catch (_) {}
  }

  void setSource(ScaleSource value) {
    if (value == _source) return;
    _source = value;
    _subscribe();
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(prefKey, value.name))
        .catchError((Object _) => false);
  }

  final _readings = StreamController<ScaleReading>.broadcast();
  StreamSubscription<ScaleReading>? _sub;

  void _subscribe() {
    _sub?.cancel();
    _sub = active.readings.listen((r) {
      if (!_readings.isClosed) _readings.add(r);
    });
  }

  // Only the chosen scale's changes matter — the Meticulous ticks ~9×/s
  // even while a Bluetooth scale is in use.
  void _onBluetooth() {
    if (_source == ScaleSource.bluetooth) notifyListeners();
  }

  void _onMeticulous() {
    if (_source == ScaleSource.meticulous) notifyListeners();
  }

  @override
  Stream<ScaleReading> get readings => _readings.stream;

  @override
  bool get isMachineScale => active.isMachineScale;
  @override
  ScaleConnection get connection => active.connection;
  @override
  String? get deviceName => active.deviceName;
  @override
  int? get batteryPercent => active.batteryPercent;
  @override
  String? get rememberedId => active.rememberedId;
  @override
  String? get details => active.details;
  @override
  double? get grams => active.grams;
  @override
  String? get error => active.error;
  @override
  List<String> get recentPackets => active.recentPackets;

  @override
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => bluetooth.scan(timeout: timeout);

  @override
  Future<void> connect() => active.connect();
  @override
  Future<void> connectTo(ScaleCandidate candidate) {
    // Picking a Bluetooth scale in the settings means: use Bluetooth.
    setSource(ScaleSource.bluetooth);
    return bluetooth.connectTo(candidate);
  }

  @override
  Future<void> disconnect() => active.disconnect();
  @override
  Future<void> forget() => bluetooth.forget();
  @override
  Future<void> tare() => active.tare();
  @override
  Future<void> startTimer() => active.startTimer();
  @override
  Future<void> stopTimer() => active.stopTimer();
  @override
  Future<void> resetTimer() => active.resetTimer();

  @override
  void dispose() {
    bluetooth.removeListener(_onBluetooth);
    meticulous.removeListener(_onMeticulous);
    _sub?.cancel();
    _readings.close();
    super.dispose();
  }
}
