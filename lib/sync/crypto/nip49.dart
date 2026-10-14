import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'bytes.dart';
import 'nostr_bech32.dart';
import 'secp256k1.dart';

// NIP-49: private key encrypted with a password (`ncryptsec1…`). This is
// how the sync key ends up in the backup and in the pairing QR code.
// https://github.com/nostr-protocol/nips/blob/master/49.md
//
// scrypt (pointycastle) → XChaCha20-Poly1305 (cryptography). Both are slow
// and need a lot of memory (log_n 16 = 64 MiB) — callers in the app run
// it in an isolate (compute), never on the UI thread.

const _version = 0x02;

/// Default cost factor: 2^16 rounds, ~64 MiB.
const nip49DefaultLogN = 16;

/// KEY_SECURITY_BYTE: 0x00 handled insecurely, 0x01 never insecure, 0x02
/// unknown. bean'd doesn't keep track of it.
const nip49KeySecurityUnknown = 0x02;

class Nip49Exception implements Exception {
  const Nip49Exception(this.message);
  final String message;
  @override
  String toString() => 'Nip49Exception: $message';
}

/// Key from password (NFKC, scrypt r=8 p=1, 32 bytes) — also for the
/// encrypted backup (backup_cipher.dart). Slow: isolate only.
Uint8List passwordKey(String password, Uint8List salt, int logN) {
  final normalized = unorm.nfkc(password);
  final scrypt = Scrypt()..init(ScryptParameters(1 << logN, 8, 1, 32, salt));
  return scrypt.process(Uint8List.fromList(utf8.encode(normalized)));
}

final _aead = Xchacha20.poly1305Aead();

Future<String> nip49Encrypt(
  Uint8List privateKey,
  String password, {
  int logN = nip49DefaultLogN,
  int keySecurity = nip49KeySecurityUnknown,
  Uint8List? salt,
  Uint8List? nonce,
}) async {
  privateKeyScalar(privateKey);
  final s = salt ?? secureRandomBytes(16);
  final n = nonce ?? secureRandomBytes(24);
  final key = passwordKey(password, s, logN);
  final box = await _aead.encrypt(
    privateKey,
    secretKey: SecretKey(key),
    nonce: n,
    aad: [keySecurity],
  );
  key.fillRange(0, key.length, 0);
  final out = BytesBuilder(copy: false)
    ..addByte(_version)
    ..addByte(logN)
    ..add(s)
    ..add(n)
    ..addByte(keySecurity)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  final bytes = out.toBytes();
  assert(bytes.length == 91);
  return bech32Encode(ncryptsecPrefix, bytes);
}

/// Throws [Nip49Exception] on a wrong password or broken input.
Future<Uint8List> nip49Decrypt(String ncryptsec, String password) async {
  final Uint8List data;
  try {
    data = bech32Decode(ncryptsecPrefix, ncryptsec);
  } on FormatException catch (e) {
    throw Nip49Exception('Not a valid encrypted key: ${e.message}');
  }
  if (data.length != 91) throw const Nip49Exception('Invalid length');
  if (data[0] != _version) {
    throw Nip49Exception('Unsupported version ${data[0]}');
  }
  final logN = data[1];
  // Guard against absurd costs from a foreign file (2^22 = 4 GiB).
  if (logN > 22) throw const Nip49Exception('Cost factor too high');
  final salt = data.sublist(2, 18);
  final nonce = data.sublist(18, 42);
  final keySecurity = data[42];
  final cipherText = data.sublist(43, 75);
  final mac = data.sublist(75, 91);
  final key = passwordKey(password, salt, logN);
  try {
    final plain = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
      aad: [keySecurity],
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw const Nip49Exception('Wrong password');
  } finally {
    key.fillRange(0, key.length, 0);
  }
}
