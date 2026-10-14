import 'package:flutter/material.dart';

import 'app_colors.dart';

export 'app_colors.dart';

class AppRadii {
  AppRadii._();
  static const tile = 18.0;
  // Primary button and pills: fully rounded.
  static const button = 24.0;
}

class AppSpacing {
  AppSpacing._();
  static const tileOuterMargin = 6.0;
  static const tileGap = 4.0;
  static const dividerInset = 16.0;
  // Space below the action button at the foot of the three shot cards — in
  // addition to the card's padding (14), so 20 px to the edge in total.
  // All three cards share this value.
  static const tileActionBottom = 6.0;
  // Smallest area a finger reliably hits.
  static const minTapTarget = 44.0;
}

// Builds the theme for an appearance. [variant] is already resolved —
// "System" no longer exists here (see AppThemeMode.resolve).
ThemeData buildAppTheme({
  AppThemeVariant variant = AppThemeVariant.dark,
  AppAccent accent = AppAccent.teal,
}) {
  final colors = AppColors.forVariant(variant, accent);
  final isLight = variant == AppThemeVariant.light;
  final brightness = isLight ? Brightness.light : Brightness.dark;

  // Text colors come from the tokens, not from Material's default —
  // otherwise the light theme would still have white text.
  final text =
      (isLight ? Typography.blackMountainView : Typography.whiteMountainView)
          .apply(
            bodyColor: colors.textPrimary,
            displayColor: colors.textPrimary,
          );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    canvasColor: colors.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.bg,
      secondary: colors.accent,
      onSecondary: colors.bg,
      error: colors.danger,
      onError: colors.bg,
      surface: colors.bg,
      onSurface: colors.textPrimary,
      surfaceContainer: colors.card,
      outline: colors.divider,
    ),
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: colors.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bg,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      // Otherwise Material 3 tints the app bar on scroll.
      scrolledUnderElevation: 0,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: colors.nav,
      selectedItemColor: colors.accent,
      unselectedItemColor: colors.textSecondary,
    ),
    // Text buttons without their own style are secondary actions (Cancel,
    // Reset): no border, secondary text color. A primary text action
    // ("Save") sets the accent itself.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
    ),
    dialogTheme: DialogThemeData(backgroundColor: colors.card),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.card),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.card,
      contentTextStyle: TextStyle(color: colors.textPrimary),
    ),
    dividerColor: colors.divider,
    dividerTheme: DividerThemeData(color: colors.divider, thickness: 1),
    splashFactory: InkSparkle.splashFactory,
    extensions: [colors],
  );
}
