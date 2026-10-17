import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

// The three GaggiMate modes: brew, steam, water. The same icons as on the
// machine's display: Uicons by Flaticon (https://www.flaticon.com/uicons),
// taken from jniebuhr/gaggimate (eez-ui/icons). See assets/gaggimate/README.md.
enum GaggiMateGlyph { brew, steam, water }

const _assets = {
  GaggiMateGlyph.brew: 'assets/gaggimate/brew.svg',
  GaggiMateGlyph.steam: 'assets/gaggimate/steam.svg',
  GaggiMateGlyph.water: 'assets/gaggimate/water.svg',
};

class GaggiMateIcon extends StatelessWidget {
  const GaggiMateIcon(this.glyph, {super.key, this.size = 24, this.color});

  final GaggiMateGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _assets[glyph]!,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? IconTheme.of(context).color ?? context.colors.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }
}

// The GAGGIMATE wordmark (used with permission of GaggiMate). [height] is
// the letter height; the width follows from the 70:9 aspect ratio.
class GaggiMateWordmark extends StatelessWidget {
  const GaggiMateWordmark({super.key, this.height = 9, this.color});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/gaggimate/wordmark.svg',
      height: height,
      width: height * 70 / 9,
      semanticsLabel: 'GaggiMate',
      colorFilter: ColorFilter.mode(
        color ??
            DefaultTextStyle.of(context).style.color ??
            context.colors.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }
}

// The square cup logo in its own colors (used with permission of GaggiMate).
class GaggiMateCupLogo extends StatelessWidget {
  const GaggiMateCupLogo({super.key, this.size});

  /// Without a size it takes the surrounding icon size (e.g. a settings row).
  final double? size;

  @override
  Widget build(BuildContext context) {
    final side = size ?? IconTheme.of(context).size ?? 24;
    return SvgPicture.asset(
      'assets/gaggimate/cup.svg',
      width: side,
      height: side,
      semanticsLabel: 'GaggiMate',
    );
  }
}
