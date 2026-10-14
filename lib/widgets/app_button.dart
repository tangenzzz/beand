import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppButtonVariant {
  /// The single main action of a card or page ("Start Profile").
  /// No fill, only a fine border; the text carries the accent color.
  primary,

  /// Secondary action without border ("Cancel").
  secondary,

  /// Delete and the like — text and icon in the warning color.
  destructive,
}

// All buttons of the app. There are no filled surfaces anymore: only what
// you can touch gets a surface, color is carried by the text alone.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.expand,
    this.height = 48,
  });

  final String label;

  /// null disables the button (dimmed, not tappable).
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;

  /// Full width. If unspecified: only the primary button takes it.
  final bool? expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    final foreground = switch (variant) {
      AppButtonVariant.primary => colors.accent,
      AppButtonVariant.secondary => colors.textSecondary,
      AppButtonVariant.destructive => colors.danger,
    };
    final wide = expand ?? (variant == AppButtonVariant.primary);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        width: wide ? double.infinity : null,
        height: height,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
            side: variant == AppButtonVariant.primary
                ? BorderSide(color: colors.divider)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            // Pressed: only a hint of the text color, no accent fill.
            overlayColor: WidgetStateProperty.all(
              colors.textPrimary.withValues(alpha: 0.08),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: foreground, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
