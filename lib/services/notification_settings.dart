import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The machine notifications that can be switched one by one.
enum MachineAlert {
  preheatDone('Preheat done'),
  reached('Temperature reached'),
  stable('Stable'),
  shotDone('Shot done'),
  connectionLost('Connection lost');

  const MachineAlert(this.label);
  final String label;
}

/// Settings → Notifications: the live status on/off, each alert, and
/// whether alerts come only while the app is closed. The live status is on
/// by default, the alerts are off (user decision 2026-10-21: the mini
/// player is enough for most).
class NotificationSettings extends ChangeNotifier {
  NotificationSettings({
    this.enabled = true,
    Set<MachineAlert>? alerts,
    this.onlyWhenClosed = false,
    this.prefs,
  }) : alerts = alerts ?? {};

  static const _enabledKey = 'notify.enabled';
  static const _onlyClosedKey = 'notify.onlyWhenClosed';
  static String _alertKey(MachineAlert a) => 'notify.${a.name}';

  static Future<NotificationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationSettings(
      enabled: prefs.getBool(_enabledKey) ?? true,
      alerts: {
        for (final a in MachineAlert.values)
          if (prefs.getBool(_alertKey(a)) ?? false) a,
      },
      onlyWhenClosed: prefs.getBool(_onlyClosedKey) ?? false,
      prefs: prefs,
    );
  }

  /// Where the switches are kept; null in tests.
  final SharedPreferences? prefs;

  /// Live status (the mini player); off = no alerts either.
  bool enabled;
  final Set<MachineAlert> alerts;

  /// Alerts only while the app is in the background (the status
  /// notification shows either way).
  bool onlyWhenClosed;

  bool wants(MachineAlert a) => enabled && alerts.contains(a);

  void setEnabled(bool value) {
    if (value == enabled) return;
    enabled = value;
    prefs?.setBool(_enabledKey, value);
    notifyListeners();
  }

  void setAlert(MachineAlert a, bool on) {
    if (on == alerts.contains(a)) return;
    on ? alerts.add(a) : alerts.remove(a);
    prefs?.setBool(_alertKey(a), on);
    notifyListeners();
  }

  void setOnlyWhenClosed(bool value) {
    if (value == onlyWhenClosed) return;
    onlyWhenClosed = value;
    prefs?.setBool(_onlyClosedKey, value);
    notifyListeners();
  }
}
