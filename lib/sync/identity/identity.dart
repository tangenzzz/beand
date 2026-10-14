import 'dart:isolate';
import 'dart:typed_data';

import '../crypto/bytes.dart';
import '../crypto/dtag.dart';
import '../crypto/nip44.dart';
import '../crypto/nostr_bech32.dart';
import '../crypto/secp256k1.dart';

/// This user's sync key: all of their own devices share it; through it they
/// find their records on the relays, and only they can read them.
///
/// The private key leaves this class only via [privateKeyBytes] and
/// [nsec] — never log either. [toString] therefore only shows the public
/// part.
class SyncIdentity {
  SyncIdentity._(this._privateKey)
    : publicKey = publicKeyOf(_privateKey),
      syncSecret = deriveSyncSecret(_privateKey),
      _conversationKey = null;

  SyncIdentity._derived(
    this._privateKey,
    this.publicKey,
    this.syncSecret,
    Uint8List conversationKey,
  ) : _conversationKey = conversationKey;

  /// Like [SyncIdentity.fromPrivateKey], but with the curve math in a
  /// background isolate: deriving the key costs ~85 ms on a PC the first
  /// time — a noticeable stutter at app start.
  static Future<SyncIdentity> fromPrivateKeyInBackground(
    Uint8List privateKey,
  ) async {
    final key = Uint8List.fromList(privateKey);
    final (publicKey, syncSecret, conversation) = await Isolate.run(() {
      privateKeyScalar(key);
      final publicKey = publicKeyOf(key);
      return (
        publicKey,
        deriveSyncSecret(key),
        conversationKey(key, publicKey),
      );
    });
    return SyncIdentity._derived(key, publicKey, syncSecret, conversation);
  }

  /// Throws [InvalidKeyException] if [privateKey] is not a valid key.
  factory SyncIdentity.fromPrivateKey(Uint8List privateKey) {
    privateKeyScalar(privateKey);
    return SyncIdentity._(Uint8List.fromList(privateKey));
  }

  factory SyncIdentity.generate() => SyncIdentity._(generatePrivateKey());

  /// From `nsec1…` (e.g. when pairing a device).
  factory SyncIdentity.fromNsec(String nsec) =>
      SyncIdentity.fromPrivateKey(bech32Decode(nsecPrefix, nsec));

  final Uint8List _privateKey;

  /// x-only, 32 bytes.
  final Uint8List publicKey;

  /// Only for d-tags (see dtag.dart).
  final Uint8List syncSecret;

  Uint8List get privateKeyBytes => Uint8List.fromList(_privateKey);

  String get publicKeyHex => hexEncode(publicKey);
  String get npub => bech32Encode(npubPrefix, publicKey);
  String get nsec => bech32Encode(nsecPrefix, _privateKey);

  /// NIP-44 key for messages to oneself — the sync encrypts every record
  /// with it.
  late final Uint8List selfConversationKey =
      _conversationKey ?? conversationKey(_privateKey, publicKey);
  final Uint8List? _conversationKey;

  String dTag(String entityType, String syncId) =>
      syncDTag(syncSecret, entityType, syncId);

  @override
  String toString() => 'SyncIdentity($npub)';
}
