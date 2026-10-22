import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_settings.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

// Settings → Notifications: one card — the live status (the mini player in
// the notifications), then the alerts that ring once, off by default.
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
              // What runs along: the live notification (mini player).
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    title: 'Live status',
                    // iOS stops the app soon after it is left
                    // (services/machine_notifications.dart).
                    info: Platform.isIOS
                        ? 'iOS pauses bean\'d soon after you leave it. '
                              'Leave it while heating and "Preheat done" or '
                              '"Should be ready" comes at the expected time.'
                        : 'Shows heating and brewing in your notifications, '
                              'even with the app closed.',
                    value: on,
                    onChanged: settings.setEnabled,
                  ),
                ],
              ),
              // Extras that ring once.
              SettingsGroup(
                label: 'Alerts',
                info:
                    'An extra notification with sound when something '
                    'happens.',
                children: [
                  for (final alert in MachineAlert.values)
                    SettingsSwitchRow(
                      title: alert.label,
                      value: settings.alerts.contains(alert),
                      onChanged: on ? (v) => settings.setAlert(alert, v) : null,
                    ),
                  SettingsSwitchRow(
                    title: 'Only when the app is closed',
                    value: settings.onlyWhenClosed,
                    onChanged: on && settings.alerts.isNotEmpty
                        ? settings.setOnlyWhenClosed
                        : null,
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
