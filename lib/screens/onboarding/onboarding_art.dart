import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/bean_icon.dart';

// The pictures of the introduction, one per page. Line drawings in the text
// color, so they work in every appearance.

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Background of the picture area; the cup is filled with it.
Color onboardingArtBackground(AppColors colors) =>
    Color.lerp(colors.card, colors.textPrimary, 0.05)!;

class MachineArt extends StatelessWidget {
  const MachineArt({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: 190,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: 300 / 360,
            strokeWidth: 9,
            strokeCap: StrokeCap.butt,
            color: colors.heroRingReady,
            backgroundColor: colors.textPrimary.withValues(alpha: 0.1),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '92.8°',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Ready',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// One large bean with smaller ones around it. Positions on a 390 x 500 area.
class BeansArt extends StatelessWidget {
  const BeansArt({super.key});

  static const _around = <(double, double, double, double, double)>[
    (-6, 70, 96, -28, .16),
    (290, 64, 112, 24, .14),
    (48, 196, 54, 40, .28),
    (306, 214, 62, -36, .26),
    (14, 318, 72, 14, .16),
    (300, 330, 84, -18, .13),
    (130, 62, 40, 60, .22),
    (232, 118, 30, -50, .34),
    (112, 356, 34, -64, .2),
    (248, 372, 44, 34, .18),
    (92, 132, 24, 18, .34),
    (356, 176, 26, 70, .24),
  ];

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textPrimary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final x = constraints.maxWidth / 390;
        final y = constraints.maxHeight / 500;
        final scale = x < y ? x : y;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final (left, top, size, degrees, opacity) in _around)
              Positioned(
                left: left * x,
                top: top * y,
                child: Transform.rotate(
                  angle: degrees * 3.14159265 / 180,
                  child: BeanIcon(
                    size: size * scale,
                    color: color.withValues(alpha: opacity),
                  ),
                ),
              ),
            Center(
              child: BeanIcon(size: 216 * scale, color: color),
            ),
          ],
        );
      },
    );
  }
}

class DeskArt extends StatelessWidget {
  const DeskArt({super.key});

  @override
  Widget build(BuildContext context) {
    final stroke = _hex(context.colors.textPrimary);
    return SvgPicture.string('''
<svg viewBox="0 0 280 200" fill="none" stroke="$stroke" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
<path d="M12 172H268"/>
<path d="M38 38H70L64 66H44Z"/><path d="M34 38H74"/>
<rect x="34" y="66" width="40" height="56" rx="7"/><circle cx="54" cy="92" r="11"/><path d="M54 84V92L60 96"/>
<path d="M46 122V130H62V122"/>
<path d="M44 138H64L62 158H46Z"/>
<rect x="30" y="158" width="48" height="14" rx="4"/>
<path d="M100 76H154L138 112H116Z"/><path d="M112 86L120 104M142 86L134 104"/>
<rect x="108" y="112" width="38" height="6" rx="3"/>
<path d="M116 118H138L146 150A5 5 0 0 1 141 156H113A5 5 0 0 1 108 150Z"/><path d="M112 138H142"/>
<rect x="96" y="158" width="62" height="14" rx="3"/><path d="M122 165H132"/>
<path d="M210 110H246L252 166A6 6 0 0 1 246 172H210A6 6 0 0 1 204 166Z"/>
<path d="M214 110Q228 96 242 110"/><circle cx="228" cy="97" r="3"/>
<path d="M248 122Q268 124 264 146Q262 158 251 160"/>
<path d="M206 152C186 152 192 112 172 100L164 96"/>
</svg>''', width: 330);
  }
}

class ChainArt extends StatelessWidget {
  const ChainArt({super.key});

  static const _grinder =
      '<path d="M8 10h8l-1 10H9z"/><path d="M7 10l1-6h8l1 6"/>';
  static const _brewer = '<path d="M4 6h16l-5 11H9z"/><path d="M8 20h8"/>';
  static const _scale =
      '<rect x="3" y="14" width="18" height="6" rx="1.5"/><path d="M8 10h8"/>';

  Widget _node(BuildContext context, String label, String icon) {
    final colors = context.colors;
    final stroke = _hex(colors.textPrimary);
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.card,
              shape: BoxShape.circle,
              border: Border.all(color: colors.accent, width: 2),
            ),
            child: SvgPicture.string(
              '<svg viewBox="0 0 24 24" fill="none" stroke="$stroke" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">$icon</svg>',
              width: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: const EdgeInsets.only(top: 33),
      child: Container(width: 22, height: 2, color: context.colors.accent),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _node(context, 'Grinder', _grinder),
        line,
        _node(context, 'Brewer', _brewer),
        line,
        _node(context, 'Scale', _scale),
      ],
    );
  }
}

class CupArt extends StatelessWidget {
  const CupArt({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stroke = _hex(colors.textPrimary);
    final fill = _hex(onboardingArtBackground(colors));
    return SizedBox(
      width: 290,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          SvgPicture.string('''
<svg viewBox="0 0 240 200" fill="none" stroke="$stroke" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
<ellipse cx="116" cy="166" rx="90" ry="12"/>
<path d="M170 98C198 92 208 122 188 136C178 142 166 142 156 138"/>
<path d="M60 84C60 134 78 164 116 164C154 164 172 134 172 84Z" fill="$fill"/>
<ellipse cx="116" cy="84" rx="56" ry="11" fill="$fill"/>
<path d="M70 86C84 92 148 92 162 86"/>
<path d="M98 62C88 50 108 42 98 28"/><path d="M134 62C124 50 144 42 134 28"/>
</svg>''', width: 290),
          // Centered on the front of the cup: (116, 124) of 240 x 200.
          Positioned(
            left: 116 / 240 * 290 - 20,
            top: 124 / 240 * 290 - 20,
            // Always teal, the brand color: with the near-white Oat accent
            // the bean would disappear into the cup's outline.
            child: _GlowingBean(
              size: 40,
              color: Theme.of(context).brightness == Brightness.light
                  ? AppAccent.teal.light
                  : AppAccent.teal.dark,
            ),
          ),
        ],
      ),
    );
  }
}

// The bean on the cup breathes in teal, on the same 1100 ms beat
// as PulsingGlow, so the app keeps its one speed. That widget concentrates
// its glow along the edge of a wide button; a halo around a bean this small
// has to go nearly from off to full before the pulse can be seen at all.
class _GlowingBean extends StatefulWidget {
  const _GlowingBean({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_GlowingBean> createState() => _GlowingBeanState();
}

class _GlowingBeanState extends State<_GlowingBean>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, bean) {
          final t = _controller.value;
          final blur = 4 + t * 6;
          return Transform.scale(
            scale: 1 + t * 0.05,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Transform.scale(
                  scale: 1.05 + t * 0.2,
                  child: Opacity(
                    opacity: 0.15 + t * 0.85,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: bean,
                    ),
                  ),
                ),
                bean!,
              ],
            ),
          );
        },
        child: BeanIcon(size: widget.size, color: widget.color),
      ),
    );
  }
}
