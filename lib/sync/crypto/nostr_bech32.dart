import 'dart:typed_data';

import 'package:bech32/bech32.dart';

// Bech32 notation for Nostr keys (NIP-19 npub/nsec, NIP-49 ncryptsec).
// Checksum and charset are handled by the bech32 package; here only the
// 8 ↔ 5 bit conversion (BIP-173), which the package does not expose.

const npubPrefix = 'npub';
const nsecPrefix = 'nsec';
const ncryptsecPrefix = 'ncryptsec';

// At 91 bytes, ncryptsec is longer than the 90 characters BIP-173 allows
// for addresses; NIP-49 deliberately specifies it that way.
const _maxLength = 200;

String bech32Encode(String prefix, List<int> bytes) => const Bech32Codec()
    .encode(Bech32(prefix, _convertBits(bytes, 8, 5, true)), _maxLength);

/// Decodes and checks the prefix. Throws [FormatException] on a wrong
/// prefix, broken checksum or wrong padding.
Uint8List bech32Decode(String expectedPrefix, String input) {
  final Bech32 decoded;
  try {
    decoded = const Bech32Codec().decode(
      input.trim().toLowerCase(),
      _maxLength,
    );
  } catch (e) {
    throw FormatException('Invalid bech32: $e');
  }
  if (decoded.hrp != expectedPrefix) {
    throw FormatException('Expected "$expectedPrefix", got "${decoded.hrp}"');
  }
  return Uint8List.fromList(_convertBits(decoded.data, 5, 8, false));
}

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxValue = (1 << to) - 1;
  for (final value in data) {
    if (value < 0 || (value >> from) != 0) {
      throw const FormatException('Value out of range');
    }
    acc = ((acc << from) | value) & 0xffffff;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((acc >> bits) & maxValue);
    }
  }
  if (pad) {
    if (bits > 0) result.add((acc << (to - bits)) & maxValue);
  } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
    throw const FormatException('Invalid padding');
  }
  return result;
}
