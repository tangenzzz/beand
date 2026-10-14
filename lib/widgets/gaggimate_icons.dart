import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// The three GaggiMate modes: brew, steam, water. Drawn with Material icons
// for now; the machine's own display icons may only be used with
// permission from GaggiMate.
enum GaggiMateGlyph { brew, steam, water }

const _icons = {
  GaggiMateGlyph.brew: Icons.coffee,
  GaggiMateGlyph.steam: Icons.air,
  GaggiMateGlyph.water: Icons.water_drop,
};

class GaggiMateIcon extends StatelessWidget {
  const GaggiMateIcon(this.glyph, {super.key, this.size = 24, this.color});

  final GaggiMateGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      _icons[glyph],
      size: size,
      color: color ?? IconTheme.of(context).color ?? context.colors.textPrimary,
    );
  }
}
