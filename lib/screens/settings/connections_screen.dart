import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'connection_log_screen.dart';
import 'gaggimate_settings_screen.dart';
import 'meticulous_settings_screen.dart';
import 'scale_settings_screen.dart';
import 'settings_widgets.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsList(
            entries: [
              SettingsEntry(
                icon: Icons.coffee_maker_outlined,
                title: 'Meticulous',
                builder: (_) => const MeticulousSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.memory,
                title: 'GaggiMate',
                builder: (_) => const GaggiMateSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.bluetooth,
                title: 'Bluetooth Scale',
                builder: (_) => const ScaleSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.receipt_long_outlined,
                title: 'Connection log',
                builder: (_) => const ConnectionLogScreen(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
