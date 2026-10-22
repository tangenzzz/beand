import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../crypto/bytes.dart';

// Encrypt files before uploading: XChaCha20-Poly1305 (cryptography) with a
// separate random key per file. Key and nonce are in the reference (BlobRef)
// inside the encrypted sync record.
//
// All of it runs in a background isolate: in pure Dart, encrypting and
// hashing a photo of a few MB took ~11–12 s on the main isolate, during
// which the whole app froze — at every sync, i.e. every start and return to
// the app, and again each time while an upload stayed pending (connection
// log, 2026-10-22).

final _aead = Xchacha20.poly1305Aead();

class EncryptedBlob {
  const EncryptedBlob(this.bytes, this.key, this.nonce, this.sha256);

  /// Ciphertext + 16-byte MAC at the end.
  final Uint8List bytes;
  final String key;
  final String nonce;

  /// Of [bytes], computed with them (in the background).
  final String sha256;
}

String sha256Hex(List<int> data) =>
    hexEncode(SHA256Digest().process(Uint8List.fromList(data)));

Future<EncryptedBlob> encryptBlob(List<int> plain) {
  final input = plain is Uint8List ? plain : Uint8List.fromList(plain);
  return Isolate.run(() => _encrypt(input));
}

Future<EncryptedBlob> _encrypt(Uint8List plain) async {
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
  final bytes = out.toBytes();
  return EncryptedBlob(
    bytes,
    base64.encode(key),
    base64.encode(nonce),
    sha256Hex(bytes),
  );
}

/// [sha256Hex] in the background, for large files.
Future<String> sha256HexInBackground(List<int> data) {
  final input = data is Uint8List ? data : Uint8List.fromList(data);
  return Isolate.run(() => sha256Hex(input));
}

/// Throws [SecretBoxAuthenticationError] if the file was modified or the key
/// doesn't match.
Future<Uint8List> decryptBlob(List<int> bytes, String key, String nonce) {
  final input = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  return Isolate.run(() => _decrypt(input, key, nonce));
}

Future<Uint8List> _decrypt(Uint8List bytes, String key, String nonce) async {
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
