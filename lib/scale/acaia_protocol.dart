// Acaia scales (Lunar, Pearl, Pyxis …) over BLE.
//
// Modeled on tatemazer/AcaiaArduinoBLE (MIT / public domain) —
// deliberately NOT on Beanconqueror (GPL-3.0). Two device generations:
//
// * old (before 2021): service 0x1820, one characteristic 0x2A80 for
//   reading and writing; weight packets without header (10 or 14 bytes).
// * new (Lunar/Pearl from 2021): Microchip "Transparent UART"
//   (49535343-…); weight packets with header EF DD 0C … 05 (13 or 17
//   bytes).
//
// Both require IDENTIFY + NOTIFICATION_REQUEST after connecting and then a
// HEARTBEAT every ~2.75 s, otherwise the scale disconnects.

import 'dart:typed_data';

enum AcaiaGeneration { old, modern }

class AcaiaUuids {
  static const oldService = '1820';
  static const oldChar = '2a80';

  static const modernService = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  static const modernWrite = '49535343-8841-43f4-a8d4-ecbe34729bb3';
  static const modernNotify = '49535343-1e4d-4bd9-ba61-23c647249616';
}

class AcaiaCommands {
  static final identify = Uint8List.fromList([
    0xef, 0xdd, 0x0b, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, //
    0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x9a, 0x6d,
  ]);
  static final notificationRequest = Uint8List.fromList([
    0xef, 0xdd, 0x0c, 0x09, 0x00, 0x01, 0x01, 0x02, 0x02, 0x05, //
    0x03, 0x04, 0x15, 0x06,
  ]);
  static final heartbeat = Uint8List.fromList([
    0xef,
    0xdd,
    0x00,
    0x02,
    0x00,
    0x02,
    0x00,
  ]);
  static final tare = Uint8List.fromList([0xef, 0xdd, 0x04, 0x00, 0x00, 0x00]);
  static final startTimer = Uint8List.fromList([
    0xef,
    0xdd,
    0x0d,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  static final stopTimer = Uint8List.fromList([
    0xef,
    0xdd,
    0x0d,
    0x00,
    0x02,
    0x00,
    0x02,
  ]);
  static final resetTimer = Uint8List.fromList([
    0xef,
    0xdd,
    0x0d,
    0x00,
    0x01,
    0x00,
    0x01,
  ]);
}

const acaiaHeartbeatPeriod = Duration(milliseconds: 2750);

/// If no packet arrives for this long, the connection counts as dead.
const acaiaPacketTimeout = Duration(seconds: 5);

/// Names Acaia scales advertise under (case-insensitive, prefix).
const acaiaNamePrefixes = [
  'ACAIA',
  'LUNAR',
  'PEARL',
  'PYXIS',
  'PROCH',
  'CINCO',
  'UMBRA',
];

bool isAcaiaName(String name) {
  final upper = name.toUpperCase();
  return acaiaNamePrefixes.any(upper.startsWith);
}

/// Assembles notifications into messages and returns the weights in them.
/// Needed because older scales in particular (PROCHBT/Lunar before 2021)
/// split one message across several BLE packets: header EF DD 0C in one,
/// the rest in the next. An "event" message looks like this:
///
///     `EF DD 0C <len> <type> …   — type 05 = weight:`
///     `EF DD 0C <len> 05 w0 w1 w2 w3 <dec> <sign> …`
class AcaiaFrameParser {
  final _buf = <int>[];

  /// Buffer at most this much; anything longer makes no sense and is dropped.
  static const _maxBuffer = 64;

  List<double> feed(List<int> packet) {
    _buf.addAll(packet);
    final out = <double>[];
    while (true) {
      final start = _header(0);
      if (start < 0) {
        // No header in sight: discard everything except a possibly
        // truncated EF at the end.
        final keepEf = _buf.isNotEmpty && _buf.last == 0xef;
        _buf.clear();
        if (keepEf) _buf.add(0xef);
        break;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < 5) break; // header present, rest still coming
      final cmd = _buf[2];
      if (cmd == 0x0c && _buf[4] == 0x05) {
        if (_buf.length < 11) break;
        final g = _weightAt(_buf, 5);
        if (g != null) out.add(g);
      }
      // On to the next message.
      final next = _header(2);
      if (next < 0) {
        // This message is processed (or uninteresting); a remainder
        // without a new header carries nothing more.
        final keepEf = _buf.last == 0xef;
        _buf.clear();
        if (keepEf) _buf.add(0xef);
        break;
      }
      _buf.removeRange(0, next);
    }
    if (_buf.length > _maxBuffer) _buf.removeRange(0, _buf.length - _maxBuffer);
    return out;
  }

  void reset() => _buf.clear();

  int _header(int from) {
    for (var i = from; i + 1 < _buf.length; i++) {
      if (_buf[i] == 0xef && _buf[i + 1] == 0xdd) return i;
    }
    return -1;
  }
}

/// Weight from a single packet without header (very old firmware sends the
/// weight this way after the header came in its own packet and was already
/// processed there). Only as a fallback when [AcaiaFrameParser] finds
/// nothing.
double? parseHeaderlessWeight(List<int> p) {
  if ((p.length == 10 || p.length == 14) && p[1] == 0x05) {
    return _weightAt(p, 2);
  }
  return null;
}

String hexPacket(List<int> p) =>
    p.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

double? _weightAt(List<int> p, int at) {
  final decimals = p[at + 4];
  // Only 0–4 decimal places make sense; anything else is not a weight
  // packet (guards against misreading foreign packets of the same length).
  if (decimals > 4) return null;
  final raw = p[at] | (p[at + 1] << 8) | (p[at + 2] << 16) | (p[at + 3] << 24);
  var grams = raw.toDouble();
  for (var i = 0; i < decimals; i++) {
    grams /= 10;
  }
  return (p[at + 5] & 0x02) != 0 ? -grams : grams;
}
