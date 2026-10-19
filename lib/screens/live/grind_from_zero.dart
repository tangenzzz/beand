import 'package:flutter/material.dart';

import '../../models/grinder.dart';
import '../../theme/app_theme.dart';
import 'grind_panel.dart';

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

/// Before the chevron of the grind row: "+x from zero" — on a grinder
/// with marks measured on the shared scale (the zero point is read at the
/// first mark).
class GrindTrailing extends StatelessWidget {
  const GrindTrailing({
    super.key,
    required this.grinder,
    required this.dial,
    this.marker,
  });

  final Grinder? grinder;
  final double? dial;
  final String? marker;

  @override
  Widget build(BuildContext context) {
    final scale = grinder?.scale;
    final dial = this.dial;
    final mark = scale != null && scale.hasMarkers
        ? scale.markerNamed(marker)
        : null;
    return GrindFromZero(
      grinder: grinder,
      dial: mark == null || dial == null ? dial : scale!.absolute(dial, mark),
    );
  }
}

/// Right behind the grind value: the dot of the index mark it is set
/// against (only on grinders with several marks), null otherwise.
Widget? grindMarkerSuffix(Grinder? grinder, double? dial, String? marker) {
  final scale = grinder?.scale;
  if (scale == null || !scale.hasMarkers || dial == null) return null;
  final mark = scale.markerNamed(marker);
  if (mark == null) return null;
  return GrindMarkerDot(
    key: const ValueKey('grind-marker-dot'),
    color: mark.color,
  );
}
