import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../crypto/bytes.dart';

// Encrypt files before uploading: XChaCha20-Poly1305 (cryptography) with a
// separate random key per file. Key and nonce are in the reference (BlobRef)
// inside the encrypted sync record.

final _aead = Xchacha20.poly1305Aead();

class EncryptedBlob {
  const EncryptedBlob(this.bytes, this.key, this.nonce);

  /// Ciphertext + 16-byte MAC at the end.
  final Uint8List bytes;
  final String key;
  final String nonce;

  String get sha256 => sha256Hex(bytes);
}

String sha256Hex(List<int> data) =>
    hexEncode(SHA256Digest().process(Uint8List.fromList(data)));

Future<EncryptedBlob> encryptBlob(List<int> plain) async {
  final key = secureRandomBytes(32);
  final nonce = secureRandomBytes(24);
  final box = await _aead.encrypt(
    plain,
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  final out = BytesBuilder(copy: false)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return EncryptedBlob(out.toBytes(), base64.encode(key), base64.encode(nonce));
}

/// Throws [SecretBoxAuthenticationError] if the file was modified or the key
/// doesn't match.
Future<Uint8List> decryptBlob(List<int> bytes, String key, String nonce) async {
  if (bytes.length < 16) throw const FormatException('Blob too short');
  final split = bytes.length - 16;
  final plain = await _aead.decrypt(
    SecretBox(
      bytes.sublist(0, split),
      nonce: base64.decode(nonce),
      mac: Mac(bytes.sublist(split)),
    ),
    secretKey: SecretKey(base64.decode(key)),
  );
  return Uint8List.fromList(plain);
}
