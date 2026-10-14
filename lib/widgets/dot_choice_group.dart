import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DotChoice<T> {
  const DotChoice(this.value, this.label);

  final T value;
  final String label;
}

// A row of choices of which at most one applies. No border, no fill: the
// selected one has a dot in the accent color on the left and slightly
// bolder text.
class DotChoiceGroup<T> extends StatelessWidget {
  const DotChoiceGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allowDeselect = false,
  });

  final List<DotChoice<T>> options;
  final T? value;

  /// Receives null when the selected choice is deselected — only possible
  /// with [allowDeselect].
  final ValueChanged<T?> onChanged;

  /// Tapping the selected one again deselects it (as it always was in the
  /// bean form).
  final bool allowDeselect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      // The entries' own padding provides the spacing; add only enough so
      // two words do not run together.
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final option in options)
          DotChoiceItem(
            label: option.label,
            selected: option.value == value,
            onTap: () {
              if (option.value == value) {
                if (allowDeselect) onChanged(null);
              } else {
                onChanged(option.value);
              }
            },
          ),
      ],
    );
  }
}

// A single entry. Public because the filters allow selecting several at
// once and should still look the same.
class DotChoiceItem extends StatelessWidget {
  const DotChoiceItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 160);
  static const _dotSize = 7.0;
  static const _dotGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: ConstrainedBox(
        // Without a border the area is small; the finger still needs room.
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The space grows along so the text glides on change instead
              // of jumping.
              AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOut,
                width: selected ? _dotSize + _dotGap : 0,
                alignment: Alignment.centerLeft,
                child: AnimatedScale(
                  duration: _duration,
                  curve: Curves.easeOutBack,
                  scale: selected ? 1 : 0.4,
                  child: AnimatedOpacity(
                    duration: _duration,
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: _dotSize,
                      height: _dotSize,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: _duration,
                style: TextStyle(
                  color: selected ? colors.textPrimary : colors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
