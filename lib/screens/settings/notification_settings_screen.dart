import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_settings.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

// Settings → Notifications: one card — the master switch, then the
// Meticulous's alerts, then "only when the app is closed".
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<NotificationSettings>();
    final on = settings.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    title: 'Notifications',
                    info:
                        'From preheat until the shot is done, bean\'d shows '
                        'the machine in a notification: temperature, time '
                        'left, the shot. That keeps the connection alive '
                        'while the app is closed. It goes away when the '
                        'shot is done.',
                    value: on,
                    onChanged: settings.setEnabled,
                  ),
                ],
              ),
              SettingsGroup(
                label: 'Meticulous',
                children: [
                  for (final alert in MachineAlert.values)
                    SettingsSwitchRow(
                      title: alert.label,
                      value: settings.alerts.contains(alert),
                      onChanged: on ? (v) => settings.setAlert(alert, v) : null,
                    ),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    title: 'Only when the app is closed',
                    info:
                        'Off: the alerts come even while bean\'d is open, '
                        'e.g. with the phone next to the machine.',
                    value: settings.onlyWhenClosed,
                    onChanged: on ? settings.setOnlyWhenClosed : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
