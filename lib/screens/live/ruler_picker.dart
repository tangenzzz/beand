import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

// Expanding picker for numbers (dose, grind) directly in the card: large
// value on top, below it a ruler you slide sideways (step 0.1, snaps). At
// the very bottom the footer with a keyboard icon for direct input (same
// rules as all dropdowns).
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.step = 0.1,
  });

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
  static const _gapBelow = 12.0;
  static const _footerHeight = 48.0;
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
      _footerHeight +
      _marginBottom;

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
  int get _digits => widget.step < 1 ? 1 : 0;

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
      // Material like InlinePicker: tap animations stay visible.
      child: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height:
                  RulerPicker._valueAreaHeight +
                  RulerPicker._rulerHeight +
                  RulerPicker._gapBelow,
              child: _typing
                  ? _ValueEditor(
                      initial: _valueOf(_tenths),
                      digits: _digits,
                      unit: widget.unit,
                      onSet: _setTyped,
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: RulerPicker._valueAreaHeight,
                          child: Center(child: _bigValue()),
                        ),
                        SizedBox(
                          height: RulerPicker._rulerHeight,
                          child: _ruler(),
                        ),
                        const SizedBox(height: RulerPicker._gapBelow),
                      ],
                    ),
            ),
            Divider(height: 1, color: context.colors.divider),
            SizedBox(
              height: RulerPicker._footerHeight,
              child: Row(
                children: [
                  IconButton(
                    tooltip: _typing ? 'Cancel' : 'Type value',
                    icon: Icon(
                      _typing ? Icons.close : Icons.keyboard_outlined,
                      color: context.colors.textSecondary,
                    ),
                    onPressed: () => setState(() => _typing = !_typing),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigValue() {
    return Text.rich(
      TextSpan(
        text: _valueOf(_tenths).toStringAsFixed(_digits),
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
                      RulerPicker._rulerHeight,
                    ),
                    painter: _RulerPainter(
                      minTenths: _minTenths,
                      step: widget.step,
                      tickCount: _tickCount,
                      tickColor: context.colors.textPrimary,
                      labelColor: context.colors.textSecondary,
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
  });

  final int minTenths;
  final double step;
  final int tickCount;

  /// Ticks and numbers of the ruler.
  final Color tickColor;
  final Color labelColor;

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
      if (tenths % 10 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: (tenths * step).round().toString(),
            style: TextStyle(color: labelColor, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x - label.width / 2, 36));
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.minTenths != minTenths ||
      old.tickCount != tickCount ||
      old.tickColor != tickColor ||
      old.labelColor != labelColor;
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
  });

  final double initial;
  final int digits;
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
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
