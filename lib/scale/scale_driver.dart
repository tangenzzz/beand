import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// What differs from scale to scale — the rest (scan, connect, reconnect,
// permissions) is the same Bluetooth plumbing in BleScale. One driver per
// family: Acaia, Decent, Bookoo. Which one applies is decided by the name
// the scale advertises.

/// The two channels a scale talks over (may be the same characteristic).
class ScaleChannels {
  const ScaleChannels({required this.notify, required this.write});
  final Characteristic notify;
  final Characteristic write;
}

/// A button on the scale that, while connected, only reports its press
/// and leaves the action to the app (Decent).
enum ScaleButton { tare, timer, timerReset }

/// What one notification packet said.
class ScalePacket {
  const ScalePacket({this.weights = const [], this.battery, this.button});
  static const empty = ScalePacket();

  /// Grams, oldest first (a packet may carry none or several).
  final List<double> weights;

  /// Battery in percent, if the packet tells.
  final int? battery;

  /// A button pressed on the scale, for the app to carry out.
  final ScaleButton? button;
}

abstract class ScaleDriver {
  /// Brand for messages ("No Decent scale found").
  String get brand;

  /// Does a scale advertising [name] speak this protocol?
  bool matches(String name);

  /// Picks notify/write from the discovered characteristics ([find] by
  /// UUID); throws [ScaleSetupException] if they are not there.
  ScaleChannels pick(Characteristic? Function(String uuid) find);

  /// Right after notifications are on (Acaia: identify + request).
  Future<void> start(Future<void> Function(Uint8List bytes) write) async {}

  /// Sent every [heartbeatPeriod] while connected; null = none needed.
  Uint8List? get heartbeat => null;
  Duration get heartbeatPeriod => const Duration(seconds: 3);

  /// No packet for this long: the link is dead, reconnect.
  Duration get packetTimeout;

  /// Write with response even where the characteristic also takes writes
  /// without (a lost heartbeat costs the connection).
  bool get writeWithResponse => false;

  /// Read the standard battery characteristic (0x2A19) now and then.
  bool get readsBatteryService => false;

  /// Sent once a minute so the scale reports its battery again (for
  /// scales that only tell it in answer to a command).
  Uint8List? get batteryRequest => null;

  /// New connection: drop half-read state.
  void reset() {}

  ScalePacket parse(List<int> packet);

  /// Commands; each may be several writes (some scales drop a command
  /// now and then, so it goes twice).
  List<Uint8List> get tare;
  List<Uint8List> get startTimer => const [];
  List<Uint8List> get stopTimer => const [];
  List<Uint8List> get resetTimer => const [];

  /// Pause between two writes of one command.
  Duration get repeatGap => const Duration(milliseconds: 60);

  /// Extra info for the settings (e.g. firmware generation), after pick.
  String? get details => null;
}

class ScaleSetupException implements Exception {
  const ScaleSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// XOR of [bytes] from [from] up to (not including) [to].
int xorOf(List<int> bytes, [int from = 0, int? to]) {
  var x = 0;
  for (var i = from; i < (to ?? bytes.length); i++) {
    x ^= bytes[i];
  }
  return x & 0xff;
}
