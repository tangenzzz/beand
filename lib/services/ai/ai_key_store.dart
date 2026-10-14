import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_provider.dart';

// Where the API keys are stored.
//
// NOT in shared_preferences, where all other settings live: on Android that
// is an XML file in the app folder and readable on a rooted device.
// flutter_secure_storage puts the value into the Android Keystore or the iOS
// Keychain — the only new dependency the AI brings along, and it exists
// exactly for this.
//
// Two consequences, both intended:
//
//  * Each provider has its own slot. Switching back and forth between Gemini
//    and Claude does not require pasting the key again each time.
//  * The backup (Settings → Backup) does NOT include the key. It packs the
//    app folder and the prefs; the keychain lives outside. A key also does
//    not belong in a zip file that leaves the device via the share dialog —
//    after a restore you enter it once again.
abstract class AiKeyStore {
  Future<String?> read(AiProvider provider);
  Future<void> write(AiProvider provider, String key);
  Future<void> delete(AiProvider provider);

  /// Which providers have a key — once at startup, so the UI can show the
  /// state without holding the keys themselves.
  Future<Set<AiProvider>> providersWithKey() async {
    final result = <AiProvider>{};
    for (final provider in AiProvider.values) {
      final key = await read(provider);
      if (key != null && key.isNotEmpty) result.add(provider);
    }
    return result;
  }

  static String prefKey(AiProvider provider) => 'ai_key_${provider.name}';
}

class SecureAiKeyStore implements AiKeyStore {
  SecureAiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(AiProvider provider) =>
      _storage.read(key: AiKeyStore.prefKey(provider));

  @override
  Future<void> write(AiProvider provider, String key) =>
      _storage.write(key: AiKeyStore.prefKey(provider), value: key);

  @override
  Future<void> delete(AiProvider provider) =>
      _storage.delete(key: AiKeyStore.prefKey(provider));

  @override
  Future<Set<AiProvider>> providersWithKey() async {
    final result = <AiProvider>{};
    for (final provider in AiProvider.values) {
      final key = await read(provider);
      if (key != null && key.isNotEmpty) result.add(provider);
    }
    return result;
  }
}

/// For tests and for when the device keystore does not respond.
class InMemoryAiKeyStore implements AiKeyStore {
  final _keys = <AiProvider, String>{};

  @override
  Future<String?> read(AiProvider provider) async => _keys[provider];

  @override
  Future<void> write(AiProvider provider, String key) async =>
      _keys[provider] = key;

  @override
  Future<void> delete(AiProvider provider) async => _keys.remove(provider);

  @override
  Future<Set<AiProvider>> providersWithKey() async => {
    for (final entry in _keys.entries)
      if (entry.value.isNotEmpty) entry.key,
  };
}
