import 'package:flutter/foundation.dart';

enum ScaleConnection { disconnected, scanning, connecting, connected }

/// A scale reading.
@immutable
class ScaleReading {
  const ScaleReading(this.grams, this.at);
  final double grams;
  final DateTime at;
}

/// A scale that showed up during the scan.
@immutable
class ScaleCandidate {
  const ScaleCandidate({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Android: MAC address, iOS: a UUID assigned by the system.
  final String id;
  final String name;

  /// Signal strength in dBm (closer to 0 = closer by).
  final int rssi;

  @override
  bool operator ==(Object other) => other is ScaleCandidate && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A Bluetooth scale for Pour Over. Pour Over only runs with a connected
/// scale — the rest of the app only knows this interface, not the Acaia
/// protocol behind it.
abstract class BrewScale extends ChangeNotifier {
  ScaleConnection get connection;
  bool get isConnected => connection == ScaleConnection.connected;

  /// Name the scale advertises (e.g. "LUNAR-1A2B3C").
  String? get deviceName;

  /// Battery level in percent, null while unknown (or without battery service).
  int? get batteryPercent => null;

  /// Device the app last connected to (preferred).
  String? get rememberedId => null;

  /// Technical extra info for the settings (e.g. firmware generation).
  String? get details => null;

  /// Last reading in grams, null before the first packet.
  double? get grams;

  /// Every new reading (scales deliver ~5–10 per second).
  Stream<ScaleReading> get readings;

  /// Readable reason why the last connection failed.
  String? get error;

  /// The latest raw packets (hex, newest last) — for debugging in the
  /// settings.
  List<String> get recentPackets => const [];

  /// Scans for nearby scales; ends after [timeout].
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => const Stream.empty();

  /// Scans and connects (preferring [rememberedId]); returns once connected
  /// or failed.
  Future<void> connect();

  /// Connects to a specific device from [scan] and remembers it.
  Future<void> connectTo(ScaleCandidate candidate) => connect();

  Future<void> disconnect();

  /// Disconnects and forgets the remembered device.
  Future<void> forget() => disconnect();

  Future<void> tare();

  /// The scale's own timer on its display, so it runs along with the app.
  /// Scales without one simply do nothing.
  Future<void> startTimer() async {}
  Future<void> stopTimer() async {}
  Future<void> resetTimer() async {}
}

/// Short model name for tight spots (command row). Decent advertises
/// "Decent Scale", Bookoo names starting with "BOOKOO". The Acaia advertises
/// device names like "PROCHBT001" (Pearl) or "ACAIAL13006" (Lunar), both
/// read off real scales. Unknown names stay as they are.
String scaleShortName(String? name) {
  if (name == null || name.isEmpty) return 'Scale';
  final n = name.toUpperCase();
  if (n.startsWith('PEARLS')) return 'Pearl S';
  if (n.startsWith('PROCH') || n.startsWith('PEARL')) return 'Pearl';
  if (n.startsWith('ACAIAL') || n.startsWith('LUNAR')) return 'Lunar';
  if (n.startsWith('PYXIS')) return 'Pyxis';
  if (n.startsWith('CINCO')) return 'Cinco';
  if (n.startsWith('UMBRA')) return 'Umbra';
  if (n.startsWith('DECENT')) return 'Decent';
  if (n.startsWith('BOOKOO')) return 'Bookoo';
  return name;
}
