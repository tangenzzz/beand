import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/hkdf.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'bytes.dart';

// d-tags of the sync events (NIP-78, kind 30078). The relay sees the d-tag
// in plain text; so it must reveal neither type nor ID of the record, but
// must always be the same for the same record (so a new event replaces the
// old one). Solution: HMAC with a secret that only one's own devices can
// derive from the private key.

const _syncSecretInfo = 'beand-sync-v1-dtag';

/// Secret only for d-tags, derived via HKDF-SHA256 from the private key —
/// so the key itself is never used for two purposes.
Uint8List deriveSyncSecret(Uint8List privateKey) {
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(
      HkdfParameters(
        privateKey,
        32,
        null,
        Uint8List.fromList(utf8.encode(_syncSecretInfo)),
      ),
    );
  final out = Uint8List(32);
  hkdf.deriveKey(null, 0, out, 0);
  return out;
}

/// `hex(HMAC-SHA256(syncSecret, "<entityType>:<syncId>"))`.
String syncDTag(Uint8List syncSecret, String entityType, String syncId) {
  final message = utf8.encode('$entityType:$syncId');
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(syncSecret));
  hmac.update(Uint8List.fromList(message), 0, message.length);
  final out = Uint8List(32);
  hmac.doFinal(out, 0);
  return hexEncode(out);
}
