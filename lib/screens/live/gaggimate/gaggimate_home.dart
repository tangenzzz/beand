import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../machines/gaggimate/gaggimate_service.dart';
import '../../../theme/app_theme.dart';
import '../profile_carousel.dart';
import '../shot_cards_carousel.dart';
import 'gaggimate_command_row.dart';
import 'gaggimate_hero.dart';
import '../../../widgets/app_button.dart';

// Home view of the GaggiMate ("GaggiMate" pill in the Home tab header).
// Same layout as the Meticulous home: hero area, command row, shot
// carousel, profiles. The shot AND profile carousels are deliberately the
// same widgets — fed by GaggiMateLiveShotService and the GaggiMate profile
// store respectively (see _GaggiMateHomeScope in live_tab.dart).
class GaggiMateHome extends StatefulWidget {
  const GaggiMateHome({super.key});

  @override
  State<GaggiMateHome> createState() => _GaggiMateHomeState();
}

class _GaggiMateHomeState extends State<GaggiMateHome> {
  bool _confirmDialogOpen = false;

  // The machine blocked the start because of an error warning and is
  // waiting for an answer. The dismissal is broadcast to all clients — if
  // someone declines on the display, this dialog must close too, so it
  // hangs off the service's state instead of its own flag.
  void _syncConfirmDialog(GaggiMateService service) {
    final pending = service.pendingBrewConfirmation;
    if (pending != null && !_confirmDialogOpen) {
      _confirmDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: context.colors.card,
            title: Text(
              'Start anyway?',
              style: TextStyle(color: context.colors.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The machine blocked the start:',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (final warning in pending)
                  Text(
                    '• ${warning.label}',
                    style: TextStyle(color: context.colors.textPrimary),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  service.cancelBrew();
                },
                child: const Text('Cancel'),
              ),
              AppButton(
                label: 'Start anyway',
                expand: false,
                height: 40,
                onPressed: () {
                  Navigator.of(context).pop();
                  service.confirmBrew();
                },
              ),
            ],
          ),
        );
        _confirmDialogOpen = false;
      });
    } else if (pending == null && _confirmDialogOpen) {
      // Dismissed elsewhere (display or a second device).
      _confirmDialogOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GaggiMateService>();
    _syncConfirmDialog(service);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GaggiMateHero(service: service),
        GaggiMateCommandRow(service: service),
        const SizedBox(height: 12),
        const ShotCardsCarousel(),
        const SizedBox(height: 16),
        // Same profile row as in the Meticulous home: which profiles are
        // meant is decided by this home screen's ProfileStore.
        const ProfileCarousel(),
      ],
    );
  }
}
