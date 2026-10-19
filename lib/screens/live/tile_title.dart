import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../services/live_shot_service.dart';
import '../../theme/app_theme.dart';

// Card title "PREShot" / "LIVEShot" / "POSTShot": the prefix is smaller
// than "Shot", sits to the left of it and higher. The top edges of both
// texts are aligned and the prefix is raised slightly above that —
// deliberately so instead of using a shared baseline, because then the
// result does not depend on the metrics of the font. The offset is a
// transform, so it does not change the line height.
//
// [active] colors the prefix in the accent color: it always marks the card
// that is currently "up" (PRE until the shot starts, LIVE until the purge,
// POST until the save button is pressed — see LiveShotService.activeCard).
class TileTitle extends StatelessWidget {
  const TileTitle({
    super.key,
    required this.short,
    required this.active,
    this.noun,
  });

  // "PRE", "LIVE" or "POST".
  final String short;
  final bool active;

  // "Shot" for the machines, "Brew" for Pour Over. If not given it follows
  // the Home screen's service — so the shared Post card there is also
  // called "POSTBrew" without knowing about it.
  final String? noun;

  @override
  Widget build(BuildContext context) => PrefixedTitle(
    prefix: short,
    title:
        noun ??
        (context.read<LiveShotService?>()?.machineKey == 'pourover'
            ? 'Brew'
            : 'Shot'),
    active: active,
  );
}

/// The look of the card titles ("PREShot") for any small prefix and title,
/// e.g. a piece's brand and model on My Coffee Desk ("NICHEZero").
class PrefixedTitle extends StatelessWidget {
  const PrefixedTitle({
    super.key,
    required this.prefix,
    required this.title,
    this.active = false,
    this.maxLines,
  });

  /// Shown in capitals; null or empty = the title alone.
  final String? prefix;
  final String title;

  /// Prefix in the accent color instead of gray.
  final bool active;
  final int? maxLines;

  static const _raise = 2.0;

  @override
  Widget build(BuildContext context) {
    final prefix = this.prefix?.trim() ?? '';
    final titleText = Text(
      title,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    );
    if (prefix.isEmpty) return titleText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -_raise),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              color: active
                  ? context.colors.accent
                  : context.colors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            child: Text(prefix.toUpperCase()),
          ),
        ),
        const SizedBox(width: 1),
        Flexible(child: titleText),
      ],
    );
  }
}
