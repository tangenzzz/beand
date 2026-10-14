import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/hkdf.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/stream/chacha7539.dart';

import 'bytes.dart';
import 'secp256k1.dart';

// NIP-44 version 2: encryption for Nostr content. Sync sends every record to
// its OWN public key; only your own devices can read it. Specification:
// https://github.com/nostr-protocol/nips/blob/master/44.md
//
// Building blocks (ECDH, HKDF, ChaCha20, HMAC-SHA256) come from pointycastle;
// only the composition per the specification is here, checked against the
// official test vectors (test/fixtures/nip44.vectors.json).
//
// Length: 1 to 65,535 bytes of plaintext. The specification now also allows
// longer messages (6-byte prefix), but the official vector file and many
// clients don't yet — sync doesn't need it, larger data goes as a blob.

const nip44Version = 2;
const nip44MinPlaintextSize = 1;
const nip44MaxPlaintextSize = 65535;

class Nip44Exception implements Exception {
  const Nip44Exception(this.message);
  final String message;
  @override
  String toString() => 'Nip44Exception: $message';
}

final _salt = Uint8List.fromList(utf8.encode('nip44-v2'));

/// Shared key of two parties; conv(a, B) == conv(b, A).
Uint8List conversationKey(Uint8List privateKey, Uint8List publicKeyX) {
  final shared = sharedX(privateKey, publicKeyX);
  return HKDFKeyDerivator(SHA256Digest()).extract(_salt, shared).key;
}

class MessageKeys {
  const MessageKeys(this.chachaKey, this.chachaNonce, this.hmacKey);
  final Uint8List chachaKey;
  final Uint8List chachaNonce;
  final Uint8List hmacKey;
}

MessageKeys messageKeys(Uint8List conversationKey, Uint8List nonce) {
  if (conversationKey.length != 32) {
    throw const Nip44Exception('Invalid conversation key length');
  }
  if (nonce.length != 32) throw const Nip44Exception('Invalid nonce length');
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(conversationKey, 76, null, nonce, true));
  final okm = Uint8List(76);
  hkdf.deriveKey(null, 0, okm, 0);
  return MessageKeys(
    okm.sublist(0, 32),
    okm.sublist(32, 44),
    okm.sublist(44, 76),
  );
}

int calcPaddedLength(int unpaddedLength) {
  if (unpaddedLength <= 32) return 32;
  final nextPower = 1 << ((unpaddedLength - 1).bitLength);
  final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
  return chunk * (((unpaddedLength - 1) ~/ chunk) + 1);
}

Uint8List _pad(String plaintext) {
  final bytes = utf8.encode(plaintext);
  final length = bytes.length;
  if (length < nip44MinPlaintextSize || length > nip44MaxPlaintextSize) {
    throw const Nip44Exception('Invalid plaintext length');
  }
  final out = Uint8List(2 + calcPaddedLength(length));
  out[0] = length >> 8;
  out[1] = length & 0xff;
  out.setRange(2, 2 + length, bytes);
  return out;
}

String _unpad(Uint8List padded) {
  if (padded.length < 2) throw const Nip44Exception('Invalid padding');
  final length = (padded[0] << 8) | padded[1];
  if (length < nip44MinPlaintextSize ||
      2 + length > padded.length ||
      padded.length != 2 + calcPaddedLength(length)) {
    throw const Nip44Exception('Invalid padding');
  }
  try {
    return utf8.decode(padded.sublist(2, 2 + length));
  } on FormatException {
    throw const Nip44Exception('Invalid UTF-8');
  }
}

Uint8List _chacha20(MessageKeys keys, Uint8List data) {
  final cipher = ChaCha7539Engine()
    ..init(
      true,
      ParametersWithIV<KeyParameter>(
        KeyParameter(keys.chachaKey),
        keys.chachaNonce,
      ),
    );
  return cipher.process(data);
}

Uint8List _hmacAad(Uint8List key, Uint8List nonce, Uint8List ciphertext) {
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
  hmac.update(nonce, 0, nonce.length);
  hmac.update(ciphertext, 0, ciphertext.length);
  final out = Uint8List(32);
  hmac.doFinal(out, 0);
  return out;
}

/// Encrypts [plaintext] into a base64 payload. Pass [nonce] only for test
/// vectors — otherwise the function draws a fresh random value itself; a
/// reused nonce would make the messages readable.
String nip44Encrypt(
  String plaintext,
  Uint8List conversationKey, {
  Uint8List? nonce,
}) {
  final n = nonce ?? secureRandomBytes(32);
  final keys = messageKeys(conversationKey, n);
  final ciphertext = _chacha20(keys, _pad(plaintext));
  final mac = _hmacAad(keys.hmacKey, n, ciphertext);
  final out = BytesBuilder(copy: false)
    ..addByte(nip44Version)
    ..add(n)
    ..add(ciphertext)
    ..add(mac);
  return base64.encode(out.toBytes());
}

String nip44Decrypt(String payload, Uint8List conversationKey) {
  if (payload.isEmpty) throw const Nip44Exception('Empty payload');
  if (payload[0] == '#') {
    throw const Nip44Exception('Unsupported encryption version');
  }
  // Limits per the specification, checked before decoding (protection
  // against oversized input). 65,535 bytes of plaintext yield at most 87,472
  // base64 characters.
  if (payload.length < 132 || payload.length > 87472) {
    throw const Nip44Exception('Invalid payload size');
  }
  final Uint8List data;
  try {
    data = base64.decode(payload);
  } on FormatException {
    throw const Nip44Exception('Invalid base64');
  }
  if (data.length < 99 || data.length > 65603) {
    throw const Nip44Exception('Invalid data size');
  }
  if (data[0] != nip44Version) {
    throw Nip44Exception('Unknown version ${data[0]}');
  }
  final nonce = data.sublist(1, 33);
  final ciphertext = data.sublist(33, data.length - 32);
  final mac = data.sublist(data.length - 32);
  final keys = messageKeys(conversationKey, nonce);
  if (!constantTimeEquals(_hmacAad(keys.hmacKey, nonce, ciphertext), mac)) {
    throw const Nip44Exception('Invalid MAC');
  }
  return _unpad(_chacha20(keys, ciphertext));
}
