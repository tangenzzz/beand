import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../scale/brew_scale.dart';
import '../../../services/live_shot_service.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../services/shot_setup.dart';
import '../shot_cards_carousel.dart';
import 'live_brew_card.dart';
import 'pourover_command_row.dart';
import 'pourover_hero.dart';
import 'pourover_profile_row.dart';
import 'pre_brew_card.dart';

// Pour Over home view ("Pour Over" pill). Layout like the machines: hero,
// then the card carousel — Pre and Live have their own cards, Post is the
// shared one. The scale connects as soon as the view opens and stays
// connected when switching to a machine.
class PourOverHome extends StatelessWidget {
  const PourOverHome({super.key});

  @override
  Widget build(BuildContext context) {
    final brew = context.read<PourOverBrewService>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LiveShotService>.value(value: brew),
        ChangeNotifierProvider<ShotSetup>.value(value: brew.setup),
      ],
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  // Measured via screenshot on the device (the test font is wider and would
  // have needed 82/19): Profile mode needs one more line of space, Manual
  // fits into the standard height.
  static const _profileExtra = 44.0;
  static const _manualExtra = 0.0;

  late final BrewScale _scale;

  @override
  void initState() {
    super.initState();
    _scale = context.read<BrewScale>();
    // After the first frame: connect() reports a new state immediately, and
    // providers must not rebuild in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _scale.connection == ScaleConnection.disconnected &&
          _scale.error == null) {
        _scale.connect();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PourOverHero(),
        const PourOverCommandRow(),
        const SizedBox(height: 12),
        ShotCardsCarousel(
          // Pre Brew has six rows (Profile mode) or five (Manual) — tall
          // enough that nothing in the card scrolls.
          extraCardHeight:
              context.select<PourOverBrewService, bool>((b) => b.manual)
              ? _manualExtra
              : _profileExtra,
          preCard: (onExtraHeight) => PreBrewCard(onExtraHeight: onExtraHeight),
          liveCard: const LiveBrewCard(),
        ),
        const SizedBox(height: 16),
        const PourOverProfileRow(),
      ],
    );
  }
}
