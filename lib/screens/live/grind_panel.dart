import 'package:flutter/material.dart';

import '../../models/grind_scale.dart';
import '../../widgets/underline_select.dart';
import 'ruler_picker.dart';

// The grind picker of Pre-Shot, Pre-Brew and the shot detail, shaped by the
// grinder's scale. On a grinder with several index marks (Kafatek
// Monolith: green, red, white) one ruler runs across all of them: sliding
// past the end of a mark carries on at the next one, and the mark can be
// picked on top — the value is then shown for that mark. A grinder read in
// several rotations gets the rotations on top the same way.
class GrindPanel extends StatefulWidget {
  const GrindPanel({
    super.key,
    required this.scale,
    required this.value,
    required this.marker,
    required this.onChanged,
  });

  final GrindScale scale;

  /// The reading at [marker] (as on the grinder).
  final double value;
  final String? marker;
  final void Function(double value, String? marker) onChanged;

  static const _markerRow = 30.0;

  static double heightFor(GrindScale scale) =>
      RulerPicker.compactHeight +
      (scale.hasMarkers || scale.hasRotations ? _markerRow : 0);

  @override
  State<GrindPanel> createState() => _GrindPanelState();
}

class _GrindPanelState extends State<GrindPanel> {
  late GrindMarker? _current = widget.scale.markerNamed(widget.marker);

  @override
  void didUpdateWidget(GrindPanel old) {
    super.didUpdateWidget(old);
    if (old.marker != widget.marker || old.scale != widget.scale) {
      _current = widget.scale.markerNamed(widget.marker);
    }
  }

  GrindScale get _scale => widget.scale;

  void _pick(GrindMarker marker) {
    final abs = _scale.absolute(widget.value, _current);
    final value = (abs - marker.offset).clamp(_scale.min, _scale.max);
    setState(() => _current = marker);
    widget.onChanged(value.toDouble(), marker.name);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (current == null && _scale.hasRotations) return _rotary();
    if (current == null) {
      return RulerPicker(
        value: _scale.clamp(widget.value),
        min: _scale.min,
        max: _scale.max,
        step: _scale.step,
        format: (v) => _scale.format(v, withUnit: false),
        unit: _scale.suffix,
        showLabels: false,
        onChanged: (v) => widget.onChanged(v, null),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: GrindPanel._markerRow,
          child: Center(
            child: Wrap(
              spacing: UnderlineSelect.spacing,
              children: [
                for (final m in _scale.markers)
                  UnderlineItem(
                    key: ValueKey('marker-${m.name}'),
                    label: m.name,
                    fontSize: 10,
                    // The chosen mark only in brighter text, no accent line.
                    underlineColor: Colors.transparent,
                    leading: GrindMarkerDot(color: m.color, size: 6),
                    selected: m == current,
                    onTap: () => _pick(m),
                  ),
              ],
            ),
          ),
        ),
        RulerPicker(
          value: _scale.absolute(widget.value, current),
          min: _scale.absoluteMin,
          max: _scale.absoluteMax,
          step: _scale.step,
          // The number as set at the mark the ruler stands at now.
          format: (abs) => _scale.format(
            _scale.read(abs, _current ?? current).value,
            withUnit: false,
          ),
          unit: _scale.suffix,
          showLabels: false,
          onChanged: (abs) {
            final r = _scale.read(abs, _current ?? current);
            if (r.marker != _current) setState(() => _current = r.marker);
            widget.onChanged(r.value, r.marker.name);
          },
        ),
      ],
    );
  }
}

extension on _GrindPanelState {
  // More than one rotation (K-Ultra "1.4.6"): the rotations on top like the
  // marks, the ruler across all of them. Tapping a rotation jumps to its
  // start (user 2026-11-17); sliding on moves the choice along.
  Widget _rotary() {
    final value = _scale.clamp(widget.value);
    final current = _scale.rotationOf(value);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: GrindPanel._markerRow,
          child: Center(
            child: Wrap(
              spacing: UnderlineSelect.spacing,
              children: [
                for (var r = 0; r < _scale.rotations; r++)
                  UnderlineItem(
                    key: ValueKey('rotation-$r'),
                    label: '$r',
                    fontSize: 10,
                    underlineColor: Colors.transparent,
                    selected: r == current,
                    onTap: () => widget.onChanged(
                      (r * _scale.clicksPerRotation).toDouble(),
                      null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        RulerPicker(
          value: value,
          min: _scale.min,
          max: _scale.max,
          step: _scale.step,
          format: (v) => _scale.format(v, withUnit: false),
          unit: _scale.suffix,
          showLabels: false,
          onChanged: (v) => widget.onChanged(v, null),
        ),
      ],
    );
  }
}

/// The colour of an index mark as a small dot.
class GrindMarkerDot extends StatelessWidget {
  const GrindMarkerDot({super.key, required this.color, this.size = 7});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(markerDisplayColor(color)),
      shape: BoxShape.circle,
    ),
  );
}
