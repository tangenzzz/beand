import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../crypto/bytes.dart';
import 'identity.dart';

// Where the sync key and the device id are stored.
//
// flutter_secure_storage: Android Keystore or iOS Keychain, as with the
// AI keys (services/ai/ai_key_store.dart). Additionally here:
//
//  * iOS: `first_unlock_this_device` — readable after the first unlock
//    (sync also runs when the app wakes up in the background), and
//    "this device": never in the iCloud Keychain, never in an iCloud backup.
//  * Android: the secure storage files are excluded from Auto Backup
//    (res/xml/backup_rules.xml, data_extraction_rules.xml). The Keystore
//    key that decrypts them never travels along anyway — a restored backup
//    would be just garbage data on the new device.
//  * Neither key nor device id are in shared_preferences, so not in the
//    app backup either (Settings → Backup). The backup takes the key only
//    password-protected (NIP-49). The device id must never travel along,
//    otherwise two devices would share one.

abstract class SyncKeyStore {
  /// Stored key, or null as long as sync has never been turned on.
  Future<SyncIdentity?> readIdentity();
  Future<void> writeIdentity(SyncIdentity identity);
  Future<void> deleteIdentity();

  /// Id of this device; created on first call and then kept.
  Future<String> deviceId();
}

class SecureSyncKeyStore implements SyncKeyStore {
  SecureSyncKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(iOptions: _iosOptions);

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static const _privateKeyKey = 'sync_private_key';
  static const _deviceIdKey = 'sync_device_id';

  final FlutterSecureStorage _storage;

  @override
  Future<SyncIdentity?> readIdentity() async {
    final hex = await _storage.read(key: _privateKeyKey);
    if (hex == null || hex.isEmpty) return null;
    return SyncIdentity.fromPrivateKeyInBackground(hexDecode(hex));
  }

  @override
  Future<void> writeIdentity(SyncIdentity identity) => _storage.write(
    key: _privateKeyKey,
    value: hexEncode(identity.privateKeyBytes),
  );

  @override
  Future<void> deleteIdentity() => _storage.delete(key: _privateKeyKey);

  @override
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: created);
    return created;
  }
}

/// For tests and as a fallback when the device keystore does not answer.
class InMemorySyncKeyStore implements SyncKeyStore {
  Uint8List? _privateKey;
  String? _deviceId;

  @override
  Future<SyncIdentity?> readIdentity() async {
    final key = _privateKey;
    return key == null ? null : SyncIdentity.fromPrivateKey(key);
  }

  @override
  Future<void> writeIdentity(SyncIdentity identity) async =>
      _privateKey = identity.privateKeyBytes;

  @override
  Future<void> deleteIdentity() async => _privateKey = null;

  @override
  Future<String> deviceId() async => _deviceId ??= const Uuid().v4();
}
