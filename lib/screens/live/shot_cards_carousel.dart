import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/live_shot_service.dart';
import '../../theme/app_theme.dart';
import 'post_shot_card.dart';
import 'pre_shot_card.dart';
import 'shot_live_card.dart';

// Swipeable row of cards (PageView + dot indicator), 3 pages: Pre Shot,
// Shot, Post Shot. Jumps ahead automatically as soon as the machine's shot
// stage changes (LiveShotService.pageJumps) — regardless of whether
// start/purge was triggered via this app, directly on the machine or from
// another app.
class ShotCardsCarousel extends StatefulWidget {
  const ShotCardsCarousel({
    super.key,
    this.preCard,
    this.liveCard,
    this.extraCardHeight = 0,
  });

  // Pour Over swaps Pre and Live for its own cards; the Post card stays the
  // same for everyone. The Pre card gets the height callback (expanded
  // lists).
  final Widget Function(ValueChanged<double> onExtraHeight)? preCard;
  final Widget? liveCard;
  // More height for all three cards of this home screen. Only Pour Over
  // uses it: its Pre Brew card has more rows in Profile mode and should not
  // scroll internally. The machines stay at [cardHeight].
  final double extraCardHeight;

  // Height all three cards get (the shot card's height test relies on
  // this).
  static const cardHeight = 373.0;

  @override
  State<ShotCardsCarousel> createState() => _ShotCardsCarouselState();
}

class _ShotCardsCarouselState extends State<ShotCardsCarousel> {
  // <1 lets neighboring cards peek in from the screen edge left/right
  // ("peek"), like ProfileCarousel — instead of borderless full width.
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;
  // Extra height for the expanded list of the pre-shot card.
  double _extraHeight = 0;
  late final StreamSubscription<int> _pageJumpSub;

  void _setExtraHeight(double value) {
    if (!mounted || value == _extraHeight) return;
    setState(() => _extraHeight = value);
  }

  @override
  void initState() {
    super.initState();
    _pageJumpSub = context.read<LiveShotService>().pageJumps.listen((page) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _pageJumpSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      widget.preCard?.call(_setExtraHeight) ??
          PreShotCard(onExtraHeight: _setExtraHeight),
      widget.liveCard ?? const ShotLiveCard(),
      const PostShotCard(),
    ];
    return Column(
      children: [
        SizedBox(
          // Was 320, then 334 (four rows + Auto Start + button in the
          // pre-shot card), then 412 for the rating flower. That was too
          // much: it now sits exactly halfway between the two.
          height:
              ShotCardsCarousel.cardHeight +
              widget.extraCardHeight +
              _extraHeight,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            // Clear gap between the cards instead of them touching.
            children: [
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: card,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) => _Dot(active: i == _page)),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? context.colors.accent : context.colors.textTertiary,
      ),
    );
  }
}
