import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// Header of a section in the shot detail (AI ANALYSIS) with an arrow to
// expand and collapse. The whole row is the tap target, like the stage
// details; own buttons in [trailing] catch their taps themselves. If the
// section is turned off in Settings, it doesn't appear at all, arrow
// included.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    this.trailing = const [],
  });

  final String label;
  final bool expanded;
  final VoidCallback onToggle;

  /// Right-aligned in the same row (e.g. model, date, button).
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      key: ValueKey('toggle-$label'),
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: colors.textTertiary,
            ),
            const Spacer(),
            ...trailing,
          ],
        ),
      ),
    );
  }
}
