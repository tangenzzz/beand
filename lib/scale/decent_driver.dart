import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'scale_driver.dart';

/// Decent Scale / Half Decent Scale. Protocol from Decent's own pages
/// (decentespresso.com/decentscale_api and the programmer's guide to the
/// Half Decent Scale, read 2026-10-21):
///
/// - Advertises "Decent Scale"; notify on FFF4, commands to 36F5.
/// - Weight 10× a second: `03 CE|CA hi lo …`, signed 16 bit big-endian in
///   tenths of a gram (CE = settled, CA = changing). 7 bytes on firmware
///   1.0/1.1, 10 bytes (with a timer) from 1.2 on; the last byte is an XOR
///   checksum.
/// - Commands are 7 bytes, the 7th the XOR of the first six. Firmware 1.0
///   may drop a command, so each goes twice, ~250 ms apart (a second one
///   while the first still runs is ignored).
/// - Heartbeat at least every 5 s, or the Half Decent drops the link. We
///   opt in to it (last data byte 01 in LED-on/tare) — older scales ignore
///   both.
class DecentDriver extends ScaleDriver {
  static const notifyUuid = '0000fff4-0000-1000-8000-00805f9b34fb';
  static const writeUuid = '000036f5-0000-1000-8000-00805f9b34fb';

  @override
  String get brand => 'Decent';

  @override
  bool matches(String name) => name.toLowerCase().startsWith('decent');

  @override
  ScaleChannels pick(Characteristic? Function(String uuid) find) {
    final notify = find(notifyUuid);
    final write = find(writeUuid);
    if (notify == null || write == null) {
      throw const ScaleSetupException(
        'This scale does not speak the Decent protocol.',
      );
    }
    return ScaleChannels(notify: notify, write: write);
  }

  /// Six bytes plus their XOR.
  static Uint8List command(List<int> six) =>
      Uint8List.fromList([...six, xorOf(six)]);

  static final ledOnGrams = command(const [0x03, 0x0A, 0x01, 0x01, 0x00, 0x01]);
  static final tareCommand = command(const [
    0x03,
    0x0F,
    0x00,
    0x00,
    0x00,
    0x01,
  ]);
  static final timerStart = command(const [0x03, 0x0B, 0x03, 0x00, 0x00, 0x00]);
  static final timerStop = command(const [0x03, 0x0B, 0x00, 0x00, 0x00, 0x00]);
  static final timerReset = command(const [0x03, 0x0B, 0x02, 0x00, 0x00, 0x00]);
  static final heartbeatCommand = command(const [
    0x03,
    0x0A,
    0x03,
    0xFF,
    0xFF,
    0x00,
  ]);

  @override
  Future<void> start(Future<void> Function(Uint8List bytes) write) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Display on, in grams — and with it the heartbeat opt-in.
    for (final bytes in twice(ledOnGrams)) {
      await write(bytes);
      await Future<void>.delayed(repeatGap);
    }
  }

  @override
  Uint8List get heartbeat => heartbeatCommand;

  @override
  Duration get heartbeatPeriod => const Duration(seconds: 4);

  @override
  Duration get packetTimeout => const Duration(seconds: 3);

  @override
  Duration get repeatGap => const Duration(milliseconds: 250);

  static List<Uint8List> twice(Uint8List bytes) => [bytes, bytes];

  @override
  List<Uint8List> get tare => twice(tareCommand);
  @override
  List<Uint8List> get startTimer => twice(timerStart);
  @override
  List<Uint8List> get stopTimer => twice(timerStop);
  @override
  List<Uint8List> get resetTimer => twice(timerReset);

  @override
  ScalePacket parse(List<int> p) {
    final grams = parseWeight(p);
    return grams == null ? ScalePacket.empty : ScalePacket(weights: [grams]);
  }

  /// Grams from a weight packet, null for anything else or a bad checksum.
  static double? parseWeight(List<int> p) {
    if (p.length < 7 || p[0] != 0x03) return null;
    if (p[1] != 0xCE && p[1] != 0xCA) return null;
    // The checksum is documented over the first six bytes (7-byte packets);
    // for the longer one either reading is accepted.
    final last = p.last;
    if (xorOf(p, 0, 6) != p[6] && xorOf(p, 0, p.length - 1) != last) {
      return null;
    }
    var raw = (p[2] << 8) | p[3];
    if (raw >= 0x8000) raw -= 0x10000;
    return raw / 10;
  }
}
