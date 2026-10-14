import 'package:flutter/material.dart';

// The three appearances. "System" is none of them — it is resolved to dark
// or light before building the theme (the system's dark mode deliberately
// yields "Dark", never "Black").
enum AppThemeVariant { dark, light, black }

// What is selectable in the settings.
enum AppThemeMode {
  system('System'),
  dark('Dark'),
  light('Light'),
  black('Black');

  const AppThemeMode(this.label);

  final String label;

  // [platform] is the brightness reported by the operating system.
  AppThemeVariant resolve(Brightness platform) => switch (this) {
    AppThemeMode.system =>
      platform == Brightness.dark
          ? AppThemeVariant.dark
          : AppThemeVariant.light,
    AppThemeMode.dark => AppThemeVariant.dark,
    AppThemeMode.light => AppThemeVariant.light,
    AppThemeMode.black => AppThemeVariant.black,
  };
}

// The selectable accent colors. One value for the dark appearances and one
// for the light one — a light accent would be unreadable on a light
// background.
enum AppAccent {
  teal('Teal', Color(0xFF2CCBB3), Color(0xFF0C7C6C)),
  crema('Crema', Color(0xFFE4C49A), Color(0xFF926531)),
  cascara('Cascara', Color(0xFFE8778E), Color(0xFFB83E57)),
  sage('Sage', Color(0xFF9FC79A), Color(0xFF4B7946)),
  chartreuse('Chartreuse', Color(0xFFCFE870), Color(0xFF5C760E)),
  oat('Oat', Color(0xFFF2EDE4), Color(0xFF2B2825));

  const AppAccent(this.label, this.dark, this.light);

  final String label;
  final Color dark;
  final Color light;

  Color forVariant(AppThemeVariant variant) =>
      variant == AppThemeVariant.light ? light : dark;
}

