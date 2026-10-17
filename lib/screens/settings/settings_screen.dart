import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';
import '../../theme/bean_icon.dart';
import '../root_scaffold.dart';
import 'about_settings_screen.dart';
import 'ai_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'backup_settings_screen.dart';
import 'beans_settings_screen.dart';
import 'connections_screen.dart';
import 'history_settings_screen.dart';
import 'home_settings_screen.dart';
import 'my_setup_screen.dart';
import 'settings_widgets.dart';
import 'sync_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // First page in its own settings navigator, so there is no automatic
        // back arrow.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final root = RootNavigation.maybeOf(context);
            if (root != null) {
              root.closeSettings();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsList(
            entries: [
              SettingsEntry(
                icon: Icons.cable,
                title: 'Connections',
                builder: (_) => const ConnectionsScreen(),
              ),
              SettingsEntry(
                // Home and Beans as in the tab bar.
                icon: Icons.coffee,
                title: 'Home',
                builder: (_) => const HomeSettingsScreen(),
              ),

              SettingsEntry(
                icon: Icons.blender_outlined,
                title: 'My Setup',
                builder: (_) => const MySetupScreen(),
              ),
              SettingsEntry(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                builder: (_) => const AppearanceSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.history,
                title: 'History',
                builder: (_) => const HistorySettingsScreen(),
              ),
              SettingsEntry(
                iconWidget: const BeanIcon(size: 20),
                title: 'Beans',
                builder: (_) => const BeansSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.auto_awesome_outlined,
                title: 'AI',
                builder: (_) => const AiSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.sync,
                title: 'Sync',
                builder: (_) => const SyncSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.backup_outlined,
                title: 'Backup',
                builder: (_) => const BackupSettingsScreen(),
              ),
              SettingsEntry(
                icon: Icons.info_outline,
                title: 'About',
                builder: (_) => const AboutSettingsScreen(),
              ),
            ],
          ),
          const _VersionLine(),
        ],
      ),
    );
  }
}

// Version line at the very bottom, subtle. The number comes from the package
// itself (`PackageInfo`), not from a string in the code: otherwise the
// display drifts from `pubspec.yaml`. Shows "bean'd 0.9.0 (1)" — version
// name plus build number, which increments with every shipped APK and is
// what matters when reporting bugs.
class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Center(
            child: Text(
              // Until the query returns, the line stays empty instead of
              // flickering — it sits below the last card anyway.
              info == null
                  ? ''
                  : "bean'd ${info.version} (${info.buildNumber})",
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}
