import 'package:flutter/material.dart';

import '../../../models/brew_recipe.dart';
import '../../../theme/app_theme.dart';

String formatGrams(double g) => g.toStringAsFixed(g % 1 == 0 ? 0 : 1);

String formatRatio(double r) {
  final rounded = (r * 10).round() / 10;
  return rounded.toStringAsFixed(rounded % 1 == 0 ? 0 : 1);
}

/// 95 → "1:35", for remaining time and clock.
String formatClock(double seconds) {
  final s = seconds.round().clamp(0, 99 * 60);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String grindLabel(String grind) =>
    grind.split('-').map((w) => w[0].toUpperCase() + w.substring(1)).join('-');

String brewTemperatureLabel(String t) => switch (t) {
  'cold' => 'Cold',
  'room-temperature' => 'Room temp.',
  _ => 'Cold / room temp.',
};

const _brewerShort = {
  'V60': 'V60',
  'Chemex': 'CX',
  'Aeropress': 'AP',
  'ColdBrew': 'CB',
  'Kalita': 'KW',
  'Orea': 'OR',
  'FrenchPress': 'FP',
  'StaggX': 'SX',
  'Origami': 'OG',
  'April': 'AB',
  'Other': '··',
};

const _brewerNames = {
  'ColdBrew': 'Cold Brew',
  'FrenchPress': 'French Press',
  'StaggX': 'Stagg X',
};

String brewerLabel(String brewer) => _brewerNames[brewer] ?? brewer;

/// "V60 · 20 g · 1:15 · 92°C" — line below the recipe name in the list.
String recipeDetail(BrewRecipe r) {
  final temp = r.waterTempC != null
      ? '${formatGrams(r.waterTempC!)}°C'
      : brewTemperatureLabel(r.brewTemperature ?? '');
  return '${brewerLabel(r.brewer)} · ${formatGrams(r.doseG)} g · '
      '1:${formatRatio(r.ratioValue)} · $temp';
}

/// Round badge with the brewer's abbreviation — recipes have no images.
class BrewerAvatar extends StatelessWidget {
  const BrewerAvatar({super.key, required this.brewer, this.size = 36});

  final String brewer;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.accent.withValues(alpha: 0.16),
      ),
      child: Text(
        _brewerShort[brewer] ?? brewer.substring(0, 2).toUpperCase(),
        style: TextStyle(
          color: context.colors.accent,
          fontSize: size * 0.3,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
