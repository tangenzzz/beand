import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'scale_driver.dart';

/// Bookoo Themis Mini / Ultra. Protocol from Bookoo's own repository
/// (github.com/BooKooCode/OpenSource, MIT, read 2026-10-21):
///
/// - Service 0FFE; weight notified on FF11, commands to FF12.
/// - Weight packet, 20 bytes: `03 0B`, timer (3 bytes, ms), unit, weight
///   sign, weight (3 bytes, grams × 100), flow sign, flow (2 bytes × 100),
///   battery %, standby (2), buzzer, flow smoothing, reserved, XOR of the
///   first 19 bytes. All big-endian.
/// - Commands, 6 bytes: `03 0A d1 d2 d3` + XOR of the first five.
///
/// The sign bytes' values are not documented; read as ASCII '-' (0x2D) for
/// negative, as other apps do — to check on a real scale.
class BookooDriver extends ScaleDriver {
  static const notifyUuid = '0000ff11-0000-1000-8000-00805f9b34fb';
  static const writeUuid = '0000ff12-0000-1000-8000-00805f9b34fb';

  @override
  String get brand => 'Bookoo';

  @override
  bool matches(String name) => name.toLowerCase().startsWith('bookoo');

  @override
  ScaleChannels pick(Characteristic? Function(String uuid) find) {
    final notify = find(notifyUuid);
    final write = find(writeUuid);
    if (notify == null || write == null) {
      throw const ScaleSetupException(
        'This scale does not speak the Bookoo protocol.',
      );
    }
    return ScaleChannels(notify: notify, write: write);
  }

  /// `03 0A d1 d2 d3` plus their XOR.
  static Uint8List command(int d1, [int d2 = 0, int d3 = 0]) {
    final five = [0x03, 0x0A, d1, d2, d3];
    return Uint8List.fromList([...five, xorOf(five)]);
  }

  static final tareCommand = command(0x01);
  static final timerStart = command(0x04);
  static final timerStop = command(0x05);
  static final timerReset = command(0x06);

  @override
  Duration get packetTimeout => const Duration(seconds: 5);

  @override
  List<Uint8List> get tare => [tareCommand];
  @override
  List<Uint8List> get startTimer => [timerStart];
  @override
  List<Uint8List> get stopTimer => [timerStop];
  @override
  List<Uint8List> get resetTimer => [timerReset];

  @override
  ScalePacket parse(List<int> p) {
    if (p.length < 20 || p[0] != 0x03 || p[1] != 0x0B) {
      return ScalePacket.empty;
    }
    if (xorOf(p, 0, 19) != p[19]) return ScalePacket.empty;
    final raw = (p[7] << 16) | (p[8] << 8) | p[9];
    final grams = (p[6] == 0x2D ? -raw : raw) / 100;
    final battery = p[13];
    return ScalePacket(
      weights: [grams],
      battery: battery <= 100 ? battery : null,
    );
  }
}
