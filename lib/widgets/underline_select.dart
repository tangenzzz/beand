import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

// The app's direct choice (no dropdown): plain text options, no border, no
// fill, no pill. The chosen one is in textPrimary with a 2 px underline in
// the accent color, exactly as wide as the text; the others in
// textSecondary with the underline's room kept free, so nothing jumps.
// Single or multi select; many options wrap (never scroll sideways).
//
// [UnderlineItem] is the single option on its own — the taste levels and
// the typing suggestions build on it.

class UnderlineOption<T> {
  const UnderlineOption(this.value, this.label);

  final T value;
  final String label;
}

class UnderlineSelect<T> extends StatelessWidget {
  /// Exactly one (or none) chosen: tapping picks, the previous one goes.
  const UnderlineSelect({
    super.key,
    required this.options,
    required this.value,
    required ValueChanged<T?> this.onChanged,
    this.allowDeselect = false,
  }) : multiSelect = false,
       values = null,
       onToggle = null;

  /// Any number chosen: tapping switches an option on/off.
  const UnderlineSelect.multi({
    super.key,
    required this.options,
    required Set<T> this.values,
    required ValueChanged<T> this.onToggle,
  }) : multiSelect = true,
       value = null,
       onChanged = null,
       allowDeselect = true;

  final List<UnderlineOption<T>> options;
  final bool multiSelect;
  final T? value;
  final Set<T>? values;
  final ValueChanged<T?>? onChanged;
  final ValueChanged<T>? onToggle;

  /// Single select: tapping the chosen one clears it (onChanged gets
  /// null) — for fields that may stay empty.
  final bool allowDeselect;

  static const spacing = 14.0;

  bool _isSelected(T v) => multiSelect ? values!.contains(v) : v == value;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      children: [
        for (final o in options)
          UnderlineItem(
            label: o.label,
            selected: _isSelected(o.value),
            onTap: () {
              if (multiSelect) {
                onToggle!(o.value);
              } else if (o.value != value) {
                onChanged!(o.value);
              } else if (allowDeselect) {
                onChanged!(null);
              }
            },
          ),
      ],
    );
  }
}

/// One option: text with an underline that grows from the middle when
/// chosen. At least 44 px tap height (invisibly extended).
class UnderlineItem extends StatefulWidget {
  const UnderlineItem({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.underlineColor,
    this.idleUnderline = false,
    this.highlight,
    this.trailing,
    this.fontSize = 14,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Defaults to the accent color.
  final Color? underlineColor;

  /// A 1 px divider-colored line while not chosen — marks typing
  /// suggestions as tappable.
  final bool idleUnderline;

  /// Leading part of [label] shown in textPrimary (the letters typed so
  /// far in a suggestion).
  final String? highlight;

  /// E.g. the level dots of a taste note, after the text.
  final Widget? trailing;
  final double fontSize;

  static const minTapHeight = 44.0;
  static const _line = 2.0;
  static const _duration = Duration(milliseconds: 150);

  @override
  State<UnderlineItem> createState() => _UnderlineItemState();
}

class _UnderlineItemState extends State<UnderlineItem> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;
    final base = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
      color: selected || _pressed
          ? colors.textPrimary.withValues(alpha: _pressed ? 0.7 : 1)
          : colors.textSecondary,
    );
    final highlight = widget.highlight;
    final text =
        highlight != null &&
            highlight.isNotEmpty &&
            widget.label.toLowerCase().startsWith(highlight.toLowerCase())
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: widget.label.substring(0, highlight.length),
                  style: base.copyWith(color: colors.textPrimary),
                ),
                TextSpan(text: widget.label.substring(highlight.length)),
              ],
            ),
            style: base,
          )
        : Text(widget.label, style: base);

    final content = IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [text, ?widget.trailing],
            ),
          ),
          // The underline's room is always there; selected it grows from
          // the middle to the full text width.
          SizedBox(
            height: UnderlineItem._line,
            child: Stack(
              children: [
                if (widget.idleUnderline && !selected)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(height: 1, color: colors.divider),
                  ),
                Positioned.fill(
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: UnderlineItem._duration,
                    curve: Curves.easeOut,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.underlineColor ?? colors.accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final tappable = widget.onTap != null;
    return Semantics(
      button: tappable,
      selected: selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: tappable ? (_) => _setPressed(true) : null,
        onTapUp: tappable ? (_) => _setPressed(false) : null,
        onTapCancel: tappable ? () => _setPressed(false) : null,
        onTap: tappable
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: UnderlineItem.minTapHeight,
          ),
          child: Align(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );
  }
}
