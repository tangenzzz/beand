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

/// A scale the app has been connected to; stays listed while it is off, like
/// the known devices in the phone's Bluetooth settings.
@immutable
class KnownScale {
  const KnownScale({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};

  static KnownScale? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    return id is String && name is String
        ? KnownScale(id: id, name: name)
        : null;
  }
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

  /// Every scale the app has been connected to, in the order they were added.
  List<KnownScale> get knownScales => const [];

  /// Removes a scale from [knownScales]; disconnects if it is in use.
  Future<void> forgetScale(String id) async {}

  /// Whether Bluetooth is switched off on the phone.
  Future<bool> get bluetoothOff async => false;

  /// True when Bluetooth goes off, false when it comes on.
  Stream<bool> get bluetoothOffChanges => const Stream.empty();

  /// Asks to switch Bluetooth on: the system's dialog on Android. iOS has
  /// none for apps. Returns whether it is on now.
  Future<bool> requestBluetoothOn() async => !await bluetoothOff;

  /// Technical extra info for the settings (e.g. firmware generation).
  String? get details => null;

  /// The scale built into an espresso machine (Meticulous): mains powered,
  /// no Bluetooth, and Pour Over runs with the machine's own filter
  /// profiles plus the setup steps (server, brewer, coffee).
  bool get isMachineScale => false;

  /// Last reading in grams, null before the first packet.
  double? get grams;

  /// Every new reading (scales deliver ~5–10 per second).
  Stream<ScaleReading> get readings;

  /// Tares done on the device itself, not by the app (the Meticulous' dial
  /// in its own Pour Over mode): the weight that stood on the scale just
  /// before. Scales that can't tell stay silent.
  Stream<double> get deviceTares => const Stream.empty();

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
