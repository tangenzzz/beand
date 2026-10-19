import 'package:flutter/material.dart';

import '../../models/grind_scale.dart';
import '../../widgets/underline_select.dart';
import 'ruler_picker.dart';

// The grind picker of Pre-Shot, Pre-Brew and the shot detail, shaped by the
// grinder's scale. On a grinder with several index marks (Kafatek
// Monolith: green, red, white) one ruler runs across all of them: sliding
// past the end of a mark carries on at the next one, and the mark can be
// picked on top — the value is then shown for that mark.
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

  static const _markerRow = 36.0;

  static double heightFor(GrindScale scale) =>
      RulerPicker.height + (scale.hasMarkers ? _markerRow : 0);

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
    if (current == null) {
      return RulerPicker(
        value: _scale.clamp(widget.value),
        min: _scale.min,
        max: _scale.max,
        step: _scale.step,
        format: (v) => _scale.format(v, withUnit: false),
        unit: _scale.unit.suffix,
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
                    leading: GrindMarkerDot(color: m.color),
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
          unit: _scale.unit.suffix,
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

/// The colour of an index mark as a small dot.
class GrindMarkerDot extends StatelessWidget {
  const GrindMarkerDot({super.key, required this.color, this.size = 8});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(color),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x33000000), width: 0.5),
    ),
  );
}
