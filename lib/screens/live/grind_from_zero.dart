import 'package:flutter/material.dart';

import '../../models/grinder.dart';
import '../../theme/app_theme.dart';

/// Small at the right of a grind value: how far above the burrs' touch
/// point the dial stands ("+12.8 from zero") — only when the grinder has a
/// zero point other than 0. Someone who re-indexes the dial sees nothing.
class GrindFromZero extends StatelessWidget {
  const GrindFromZero({super.key, required this.grinder, required this.dial});

  final Grinder? grinder;
  final double? dial;

  @override
  Widget build(BuildContext context) {
    final g = grinder;
    final zero = g?.zeroPoint?.value;
    final dial = this.dial;
    if (g == null || zero == null || zero == 0 || dial == null) {
      return const SizedBox.shrink();
    }
    final effective = g.effective(dial);
    final text = g.scaleOrStandard.format(effective, withUnit: false);
    return Text(
      '${effective >= 0 ? '+' : ''}$text from zero',
      key: const ValueKey('grind-from-zero'),
      style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
    );
  }
}
