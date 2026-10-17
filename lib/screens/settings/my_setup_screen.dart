import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/grinder_store.dart';
import '../../theme/app_theme.dart';
import 'grinders_screen.dart';
import 'settings_widgets.dart';

// Settings → My Setup: the user's own equipment. Grinders for now.
class MySetupScreen extends StatelessWidget {
  const MySetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<GrinderStore>().grinders.length;
    return Scaffold(
      appBar: AppBar(title: const Text('My Setup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.blender_outlined,
                title: 'Grinders',
                subtitle: count == 0 ? null : '$count',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GrindersScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
