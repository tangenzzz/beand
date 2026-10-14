// ignore_for_file: prefer_initializing_formals
// (The fields are private, and named parameters in Dart can't start with
// an underscore — so `{required this._feld}` doesn't exist.)
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_key_store.dart';
import 'ai_provider.dart';

// The three features AI is meant to get in bean'd. One switch each,
// because the trust differs: letting a model transcribe a label is easier
// to accept than a pressure curve that goes to the machine.
enum AiFeature {
  beanForm(
    'Fill bean form',
    'Read a bean from a photo of the packaging or from a shop link',
  ),
  shotAnalysis(
    'Analyse shots',
    'Comment on a shot and suggest what to change next. '
        'Espresso shots only, not for pour-over brews',
  ),
  profileDraft(
    'Draft profiles',
    'Turn a description into a profile — always opened in the editor first, '
        'never sent straight to the machine',
  );

  const AiFeature(this.label, this.description);

  final String label;
  final String description;
}

// What is configured in Settings → AI. A separate class next to
// AppSettings, for two reasons: the keys are not in the prefs but in the
// [AiKeyStore], and this part will still grow with models, limits and
// caches.
class AiSettings extends ChangeNotifier {
  AiSettings({
    required AiKeyStore keyStore,
    bool enabled = false,
    AiProvider provider = AiProvider.gemini,
    Map<AiProvider, String> models = const {},
    String baseUrl = '',
    Set<AiFeature> disabledFeatures = const {},
    Set<AiProvider> providersWithKey = const {},
  }) : _keyStore = keyStore,
       _enabled = enabled,
       _provider = provider,
       _models = {...models},
       _baseUrl = baseUrl,
       _disabledFeatures = {...disabledFeatures},
       _providersWithKey = {...providersWithKey};

  static const enabledPrefKey = 'ai_enabled';
  static const providerPrefKey = 'ai_provider';
  static const baseUrlPrefKey = 'ai_base_url';
  static String modelPrefKey(AiProvider p) => 'ai_model_${p.name}';
  static String featurePrefKey(AiFeature f) => 'ai_feature_${f.name}';

  /// Gemini is the default because it has the free tier: someone who just
  /// installed the app can try AI without having entered a credit card
  /// anywhere. Without a key everything stays off anyway — the choice costs
  /// nobody anything.
  static const defaultProvider = AiProvider.gemini;

  static Future<AiSettings> load({AiKeyStore? keyStore}) async {
    final store = keyStore ?? SecureAiKeyStore();
    final prefs = await SharedPreferences.getInstance();
    // The keystore can act up on a fresh device or after a restore; then AI
    // just shows "no key" instead of crashing the app on startup.
    var withKey = <AiProvider>{};
    try {
      withKey = await store.providersWithKey();
    } catch (e) {
      debugPrint('AiSettings: key store not readable ($e)');
    }
    // The main switch starts OFF: a freshly installed app shouldn't want to
    // send anything to an AI provider on its own, and whoever doesn't need
    // it should never have to open the card.
    //
    // The one exception is an update: whoever already entered a key clearly
    // wanted AI — an update doesn't switch it off under them. After that the
    // decision is stored (below), and this branch never applies again.
    final stored = prefs.getBool(enabledPrefKey);
    final enabled = stored ?? withKey.isNotEmpty;
    if (stored == null) await prefs.setBool(enabledPrefKey, enabled);

    return AiSettings(
      keyStore: store,
      enabled: enabled,
      provider:
          AiProvider.values.asNameMap()[prefs.getString(providerPrefKey)] ??
          defaultProvider,
      models: {
        for (final provider in AiProvider.values)
          provider: ?prefs.getString(modelPrefKey(provider)),
      },
      baseUrl: prefs.getString(baseUrlPrefKey) ?? '',
      disabledFeatures: {
        for (final feature in AiFeature.values)
          if (prefs.getBool(featurePrefKey(feature)) == false) feature,
      },
      providersWithKey: withKey,
    );
  }

