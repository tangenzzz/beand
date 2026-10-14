import 'package:flutter/material.dart';

// Compact icon button for the tab headers (search, filter, gear, ...):
// icon 22 px, tap target ~34 instead of 48 px — the same size everywhere as
// the gear in the Home tab.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  // Icon without its own size, so it takes the button's 22 px.
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 22,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      icon: icon,
      onPressed: onPressed,
    );
  }
}
