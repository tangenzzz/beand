import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/profile_draft.dart';
import '../../../theme/app_theme.dart';
import 'editor_widgets.dart';

// The stage page's chart: target value over time, with draggable points.
//
// Interaction as in the reference apps: long-press adds a point, tap
// selects, drag moves, dragging out of the chart deletes. Points bound to a
// variable get a ring instead of a filled dot.
//
// If the stage has a limit of another quantity (a pressure stage limits
// flow), the chart gets a second axis on the left and the limit a dashed
// line — exactly like the community app does it.

// Upper end of the axis per quantity. Deliberately a bit above what the
// slider allows, so the curve doesn't stick to the edge.
double chartMaxForType(String type) => switch (type) {
  'pressure' => 14,
  'flow' => 15,
  'power' => 100,
  'weight' => 100,
  'piston_position' => 100,
  _ => 100,
};

class StageCurveEditor extends StatefulWidget {
  const StageCurveEditor({
    super.key,
    required this.stage,
    required this.variables,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final DraftStage stage;
  final List<DraftVariable> variables;

  // Index of the selected point, null = none.
  final int? selected;
  final ValueChanged<int?> onSelect;

  // The stage was changed; the parent redraws and validates.
  final VoidCallback onChanged;

  @override
  State<StageCurveEditor> createState() => _StageCurveEditorState();
}

class _StageCurveEditorState extends State<StageCurveEditor> {
  // Which point is currently under the finger.
  int? _dragging;

  // Is the finger outside? Then the point is deleted on release.
  bool _wouldDelete = false;

  static const _padLeft = 34.0;
  static const _padRight = 34.0;
  // Room at the top for the axis titles — otherwise they sit on the label of
  // the topmost grid line (seen on device).
  static const _padTop = 26.0;
  static const _padBottom = 20.0;
  static const _height = 190.0;

  DraftStage get _stage => widget.stage;

  // The limit with a different unit, drawn alongside as a dashed line.
  DraftLimit? get _shownLimit {
    for (final l in _stage.limits) {
      if (l.type != _stage.type) return l;
    }
    return null;
  }

  double get _maxX {
    var max = 0.0;
    for (final p in _stage.points) {
      final x = p.x.resolve(widget.variables);
      if (x != null && x > max) max = x;
    }
    // A completely flat axis would be unusable.
    return max < 5 ? 5 : max;
  }

  double get _maxY => chartMaxForType(_stage.type);

  // Chart coordinates <-> values.
  Offset _toScreen(double x, double y, Size size) {
    final w = size.width - _padLeft - _padRight;
    final h = size.height - _padTop - _padBottom;
    return Offset(
      _padLeft + (x / _maxX).clamp(0.0, 1.0) * w,
      _padTop + (1 - (y / _maxY).clamp(0.0, 1.0)) * h,
    );
  }

  ({double x, double y}) _toValue(Offset pos, Size size) {
    final w = size.width - _padLeft - _padRight;
    final h = size.height - _padTop - _padBottom;
    return (
      x: (((pos.dx - _padLeft) / w) * _maxX).clamp(0.0, _maxX),
      y: ((1 - (pos.dy - _padTop) / h) * _maxY).clamp(0.0, _maxY),
    );
  }

  bool _inside(Offset pos, Size size) =>
      pos.dx >= _padLeft - 24 &&
      pos.dx <= size.width - _padRight + 24 &&
      pos.dy >= _padTop - 24 &&
      pos.dy <= size.height - _padBottom + 24;

  // Point under the finger, if one is close enough.
  int? _hit(Offset pos, Size size) {
    var best = -1;
    var bestDistance = 32.0; // generous, fingers are imprecise
    for (var i = 0; i < _stage.points.length; i++) {
      final p = _stage.points[i];
      final x = p.x.resolve(widget.variables);
      final y = p.y.resolve(widget.variables);
      if (x == null || y == null) continue;
      final d = (_toScreen(x, y, size) - pos).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  void _addPoint(Offset pos, Size size) {
    final v = _toValue(pos, size);
    final step = _stage.type == 'power' ? 1.0 : 0.1;
    final y = (v.y / step).round() * step;
    final x = (v.x * 10).round() / 10;

    // Sort in so the curve doesn't jump back.
    var index = _stage.points.length;
    for (var i = 0; i < _stage.points.length; i++) {
      final px = _stage.points[i].x.resolve(widget.variables);
      if (px != null && px > x) {
        index = i;
        break;
      }
    }
    _stage.points.insert(
      index,
      DraftPoint(DraftValue.number(x), DraftValue.number(y)),
    );
    widget.onSelect(index);
    widget.onChanged();
  }

  void _moveTo(int index, Offset pos, Size size) {
    final point = _stage.points[index];
    final v = _toValue(pos, size);
    final step = _stage.type == 'power' ? 1.0 : 0.1;

    // Bound values belong to the variable — a finger must not overwrite
    // them, otherwise the binding is lost unnoticed.
    if (!point.y.isVariable) {
      point.y = DraftValue.number((v.y / step).round() * step);
    }
    if (!point.x.isVariable) {
      // The first point stays at 0, like in the Meticulous app.
      final x = index == 0 ? 0.0 : (v.x * 10).round() / 10;
      point.x = DraftValue.number(x);
    }
    widget.onChanged();
  }

  void _endDrag(Size size) {
    final index = _dragging;
    if (index != null && _wouldDelete && _canDelete(index)) {
      _stage.points.removeAt(index);
      widget.onSelect(null);
      widget.onChanged();
    } else {
      // The order may have changed after dragging.
      _sortPoints();
    }
    setState(() {
      _dragging = null;
      _wouldDelete = false;
    });
  }

  // The start point and the last remaining point stay.
  bool _canDelete(int index) => index != 0 && _stage.points.length > 2;

  void _sortPoints() {
    final selected = widget.selected == null
        ? null
        : _stage.points[widget.selected!];
    _stage.points.sort((a, b) {
      final ax = a.x.resolve(widget.variables) ?? 0;
      final bx = b.x.resolve(widget.variables) ?? 0;
      return ax.compareTo(bx);
    });
    if (selected != null) {
      final moved = _stage.points.indexOf(selected);
      if (moved != widget.selected) widget.onSelect(moved);
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = colorForStageType(context, _stage.type);
    final limit = _shownLimit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, _height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => widget.onSelect(_hit(d.localPosition, size)),
          onLongPressStart: (d) {
            // Only on empty space — otherwise a point would be duplicated.
            if (_hit(d.localPosition, size) == null) {
              _addPoint(d.localPosition, size);
            }
          },
          onPanStart: (d) {
            final index = _hit(d.localPosition, size);
            if (index == null) return;
            widget.onSelect(index);
            setState(() => _dragging = index);
          },
          onPanUpdate: (d) {
            final index = _dragging;
            if (index == null || index >= _stage.points.length) return;
            final outside = !_inside(d.localPosition, size);
            if (outside != _wouldDelete) {
              setState(() => _wouldDelete = outside);
            }
            if (!outside) _moveTo(index, d.localPosition, size);
          },
          onPanEnd: (_) => _endDrag(size),
          onPanCancel: () => setState(() {
            _dragging = null;
            _wouldDelete = false;
          }),
          child: SizedBox(
            height: _height,
            // The size MUST be here: a CustomPaint without a child otherwise
            // takes Size.zero, is only bounded by the constraints and thus
            // stays 0 wide — the chart would stay empty.
            child: CustomPaint(
              size: size,
              painter: _CurveEditorPainter(
                points: [
                  for (final p in _stage.points)
                    (
                      x: p.x.resolve(widget.variables),
                      y: p.y.resolve(widget.variables),
                      bound: p.x.isVariable || p.y.isVariable,
                    ),
                ],
                maxX: _maxX,
                maxY: _maxY,
                smooth: _stage.interpolation == 'curve',
                color: tint,
                grid: colors.divider,
                text: colors.textTertiary,
                selected: widget.selected,
                dimmed: _wouldDelete,
                valueLabel:
                    '${labelForType(_stage.type)} · ${unitForType(_stage.type)}',
                limitValue: limit?.value.resolve(widget.variables),
                limitMax: limit == null ? null : chartMaxForType(limit.type),
                limitLabel: limit == null
                    ? null
                    : '${labelForType(limit.type)} · ${unitForType(limit.type)}',
                limitColor: limit == null
                    ? null
                    : colorForStageType(context, limit.type),
                padLeft: limit == null ? _padRight : _padLeft,
                padRight: _padRight,
                padTop: _padTop,
                padBottom: _padBottom,
              ),
            ),
          ),
        );
      },
    );
  }
}

typedef _P = ({double? x, double? y, bool bound});

class _CurveEditorPainter extends CustomPainter {
  _CurveEditorPainter({
    required this.points,
    required this.maxX,
    required this.maxY,
    required this.smooth,
    required this.color,
    required this.grid,
    required this.text,
    required this.selected,
    required this.dimmed,
    required this.valueLabel,
    required this.limitValue,
    required this.limitMax,
    required this.limitLabel,
    required this.limitColor,
    required this.padLeft,
    required this.padRight,
    required this.padTop,
    required this.padBottom,
  });

  final List<_P> points;
  final double maxX;
  final double maxY;
  final bool smooth;
  final Color color;
  final Color grid;
  final Color text;
  final int? selected;
  final bool dimmed;
  final String valueLabel;
  final double? limitValue;
  final double? limitMax;
  final String? limitLabel;
  final Color? limitColor;
  final double padLeft;
  final double padRight;
  final double padTop;
  final double padBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - padLeft - padRight;
    final h = size.height - padTop - padBottom;
    if (w <= 0 || h <= 0) return;

    Offset at(double x, double y) => Offset(
      padLeft + (x / maxX).clamp(0.0, 1.0) * w,
      padTop + (1 - (y / maxY).clamp(0.0, 1.0)) * h,
    );

    // -- Grid and axis labels ---------------------------------------------

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    const rows = 4;
    for (var i = 0; i <= rows; i++) {
      final y = padTop + h * i / rows;
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + w, y), gridPaint);
      _label(
        canvas,
        trimNumber(maxY * (rows - i) / rows),
        Offset(padLeft + w + 4, y - 6),
        color,
      );
      if (limitMax != null) {
        _label(
          canvas,
          trimNumber(limitMax! * (rows - i) / rows),
          Offset(2, y - 6),
          limitColor ?? text,
        );
      }
    }

