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
///   both. Like Beanconqueror (graphefruit/Beanconqueror, decentScale.ts):
///   every 2 s, the first right away, written with response; at 4 s
///   without a first beat the scale dropped us every few seconds.
/// - Byte 0 of a weight packet is the model byte (03 on the Decent
///   Scale), so it is not checked.
/// - LED on/off is answered with the battery in byte 4 (3–100 %, FF = on
///   USB/charging); LED-on goes again once a minute for a fresh level.
///   Decent Scale: `03 0A 00 00 battery firmware xor`, firmware FE = 1.0,
///   02 = 1.1, 03 = 1.2. Half Decent (open firmware, decentespresso/
///   openscale `buildLedResponsePacket`): bytes 2–3 the weight, 5–6 the
///   version (BCD major, minor<<4 | patch), no checksum — that is how the
///   two are told apart.
/// - Buttons while connected (`03 AA button press …`, button 01 = O,
///   02 = square; press 01 short, 02 long): the Decent Scale only reports
///   and leaves tare/timer to the app. The Half Decent does nothing at all
///   by default and with "BLE Buttons" on in its menu carries them out
///   itself, so there the app does nothing.
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
    // The 5 s run from the opt-in, the periodic beat only starts after us.
    await write(heartbeatCommand);
  }

  @override
  Uint8List get heartbeat => heartbeatCommand;

  @override
  Uint8List get batteryRequest => ledOnGrams;

  String? _firmware;
  bool _halfDecent = false;

  @override
  void reset() {
    _firmware = null;
    _halfDecent = false;
  }

  @override
  String? get details => _firmware == null ? null : 'firmware $_firmware';

  @override
  Duration get heartbeatPeriod => const Duration(seconds: 2);

  @override
  Duration get packetTimeout => const Duration(seconds: 5);

  @override
  bool get writeWithResponse => true;

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
    if (grams != null) return ScalePacket(weights: [grams]);
    if (p.length < 7) return ScalePacket.empty;
    switch (p[1]) {
      case 0x0A:
        if (xorOf(p, 0, 6) == p[6]) {
          _firmware =
              switch (p[5]) {
                0xFE => '1.0',
                0x02 => '1.1',
                0x03 => '1.2',
                _ => null,
              } ??
              _firmware;
        } else {
          _halfDecent = true;
          final major = (p[5] >> 4) * 10 + (p[5] & 0x0F);
          _firmware = 'Half Decent $major.${p[6] >> 4}.${p[6] & 0x0F}';
        }
        final level = p[4];
        // FF = on USB, no level to show.
        return ScalePacket(battery: level <= 100 ? level : null);
      case 0xAA:
        if (_halfDecent) return ScalePacket.empty;
        final button = switch ((p[2], p[3])) {
          (0x01, 0x01) => ScaleButton.tare,
          (0x02, 0x01) => ScaleButton.timer,
          (0x02, 0x02) => ScaleButton.timerReset,
          _ => null,
        };
        return ScalePacket(button: button);
    }
    return ScalePacket.empty;
  }

  /// Grams from a weight packet, null for anything else or a bad checksum.
  static double? parseWeight(List<int> p) {
    if (p.length < 7) return null;
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