  /// After taking over from sync: read the synced values fresh from the
  /// prefs (provider, models, base URL, features). Key and main switch
  /// belong to the device and stay as they are.
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    _provider =
        AiProvider.values.asNameMap()[prefs.getString(providerPrefKey)] ??
        defaultProvider;
    _models
      ..clear()
      ..addAll({
        for (final provider in AiProvider.values)
          provider: ?prefs.getString(modelPrefKey(provider)),
      });
    _baseUrl = prefs.getString(baseUrlPrefKey) ?? '';
    _disabledFeatures
      ..clear()
      ..addAll({
        for (final feature in AiFeature.values)
          if (prefs.getBool(featurePrefKey(feature)) == false) feature,
      });
    notifyListeners();
  }

  final AiKeyStore _keyStore;
  bool _enabled;
  AiProvider _provider;
  final Map<AiProvider, String> _models;
  String _baseUrl;
  final Set<AiFeature> _disabledFeatures;
  final Set<AiProvider> _providersWithKey;

  /// The main switch. Off means: the settings page only shows the switch
  /// itself, and nothing AI-related shows up anywhere in the app — without
  /// having to delete your key. It stays stored and applies again as soon
  /// as you switch back.
  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPrefKey, value);
  }

  AiProvider get provider => _provider;

  Future<void> setProvider(AiProvider value) async {
    if (value == _provider) return;
    _provider = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(providerPrefKey, value.name);
  }

  /// The provider's selected model, otherwise its default.
  String modelFor(AiProvider provider) =>
      _models[provider] ?? provider.defaultModel;

  String get model => modelFor(_provider);

  Future<void> setModel(String value) async {
    if (value == _models[_provider]) return;
    _models[_provider] = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(modelPrefKey(_provider), value);
  }

  /// Only for "Custom" — for the others the address is fixed.
  String get baseUrl => _baseUrl;

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(baseUrlPrefKey, trimmed);
  }

  bool hasKey(AiProvider provider) => _providersWithKey.contains(provider);

  Future<String?> readKey(AiProvider provider) => _keyStore.read(provider);

  Future<void> setKey(AiProvider provider, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return removeKey(provider);
    await _keyStore.write(provider, trimmed);
    _providersWithKey.add(provider);
    notifyListeners();
  }

  Future<void> removeKey(AiProvider provider) async {
    await _keyStore.delete(provider);
    _providersWithKey.remove(provider);
    notifyListeners();
  }

  /// The switch itself. Whether the feature really runs is told by
  /// [isEnabled] — without a key a switched-on switch doesn't help.
  bool isFeatureOn(AiFeature feature) => !_disabledFeatures.contains(feature);

  Future<void> setFeatureOn(AiFeature feature, bool value) async {
    if (value == isFeatureOn(feature)) return;
    if (value) {
      _disabledFeatures.remove(feature);
    } else {
      _disabledFeatures.add(feature);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(featurePrefKey(feature), value);
  }

  /// Is the selected provider fully set up? Deliberately NOT dependent on
  /// the main switch: the settings page must be able to check and test even
  /// when nothing is enabled.
  bool get isConfigured =>
      modelFor(_provider).isNotEmpty &&
      (hasKey(_provider) || !_provider.requiresKey) &&
      (!_provider.requiresBaseUrl || _baseUrl.isNotEmpty);

  /// The question the rest of the app asks. Three things must hold: the
  /// main switch, a set-up provider and the switch of this one feature. If
  /// one is missing, no AI button appears in the app — that's the promise.
  bool isEnabled(AiFeature feature) =>
      _enabled && isConfigured && isFeatureOn(feature);

  /// The full connection including the key. Only here is the key fetched
  /// from the keystore — it isn't kept in memory permanently.
  Future<AiConnection> connection() async => AiConnection(
    provider: _provider,
    apiKey: await _keyStore.read(_provider) ?? '',
    model: modelFor(_provider),
    baseUrl: _provider.requiresBaseUrl ? _baseUrl : _provider.defaultBaseUrl,
  );
}