    // x-axis: start and end suffice, plus the middle.
    _label(canvas, '0s', Offset(padLeft, size.height - padBottom + 3), text);
    _label(
      canvas,
      '${trimNumber(maxX / 2)}s',
      Offset(padLeft + w / 2 - 10, size.height - padBottom + 3),
      text,
    );
    _label(
      canvas,
      '${trimNumber(maxX)}s',
      Offset(padLeft + w - 26, size.height - padBottom + 3),
      text,
    );

    // Axis titles, above the grid.
    _label(
      canvas,
      valueLabel,
      Offset(padLeft + w, 2),
      color,
      size: 9,
      alignRight: true,
    );
    if (limitLabel != null) {
      _label(
        canvas,
        limitLabel!,
        const Offset(2, 2),
        limitColor ?? text,
        size: 9,
      );
    }

    // -- Limit as dashed line ---------------------------------------------

    if (limitValue != null && limitMax != null && limitMax! > 0) {
      final y = padTop + (1 - (limitValue! / limitMax!).clamp(0.0, 1.0)) * h;
      final paint = Paint()
        ..color = (limitColor ?? text).withValues(alpha: 0.8)
        ..strokeWidth = 1.4;
      for (var x = padLeft; x < padLeft + w; x += 9) {
        canvas.drawLine(
          Offset(x, y),
          Offset(min(x + 5, padLeft + w), y),
          paint,
        );
      }
    }

