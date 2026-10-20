import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

// Expanding picker for numbers (dose, grind) directly in the card: large
// value on top with the keyboard icon for direct input right next to it,
// below it a ruler you slide sideways (step 0.1, snaps). Framed like the
// choice lists of ValueSelectRow (0.5 px line, radius 10).
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.step = 0.1,
    this.format,
    this.showLabels = true,
  });

  /// Numbers under the long ticks. Off for the grind ruler (user request
  /// 2026-10-20): the big value above says it; the ruler gets lower.
  final bool showLabels;

  /// Shows the value as read on the device instead of plain digits (e.g. a
  /// grinder's "2.14" in rotations); the unit is added separately.
  final String Function(double value)? format;

  final double value;
  // Value of one tick. 0.1 for dose/grind size; pour-over water (up to
  // 1000 g) uses whole grams, otherwise the ruler would be endless.
  final double step;
  final double min;
  final double max;
  // Unit after the value ("g"), empty for unitless values.
  final String unit;
  final ValueChanged<double> onChanged;

  static const _valueAreaHeight = 64.0;
  static const _rulerHeight = 58.0;
  // Room of the numbers under the ticks, left out without labels.
  static const _labelArea = 22.0;
  static const _gapBelow = 12.0;
  static const _marginTop = 2.0;
  static const _marginBottom = 8.0;
  // Distance between two ticks (= 0.1) in px.
  static const _tickGap = 10.0;

  // Total height incl. outer padding (constant, also while typing).
  static const height =
      _marginTop +
      _valueAreaHeight +
      _rulerHeight +
      _gapBelow +
      1 +
      _marginBottom;

  /// The same without the ruler's numbers ([showLabels] false).
  static const compactHeight = height - _labelArea;

  double get _rulerH => showLabels ? _rulerHeight : _rulerHeight - _labelArea;

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  late final ScrollController _controller;
  late int _tenths;
  bool _typing = false;

  // "Tenths" = ticks; with step 0.1 these are tenths.
  int get _minTenths => (widget.min / widget.step).round();
  int get _tickCount => (widget.max / widget.step).round() - _minTenths;
  double _valueOf(int ticks) => ticks * widget.step;
  // As many decimals as the step needs (0.25 → 2).
  int get _digits {
    if (widget.step >= 1) return 0;
    final text = widget.step.toString();
    return text.contains('.') ? text.split('.').last.length : 0;
  }

  String _text(double v) =>
      widget.format?.call(v) ?? v.toStringAsFixed(_digits);

  double _offsetFor(int tenths) =>
      (tenths - _minTenths).clamp(0, _tickCount) * RulerPicker._tickGap;

  @override
  void initState() {
    super.initState();
    _tenths = (widget.value / widget.step).round();
    _controller = ScrollController(initialScrollOffset: _offsetFor(_tenths));
  }

  @override
  void didUpdateWidget(RulerPicker old) {
    super.didUpdateWidget(old);
    final incoming = (widget.value / widget.step).round();
    if (incoming != _tenths) {
      _tenths = incoming;
      if (_controller.hasClients) _controller.jumpTo(_offsetFor(incoming));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification || n.metrics.axis != Axis.horizontal) {
      return false;
    }
    final i = (n.metrics.pixels / RulerPicker._tickGap).round().clamp(
      0,
      _tickCount,
    );
    final tenths = _minTenths + i;
    if (tenths != _tenths) {
      setState(() => _tenths = tenths);
      widget.onChanged(_valueOf(tenths));
    }
    return false;
  }

  void _setTyped(double value) {
    final tenths = (value / widget.step).round();
    setState(() {
      _typing = false;
      _tenths = tenths;
    });
    if (_controller.hasClients) _controller.jumpTo(_offsetFor(tenths));
    widget.onChanged(_valueOf(tenths));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: RulerPicker._marginTop,
        bottom: RulerPicker._marginBottom,
      ),
      // Material, so tap animations stay visible on the card.
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.divider, width: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height:
                RulerPicker._valueAreaHeight +
                widget._rulerH +
                RulerPicker._gapBelow,
            child: _typing
                ? Row(
                    children: [
                      Expanded(
                        child: _ValueEditor(
                          initial: _valueOf(_tenths),
                          digits: _digits,
                          unit: widget.unit,
                          // Below zero needs a sign the number pad may lack.
                          signed: widget.min < 0,
                          onSet: _setTyped,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel',
                        icon: Icon(
                          Icons.close,
                          color: context.colors.textSecondary,
                        ),
                        onPressed: () => setState(() => _typing = false),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: RulerPicker._valueAreaHeight,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Same width as the icon, so the number stays
                              // centered over the ruler's mark.
                              const SizedBox(width: 48),
                              _bigValue(),
                              IconButton(
                                tooltip: 'Type value',
                                icon: Icon(
                                  Icons.keyboard_outlined,
                                  color: context.colors.textSecondary,
                                ),
                                onPressed: () => setState(() => _typing = true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: widget._rulerH, child: _ruler()),
                      const SizedBox(height: RulerPicker._gapBelow),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _bigValue() {
    return Text.rich(
      TextSpan(
        text: _text(_valueOf(_tenths)),
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        children: [
          if (widget.unit.isNotEmpty)
            TextSpan(
              text: '  ${widget.unit}',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }

  Widget _ruler() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const _StepSnapPhysics(step: RulerPicker._tickGap),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width / 2),
                  child: CustomPaint(
                    size: Size(
                      _tickCount * RulerPicker._tickGap,
                      widget._rulerH,
                    ),
                    painter: _RulerPainter(
                      minTenths: _minTenths,
                      step: widget.step,
                      tickCount: _tickCount,
                      tickColor: context.colors.textPrimary,
                      labelColor: context.colors.textSecondary,
                      showLabels: widget.showLabels,
                    ),
                  ),
                ),
              ),
            ),
            // Fade out the edges so the ruler tapers off softly.
            for (final left in [true, false])
              Positioned(
                left: left ? 0 : null,
                right: left ? null : 0,
                top: 0,
                bottom: 0,
                width: 48,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: left
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        end: left
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        colors: [
                          context.colors.card,
                          context.colors.card.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Fixed center mark (IgnorePointer, otherwise it swallows swipes
            // that start exactly in the middle).
            Positioned(
              top: 0,
              child: IgnorePointer(
                child: Container(
                  width: 2,
                  height: 34,
                  decoration: BoxDecoration(
                    color: context.colors.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.minTenths,
    required this.step,
    required this.tickCount,
    required this.tickColor,
    required this.labelColor,
    required this.showLabels,
  });

  final int minTenths;
  final double step;
  final int tickCount;

  /// Ticks and numbers of the ruler.
  final Color tickColor;
  final Color labelColor;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i <= tickCount; i++) {
      final tenths = minTenths + i;
      final x = i * RulerPicker._tickGap;
      final double h;
      final double alpha;
      if (tenths % 10 == 0) {
        h = 30;
        alpha = 0.75;
        paint.strokeWidth = 1.5;
      } else if (tenths % 5 == 0) {
        h = 20;
        alpha = 0.5;
        paint.strokeWidth = 1.2;
      } else {
        h = 11;
        alpha = 0.3;
        paint.strokeWidth = 1;
      }
      paint.color = tickColor.withValues(alpha: alpha);
      canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
      if (showLabels && tenths % 10 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: _label(tenths * step),
            style: TextStyle(color: labelColor, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x - label.width / 2, 36));
      }
    }
  }

  // Whole numbers without decimals, others as short as they get (2.5).
  static String _label(double v) {
    final rounded = (v * 100).round() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.minTenths != minTenths ||
      old.tickCount != tickCount ||
      old.tickColor != tickColor ||
      old.labelColor != labelColor ||
      old.showLabels != showLabels;
}

// Snaps to whole steps; the swipe velocity carries the ruler a bit further
// before it snaps.
class _StepSnapPhysics extends ScrollPhysics {
  const _StepSnapPhysics({required this.step, super.parent});

  final double step;

  @override
  _StepSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _StepSnapPhysics(step: step, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    final atEdge =
        (velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent);
    if (atEdge) return super.createBallisticSimulation(position, velocity);
    final projected = position.pixels + velocity * 0.2;
    final target = ((projected / step).round() * step)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

// Direct input: number keyboard, "Set" applies the value.
// Separate StatefulWidget so the controller is disposed cleanly in the
// state lifecycle.
class _ValueEditor extends StatefulWidget {
  const _ValueEditor({
    required this.initial,
    required this.unit,
    required this.onSet,
    this.digits = 1,
    this.signed = false,
  });

  final double initial;
  final int digits;

  /// Allows a minus, with a ± button next to the field.
  final bool signed;
  final String unit;
  final ValueChanged<double> onSet;

  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial.toStringAsFixed(widget.digits),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flipSign() {
    final t = _controller.text.trim();
    final next = t.startsWith('-') ? t.substring(1) : '-$t';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (value != null) widget.onSet(value);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 110,
            child: TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  widget.signed ? RegExp(r'^-?[0-9.,]*') : RegExp(r'[0-9.,]'),
                ),
              ],
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: context.colors.divider),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: context.colors.accent),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (widget.signed)
            TextButton(
              key: const ValueKey('ruler-sign'),
              onPressed: _flipSign,
              child: Text(
                '±',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 20,
                ),
              ),
            ),
          if (widget.unit.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              widget.unit,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(width: 16),
          AppButton(
            label: 'Set',
            onPressed: _submit,
            expand: false,
            height: 40,
          ),
        ],
      ),
    );
  }
}
