import 'package:flutter/material.dart';

import '../root_scaffold.dart';

import 'package:provider/provider.dart';

import '../../machines/espresso_machine.dart';
import '../../machines/gaggimate/gaggimate_live_shot_service.dart';
import '../../machines/gaggimate/gaggimate_profile_sync_service.dart';
import '../../machines/gaggimate/gaggimate_service.dart';
import '../../services/app_settings.dart';
import '../../services/live_shot_service.dart';
import '../../services/meticulous_socket_service.dart';
import '../../services/profile_store.dart';
import '../../services/profile_sync_service.dart';
import '../../services/shot_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/header_icon_button.dart';
import 'command_buttons_row.dart';
import 'gaggimate/gaggimate_home.dart';
import 'home_mode_bar.dart';
import 'pourover/pourover_home.dart';
import 'profile_carousel.dart';
import 'shot_cards_carousel.dart';
import 'temperature_tile.dart';

class LiveTab extends StatelessWidget {
  const LiveTab({super.key});

  @override
  Widget build(BuildContext context) {
    final activeMode = context.select<AppSettings, HomeMode>(
      (s) => s.activeHomeMode,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The settings gear sits inline here instead of in a fixed
            // AppBar overlay — it scrolls with the content. The mode pills
            // are to its left.
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: HomeModeBar(),
                    ),
                  ),
                ),
                // Compact (HeaderIconButton): icon 22 px, tap area ~34
                // instead of 48.
                HeaderIconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: context.colors.textSecondary,
                  ),
                  onPressed: () {
                    RootNavigation.maybeOf(context)?.openSettings();
                  },
                ),
              ],
            ),
            // maintainState: dose/grind size/bean/profile of the pre-shot
            // card and carousel positions are kept when switching views.
            Visibility(
              visible: activeMode == HomeMode.meticulous,
              maintainState: true,
              child: const _MeticulousHome(),
            ),
            if (activeMode == HomeMode.pourOver) const PourOverHome(),
            if (activeMode == HomeMode.gaggimate) const _GaggiMateHomeScope(),
          ],
        ),
      ),
    );
  }
}

// Each home screen provides its machine and its shot state under the shared
// types — so the same pre/live/post cards run in both views without
// knowing which machine is behind them.
class _MeticulousHome extends StatelessWidget {
  const _MeticulousHome();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EspressoMachine>.value(
          value: context.read<MeticulousSocketService>(),
        ),
        Provider<ProfileStore>.value(value: context.read<ProfileSyncService>()),
        ChangeNotifierProvider<ShotSetup>.value(
          value: context.read<ShotSetups>().meticulous,
        ),
      ],
      child: const _MeticulousBody(),
    );
  }
}

class _GaggiMateHomeScope extends StatelessWidget {
  const _GaggiMateHomeScope();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EspressoMachine>.value(
          value: context.read<GaggiMateService>(),
        ),
        ChangeNotifierProvider<LiveShotService>.value(
          value: context.read<GaggiMateLiveShotService>(),
        ),
        Provider<ProfileStore>.value(
          value: context.read<GaggiMateProfileSyncService>(),
        ),
        // Separate setup store: profile, bean, dose and grind size belong
        // to the machine.
        ChangeNotifierProvider<ShotSetup>.value(
          value: context.read<ShotSetups>().gaggimate,
        ),
      ],
      child: const GaggiMateHome(),
    );
  }
}

class _MeticulousBody extends StatelessWidget {
  const _MeticulousBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TemperatureTile(),
        CommandButtonsRow(),
        SizedBox(height: 12),
        // No horizontal padding here — ShotCardsCarousel handles card
        // width/gaps/edge peek itself (see there), just like
        // ProfileCarousel (cards should scroll in directly from the screen
        // edge).
        ShotCardsCarousel(),
        SizedBox(height: 16),
        ProfileCarousel(),
        // Profile editor card comes later.
      ],
    );
  }
}