    // -- Curve -------------------------------------------------------------

    final usable = [
      for (final p in points)
        if (p.x != null && p.y != null) p,
    ];
    if (usable.isEmpty) return;

    final offsets = [for (final p in usable) at(p.x!, p.y!)];
    final alpha = dimmed ? 0.35 : 1.0;

    if (offsets.length > 1) {
      final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      if (smooth && offsets.length > 2) {
        for (var i = 1; i < offsets.length; i++) {
          final prev = offsets[i - 1];
          final cur = offsets[i];
          final midX = (prev.dx + cur.dx) / 2;
          line.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
        }
      } else {
        for (final o in offsets.skip(1)) {
          line.lineTo(o.dx, o.dy);
        }
      }

      final area = Path.from(line)
        ..lineTo(offsets.last.dx, padTop + h)
        ..lineTo(offsets.first.dx, padTop + h)
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = color.withValues(alpha: 0.10 * alpha),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // -- Points ------------------------------------------------------------

    for (var i = 0; i < offsets.length; i++) {
      final isSelected = i == selected;
      final bound = usable[i].bound;
      final radius = isSelected ? 7.0 : 5.0;

      if (bound) {
        // Bound: only a ring, so the variable is visible.
        canvas.drawCircle(
          offsets[i],
          radius,
          Paint()
            ..color = color.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      } else {
        canvas.drawCircle(
          offsets[i],
          radius,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
      if (isSelected) {
        canvas.drawCircle(
          offsets[i],
          radius + 4,
          Paint()
            ..color = color.withValues(alpha: 0.45 * alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }
  }

  void _label(
    Canvas canvas,
    String value,
    Offset at,
    Color color, {
    double size = 9.5,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      alignRight ? Offset(at.dx - painter.width, at.dy) : at,
    );
  }

  @override
  bool shouldRepaint(_CurveEditorPainter old) => true;
}
