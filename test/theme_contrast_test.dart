import 'dart:math' as math;

import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Contrast per WCAG: (lighter + 0.05) / (darker + 0.05), both as relative
// luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // The light theme is the tight case: everything sits on a light
  // background. Measured against the page background (darker than the
  // card) because it's the harder of the two.
  group('Light appearance: contrasts', () {
    final colors = AppColors.forVariant(AppThemeVariant.light, AppAccent.teal);

    // Everything that carries numbers or labels.
    final textCarrying = {
      'textPrimary': colors.textPrimary,
      'textSecondary': colors.textSecondary,
      'sensorUp': colors.sensorUp,
      'sensorMid': colors.sensorMid,
      'sensorDown': colors.sensorDown,
      'sensorGroup': colors.sensorGroup,
      'danger': colors.danger,
      'success': colors.success,
      'heroRingHeating': colors.heroRingHeating,
      'heroRingReady': colors.heroRingReady,
      'ice': colors.ice,
    };

    for (final entry in textCarrying.entries) {
      test('${entry.key} reaches 4.5:1 on background and card', () {
        expect(
          contrast(entry.value, colors.bg),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} on the page background',
        );
        expect(contrast(entry.value, colors.card), greaterThanOrEqualTo(4.5));
      });
    }

    // Icons and subtle hints: 3:1 (threshold for non-text).
    test('star and textTertiary reach 3:1', () {
      expect(contrast(colors.star, colors.bg), greaterThanOrEqualTo(3));
      expect(contrast(colors.textTertiary, colors.bg), greaterThanOrEqualTo(3));
    });

    test('textTertiary stays clearly quieter than textSecondary', () {
      expect(
        contrast(colors.textTertiary, colors.bg),
        lessThan(contrast(colors.textSecondary, colors.bg)),
      );
    });

    for (final accent in AppAccent.values) {
      test('accent ${accent.label} reaches 4.5:1 in the light theme', () {
        final c = AppColors.forVariant(AppThemeVariant.light, accent);
        expect(
          contrast(c.accent, c.bg),
          greaterThanOrEqualTo(4.5),
          reason: '${accent.label} on the page background',
        );
        expect(contrast(c.accent, c.card), greaterThanOrEqualTo(4.5));
      });
    }
  });

  // The dark themes were never the problem — the test pins them down.
  for (final variant in [AppThemeVariant.dark, AppThemeVariant.black]) {
    test('${variant.name}: text and accents stay above 4.5:1', () {
      for (final accent in AppAccent.values) {
        final c = AppColors.forVariant(variant, accent);
        expect(contrast(c.textPrimary, c.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(c.textSecondary, c.bg), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.accent, c.card),
          greaterThanOrEqualTo(4.5),
          reason: '${accent.label} in ${variant.name}',
        );
      }
    });
  }
}