// All app colors as theme tokens. Widgets access them via
// `context.colors.<token>` and contain no color values themselves — so
// every switch takes effect immediately and everywhere.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.card,
    required this.nav,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.accent,
    required this.sensorUp,
    required this.sensorMid,
    required this.sensorDown,
    required this.sensorGroup,
    required this.danger,
    required this.star,
    required this.success,
    required this.heroRingHeating,
    required this.heroRingReady,
    required this.ice,
    required this.iceLight,
  });

  /// Screen background
  final Color bg;

  /// Surface of a tile/card on the background
  final Color card;

  /// Bars: bottom tab bar and header bar
  final Color nav;

  /// Main text
  final Color textPrimary;

  /// Secondary text, labels, unselected choices
  final Color textSecondary;

  /// Hints, disabled things, fine lines in charts
  final Color textTertiary;

  /// Dividers and borders
  final Color divider;

  /// Accent: ONLY section headers, PRE label, active nav icon, page dots,
  /// text actions, pill dot, button text. No surfaces.
  final Color accent;

  /// Sensor top / temperature curve top
  final Color sensorUp;

  /// Sensor middle / weight curve / status 'connecting'
  final Color sensorMid;

  /// Sensor bottom / flow curve
  final Color sensorDown;

  /// Fourth sensor / group
  final Color sensorGroup;

  /// Target temperature, error, delete
  final Color danger;

  /// Rating stars
  final Color star;

  /// Connected, pressure curve, best freshness window
  final Color success;

  /// Hero ring heating
  final Color heroRingHeating;

  /// Hero ring ready
  final Color heroRingReady;

  /// Frozen bean: ring
  final Color ice;

  /// Frozen bean: light part of the ring
  final Color iceLight;

  factory AppColors.dark(Color accent) => AppColors(
    accent: accent,
    bg: const Color(0xFF1B1B1D),
    card: const Color(0xFF232326),
    nav: const Color(0xFF202022),
    textPrimary: const Color(0xFFECEAE4),
    textSecondary: const Color(0xFF9A9892),
    textTertiary: const Color(0xFF5E5D5A),
    divider: const Color(0xFF3F3F43),
    sensorUp: const Color(0xFFF0914A),
    sensorMid: const Color(0xFFF2C94C),
    sensorDown: const Color(0xFF4AA8F0),
    sensorGroup: const Color(0xFFA98BE8),
    danger: const Color(0xFFE5534B),
    star: const Color(0xFFE9A93A),
    success: const Color(0xFF5AD86B),
    heroRingHeating: const Color(0xFFBA7517),
    heroRingReady: const Color(0xFF1D9E75),
    ice: const Color(0xFF9ADCFF),
    iceLight: const Color(0xFFE8F6FF),
  );

  factory AppColors.light(Color accent) => AppColors(
    accent: accent,
    bg: const Color(0xFFF4F1EB),
    card: const Color(0xFFFFFFFF),
    nav: const Color(0xFFEBE7DF),
    textPrimary: const Color(0xFF1F1D1A),
    textSecondary: const Color(0xFF6F6C66),
    textTertiary: const Color(0xFF918B7F),
    divider: const Color(0xFFDDD8CE),
    sensorUp: const Color(0xFFAB561A),
    sensorMid: const Color(0xFF876A0B),
    sensorDown: const Color(0xFF1E70BD),
    sensorGroup: const Color(0xFF7656C4),
    danger: const Color(0xFFC93A33),
    star: const Color(0xFFB97F18),
    success: const Color(0xFF297D44),
    heroRingHeating: const Color(0xFF9D5F0E),
    heroRingReady: const Color(0xFF15795A),
    ice: const Color(0xFF2573A1),
    iceLight: const Color(0xFF7CC2E8),
  );

  factory AppColors.black(Color accent) => AppColors(
    accent: accent,
    bg: const Color(0xFF000000),
    card: const Color(0xFF121213),
    nav: const Color(0xFF0A0A0A),
    textPrimary: const Color(0xFFEDEBE6),
    textSecondary: const Color(0xFF8E8C86),
    textTertiary: const Color(0xFF4A4946),
    divider: const Color(0xFF2C2C2F),
    sensorUp: const Color(0xFFF0914A),
    sensorMid: const Color(0xFFF2C94C),
    sensorDown: const Color(0xFF4AA8F0),
    sensorGroup: const Color(0xFFA98BE8),
    danger: const Color(0xFFE5534B),
    star: const Color(0xFFE9A93A),
    success: const Color(0xFF5AD86B),
    heroRingHeating: const Color(0xFFBA7517),
    heroRingReady: const Color(0xFF1D9E75),
    ice: const Color(0xFF9ADCFF),
    iceLight: const Color(0xFFE8F6FF),
  );

  factory AppColors.forVariant(AppThemeVariant variant, AppAccent accent) {
    final color = accent.forVariant(variant);
    return switch (variant) {
      AppThemeVariant.dark => AppColors.dark(color),
      AppThemeVariant.light => AppColors.light(color),
      AppThemeVariant.black => AppColors.black(color),
    };
  }

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? bg,
    Color? card,
    Color? nav,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? accent,
    Color? sensorUp,
    Color? sensorMid,
    Color? sensorDown,
    Color? sensorGroup,
    Color? danger,
    Color? star,
    Color? success,
    Color? heroRingHeating,
    Color? heroRingReady,
    Color? ice,
    Color? iceLight,
  }) => AppColors(
    bg: bg ?? this.bg,
    card: card ?? this.card,
    nav: nav ?? this.nav,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    divider: divider ?? this.divider,
    accent: accent ?? this.accent,
    sensorUp: sensorUp ?? this.sensorUp,
    sensorMid: sensorMid ?? this.sensorMid,
    sensorDown: sensorDown ?? this.sensorDown,
    sensorGroup: sensorGroup ?? this.sensorGroup,
    danger: danger ?? this.danger,
    star: star ?? this.star,
    success: success ?? this.success,
    heroRingHeating: heroRingHeating ?? this.heroRingHeating,
    heroRingReady: heroRingReady ?? this.heroRingReady,
    ice: ice ?? this.ice,
    iceLight: iceLight ?? this.iceLight,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      sensorUp: Color.lerp(sensorUp, other.sensorUp, t)!,
      sensorMid: Color.lerp(sensorMid, other.sensorMid, t)!,
      sensorDown: Color.lerp(sensorDown, other.sensorDown, t)!,
      sensorGroup: Color.lerp(sensorGroup, other.sensorGroup, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      star: Color.lerp(star, other.star, t)!,
      success: Color.lerp(success, other.success, t)!,
      heroRingHeating: Color.lerp(heroRingHeating, other.heroRingHeating, t)!,
      heroRingReady: Color.lerp(heroRingReady, other.heroRingReady, t)!,
      ice: Color.lerp(ice, other.ice, t)!,
      iceLight: Color.lerp(iceLight, other.iceLight, t)!,
    );
  }
}

// Shortcut to the tokens: `context.colors.textPrimary`.
extension AppColorsContext on BuildContext {
  AppColors get colors => AppColors.of(this);
}
