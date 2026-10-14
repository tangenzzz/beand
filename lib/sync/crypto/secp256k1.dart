import 'dart:typed_data';

import 'package:bip340/bip340.dart' as bip340;
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'bytes.dart';

// Keys on secp256k1 as Nostr uses them: private key = 32 bytes, public =
// only the x coordinate (BIP-340, 32 bytes). The math itself is done by
// pointycastle and bip340; only the BIP-340/NIP-44 checks around it are
// here.

final _curve = ECCurve_secp256k1();

/// Order of the group (n).
final BigInt secp256k1Order = _curve.n;

// Prime of the field (p); x coordinates must be smaller.
final _fieldPrime = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);

class InvalidKeyException implements Exception {
  const InvalidKeyException(this.message);
  final String message;
  @override
  String toString() => 'InvalidKeyException: $message';
}

/// Private key as a number; must be 32 bytes long and in [1, n-1].
BigInt privateKeyScalar(Uint8List privateKey) {
  if (privateKey.length != 32) {
    throw const InvalidKeyException('Private key must be 32 bytes');
  }
  final d = bytesToBigInt(privateKey);
  if (d == BigInt.zero || d >= secp256k1Order) {
    throw const InvalidKeyException('Private key out of range');
  }
  return d;
}

bool isValidPrivateKey(Uint8List privateKey) {
  try {
    privateKeyScalar(privateKey);
    return true;
  } on InvalidKeyException {
    return false;
  }
}

/// New private key from system randomness.
Uint8List generatePrivateKey() {
  while (true) {
    final candidate = secureRandomBytes(32);
    if (isValidPrivateKey(candidate)) return candidate;
  }
}

/// Public key (x-only, 32 bytes) for the private one.
Uint8List publicKeyOf(Uint8List privateKey) {
  privateKeyScalar(privateKey);
  return hexDecode(bip340.getPublicKey(hexEncode(privateKey)));
}

/// Point for the x coordinate with even y (lift_x from BIP-340). Throws if
/// there is no point on the curve with this x.
ECPoint liftX(Uint8List x) {
  if (x.length != 32) {
    throw const InvalidKeyException('Public key must be 32 bytes');
  }
  if (bytesToBigInt(x) >= _fieldPrime) {
    throw const InvalidKeyException('Public key out of range');
  }
  try {
    final point = _curve.curve.decodePoint([0x02, ...x]);
    if (point == null || point.isInfinity) {
      throw const InvalidKeyException('Public key is not on the curve');
    }
    return point;
  } on ArgumentError {
    // pointycastle finds no root: x is not on the curve.
    throw const InvalidKeyException('Public key is not on the curve');
  }
}

/// ECDH without hash: x coordinate of privateKey · publicKey (32 bytes), as
/// NIP-44 requires.
Uint8List sharedX(Uint8List privateKey, Uint8List publicKeyX) {
  final d = privateKeyScalar(privateKey);
  final shared = liftX(publicKeyX) * d;
  if (shared == null || shared.isInfinity) {
    throw const InvalidKeyException('Shared point is at infinity');
  }
  return bigIntToBytes(shared.x!.toBigInteger()!, 32);
}
