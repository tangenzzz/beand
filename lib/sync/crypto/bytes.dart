import 'dart:math';
import 'dart:typed_data';

// Small byte helpers for the sync crypto. No cryptography in here — just
// hex, randomness from the system CSPRNG and constant-time comparison.

final _random = Random.secure();

/// [length] bytes from the system's cryptographically secure random
/// generator (Random.secure).
Uint8List secureRandomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

String hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Throws [FormatException] on odd length or invalid characters.
Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) throw const FormatException('Odd hex length');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(2 * i, 2 * i + 2), radix: 16);
    if (byte == null) throw const FormatException('Invalid hex');
    out[i] = byte;
  }
  return out;
}

/// Equality without early exit — for MACs, so the runtime does not reveal
/// at which byte a forged value differs.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

BigInt bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

/// Big-endian, left-padded with zeros to [length] bytes.
Uint8List bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  if (v != BigInt.zero) throw ArgumentError('Value too large');
  return out;
}
