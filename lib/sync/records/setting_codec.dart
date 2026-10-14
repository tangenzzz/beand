import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai/ai_provider.dart';
import '../../services/ai/ai_settings.dart';
import '../../services/app_settings.dart';

// Which settings travel between devices (whitelist). Everything not listed
// here stays on the device — above all machine addresses, the currently
// selected view/bean/dose, AI keys and the AI main switch (without a key on
// the other device, "on" there would just mean "No key").

const settingType = 'setting';

List<String> syncedSettingKeys() => [
  AppSettings.showFreshnessRingPrefKey,
  AppSettings.showBeanStockPrefKey,
  AppSettings.showStageDetailsPrefKey,
  AppSettings.showShotFactsPrefKey,
  AppSettings.expandAiAnalysisPrefKey,
  AppSettings.homeModeOrderPrefKey,
  for (final mode in HomeMode.values) AppSettings.homeModeEnabledPrefKey(mode),
  AppSettings.beanFormOrderPrefKey,
  AppSettings.beanFormHiddenPrefKey,
  AppSettings.historyAvatarPrefKey,
  AppSettings.themeModePrefKey,
  AppSettings.accentPrefKey,
  AiSettings.providerPrefKey,
  AiSettings.baseUrlPrefKey,
  for (final p in AiProvider.values) AiSettings.modelPrefKey(p),
  for (final f in AiFeature.values) AiSettings.featurePrefKey(f),
];

/// Where the settings live — in the app shared_preferences
/// ([SharedPreferencesSettingsStore]), in tests a map per device.
abstract class SettingsStore {
  /// bool, int, double, String, `List<String>` or null.
  Object? get(String key);
  Future<void> set(String key, Object value);
  Future<void> remove(String key);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this.prefs);
  final SharedPreferences prefs;

  @override
  Object? get(String key) => prefs.get(key);

  @override
  Future<void> remove(String key) => prefs.remove(key);

  @override
  Future<void> set(String key, Object value) => switch (value) {
    bool v => prefs.setBool(key, v),
    int v => prefs.setInt(key, v),
    double v => prefs.setDouble(key, v),
    String v => prefs.setString(key, v),
    List<String> v => prefs.setStringList(key, v),
    _ => throw ArgumentError('Unsupported setting value for $key'),
  };
}

/// Current value as JSON; null = not set.
String? readSettingJson(SettingsStore store, String key) {
  final value = store.get(key);
  return value == null ? null : jsonEncode(value);
}

/// Write a value from sync (null = remove). Throws [FormatException] for a
/// type the prefs don't know.
Future<void> writeSettingJson(
  SettingsStore store,
  String key,
  String? json,
) async {
  if (json == null) {
    await store.remove(key);
    return;
  }
  final value = jsonDecode(json);
  switch (value) {
    case bool() || int() || double() || String():
      await store.set(key, value as Object);
    case List v when v.every((e) => e is String):
      await store.set(key, v.cast<String>().toList());
    default:
      throw FormatException('Setting $key has an unsupported value');
  }
}
