import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'nip49.dart';

// Encrypt a whole backup with a password (Settings → Backup, selectable when
// creating). Same building blocks as NIP-49: scrypt → XChaCha20-Poly1305.
//
// A backup can be several hundred MB, hence chunks of 1 MiB, each with its
// own nonce and MAC. The chunks are bound to their position by their number
// and the "last chunk" flag (both in the AAD): reordering, omitting or
// truncating is detected on decryption.
//
// File:   "BEANDENC" · version (1) · log_n (1) · salt (16)
// Chunk:  flag (1: 0 = more, 1 = last) · plaintext length (4, BE)
//         · nonce (24) · ciphertext · MAC (16)
//
// Both are slow (scrypt with 64 MiB, ChaCha in pure Dart) — callers run it
// in an isolate.

const backupCipherMagic = 'BEANDENC';
const _version = 1;
const _chunkSize = 1 << 20;
const _headerLength = 8 + 1 + 1 + 16;

class BackupCipherException implements Exception {
  const BackupCipherException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _aead = Xchacha20.poly1305Aead();

/// Whether [file] is an encrypted backup (detected by the first bytes).
bool isEncryptedBackup(File file) {
  try {
    final raf = file.openSync();
    try {
      final head = raf.readSync(backupCipherMagic.length);
      return String.fromCharCodes(head) == backupCipherMagic;
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
}

Uint8List _aad(Uint8List header, int index, bool last) {
  final b = ByteData(_headerLength + 5);
  final out = b.buffer.asUint8List()..setRange(0, _headerLength, header);
  b.setUint32(_headerLength, index);
  b.setUint8(_headerLength + 4, last ? 1 : 0);
  return out;
}

/// Encrypts [source] to [target].
Future<void> encryptBackupFile(
  File source,
  File target,
  String password, {
  int logN = nip49DefaultLogN,
}) async {
  final salt = secureRandomBytes(16);
  final header = Uint8List(_headerLength)
    ..setRange(0, 8, backupCipherMagic.codeUnits)
    ..[8] = _version
    ..[9] = logN
    ..setRange(10, 26, salt);
  final key = SecretKey(passwordKey(password, salt, logN));

  final input = source.openSync();
  final output = target.openSync(mode: FileMode.write);
  try {
    output.writeFromSync(header);
    final total = input.lengthSync();
    var offset = 0;
    var index = 0;
    // An empty file also gets an (empty) last chunk.
    do {
      final plain = input.readSync(_chunkSize);
      offset += plain.length;
      final last = offset >= total;
      final nonce = secureRandomBytes(24);
      final box = await _aead.encrypt(
        plain,
        secretKey: key,
        nonce: nonce,
        aad: _aad(header, index, last),
      );
      final meta = ByteData(5)
        ..setUint8(0, last ? 1 : 0)
        ..setUint32(1, plain.length);
      output
        ..writeFromSync(meta.buffer.asUint8List())
        ..writeFromSync(nonce)
        ..writeFromSync(box.cipherText)
        ..writeFromSync(box.mac.bytes);
      index++;
      if (last) break;
    } while (true);
  } finally {
    input.closeSync();
    output.closeSync();
  }
}

/// Decrypts [source] to [target]. Throws [BackupCipherException] on a wrong
/// password or a corrupted file.
Future<void> decryptBackupFile(
  File source,
  File target,
  String password,
) async {
  final input = source.openSync();
  RandomAccessFile? output;
  try {
    final header = input.readSync(_headerLength);
    if (header.length != _headerLength ||
        String.fromCharCodes(header.sublist(0, 8)) != backupCipherMagic) {
      throw const BackupCipherException('This is not an encrypted backup.');
    }
    if (header[8] != _version) {
      throw const BackupCipherException(
        'This backup was encrypted by a newer version of the app.',
      );
    }
    final logN = header[9];
    // Protection against absurd costs from a foreign file.
    if (logN > 22) {
      throw const BackupCipherException('This backup is damaged.');
    }
    final key = SecretKey(passwordKey(password, header.sublist(10, 26), logN));
    output = target.openSync(mode: FileMode.write);
    var index = 0;
    while (true) {
      final meta = input.readSync(5);
      if (meta.length != 5) {
        throw const BackupCipherException('This backup is incomplete.');
      }
      final last = meta[0] == 1;
      final length = ByteData.sublistView(meta).getUint32(1);
      if (length > _chunkSize) {
        throw const BackupCipherException('This backup is damaged.');
      }
      final nonce = input.readSync(24);
      final cipherText = input.readSync(length);
      final mac = input.readSync(16);
      if (nonce.length != 24 ||
          cipherText.length != length ||
          mac.length != 16) {
        throw const BackupCipherException('This backup is incomplete.');
      }
      final List<int> plain;
      try {
        plain = await _aead.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
          aad: _aad(header, index, last),
        );
      } on SecretBoxAuthenticationError {
        throw BackupCipherException(
          index == 0 ? 'Wrong password.' : 'This backup is damaged.',
        );
      }
      output.writeFromSync(plain);
      index++;
      if (last) break;
    }
    if (input.positionSync() != input.lengthSync()) {
      throw const BackupCipherException('This backup is damaged.');
    }
  } finally {
    input.closeSync();
    output?.closeSync();
  }
}
