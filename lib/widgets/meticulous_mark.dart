import 'package:flutter/material.dart';

/// Stand-in for the Meticulous logo until the maker allows its use (asked,
/// no answer yet — user 2026-11-04): a plain, wide "M" sized like an icon.
/// Swap this one widget for the real mark later.
class MeticulousMark extends StatelessWidget {
  const MeticulousMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          'M',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: c,
            fontSize: size * 0.95,
            height: 1,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
