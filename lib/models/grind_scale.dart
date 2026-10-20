import 'package:flutter/foundation.dart';

// How a grinder's setting is read (My Coffee Desk → grinder dialog): the
// unit, the step and the range of its dial. The grind ruler in Pre-Shot,
// Pre-Brew and the shot detail follows it.
enum GrindUnit {
  /// Numbers on a dial (Niche 0–50, DF64 0–90).
  dial('Dial', ''),

  /// Clicks of a hand grinder (Comandante, Kingrinder). With clicks per
  /// rotation set, read as rotations and clicks (1Zpresso: "2.14") — until
  /// 2026-10-20 that was a unit of its own, "rotations" (see fromJson).
  clicks('Clicks', 'clicks'),

  /// Microns, as some single-dose grinders give their scale.
  microns('Microns', 'µm');

  const GrindUnit(this.label, this.suffix);
  final String label;

  /// After the value ("24 clicks", "450 µm"); empty for a dial.
  final String suffix;

  /// The steps to choose from; a click is always one.
  List<double> get steps => switch (this) {
    GrindUnit.dial => const [1, 0.5, 0.25, 0.1],
    GrindUnit.microns => const [50, 25, 10, 5, 1],
    GrindUnit.clicks => const [1],
  };
}

/// An index mark on the grinder's body that the dial is read against —
/// some grinders (Kafatek Monolith) have several, each for a range of
/// grind sizes, so the same number means something else at another mark.
/// [offset]: how far this mark sits from the first one, in dial units —
/// "red 2.2 is green 9.0" makes red's offset 6.8.
@immutable
class GrindMarker {
  const GrindMarker({required this.name, required this.color, this.offset = 0});

  final String name;

  /// ARGB, e.g. 0xFF4CAF50.
  final int color;
  final double offset;

  Map<String, Object> toJson() => {
    'name': name,
    'color': color,
    'offset': offset,
  };

  static GrindMarker? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], color = json['color'], offset = json['offset'];
    if (name is! String || color is! int) return null;
    return GrindMarker(
      name: name,
      color: color,
      offset: offset is num ? offset.toDouble() : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GrindMarker &&
      other.name == name &&
      other.color == color &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(name, color, offset);
}

/// Colours of index marks to pick from — muted, so the dots sit quietly
/// next to the values (user 2026-10-19: the first, bright ones were too
/// loud): green, red, white, blue, yellow, orange, purple, black.
const markerPalette = [
  0xFF5F8A62,
  0xFFA85A55,
  0xFFB9B5AC,
  0xFF5E7FA0,
  0xFFB59E57,
  0xFFB37A4B,
  0xFF84709C,
  0xFF4A4A4A,
];

// The bright first palette, in the same order: marks saved with it are
// shown in the muted colour.
const _brightPalette = [
  0xFF4CAF50,
  0xFFE53935,
  0xFFF2F2F2,
  0xFF1E88E5,
  0xFFFDD835,
  0xFFFB8C00,
  0xFF8E24AA,
  0xFF212121,
];

/// The colour a mark is drawn in.
int markerDisplayColor(int color) {
  final i = _brightPalette.indexOf(color);
  return i < 0 ? color : markerPalette[i];
}

/// A reading on a grinder with markers: the number and the mark it is set
/// against.
typedef MarkedGrind = ({double value, GrindMarker marker});

@immutable
class GrindScale {
  const GrindScale({
    this.unit = GrindUnit.dial,
    this.step = 0.1,
    this.min = 0,
    this.max = 20,
    this.clicksPerRotation = 0,
    this.markers = const [],
  });

  /// Index marks, the first one the reference (offset 0). Empty for the
  /// usual single scale.
  final List<GrindMarker> markers;

  bool get hasMarkers => markers.isNotEmpty;

  GrindMarker? markerNamed(String? name) =>
      markers.where((m) => m.name == name).firstOrNull ?? markers.firstOrNull;

  /// One position across all markers ("in units of the first one").
  double absolute(double value, GrindMarker? marker) =>
      value + (marker?.offset ?? 0);

  /// The whole range the dial covers over all markers.
  double get absoluteMin => markers.isEmpty
      ? min
      : min + markers.map((m) => m.offset).reduce((a, b) => a < b ? a : b);
  double get absoluteMax => markers.isEmpty
      ? max
      : max + markers.map((m) => m.offset).reduce((a, b) => a > b ? a : b);

  /// The reading for a position on the shared scale: stays at [current] as
  /// long as its range reaches, only then switches to the neighbouring
  /// mark — so it doesn't flip back and forth where two marks overlap.
  MarkedGrind read(double absolute, GrindMarker current) {
    bool fits(GrindMarker m) =>
        absolute >= min + m.offset - 1e-9 && absolute <= max + m.offset + 1e-9;
    if (fits(current)) {
      return (value: _snap(absolute - current.offset), marker: current);
    }
    // Going up: the mark whose range starts lowest beyond; going down: the
    // one ending highest.
    final up = absolute > max + current.offset;
    final candidates = [
      for (final m in markers)
        if (fits(m)) m,
    ]..sort((a, b) => a.offset.compareTo(b.offset));
    final next = candidates.isEmpty
        ? current
        : (up ? candidates.first : candidates.last);
    return (
      value: _snap((absolute - next.offset).clamp(min, max).toDouble()),
      marker: next,
    );
  }

  double _snap(double v) => (v / step).round() * step;

  /// Without a grinder (or one without a scale): the ruler as before.
  static const standard = GrindScale();

  final GrindUnit unit;
  final double step;

  /// The range of the dial; may start below zero.
  final double min;
  final double max;

  /// Clicks only: above 0 the value reads as rotations and clicks ("2.14"),
  /// 0 as plain clicks ("24 clicks").
  final int clicksPerRotation;

  bool get _asRotations => unit == GrindUnit.clicks && clicksPerRotation > 0;

  /// After the value: the unit's, except clicks read as rotations ("2.14"
  /// stands alone).
  String get suffix => _asRotations ? '' : unit.suffix;

  int get digits {
    if (step >= 1) return 0;
    final text = step.toString();
    return text.contains('.') ? text.split('.').last.length : 0;
  }

  /// The value as read on the grinder, with its unit.
  String format(double value, {bool withUnit = true}) {
    final String text;
    if (_asRotations) {
      final clicks = value.round();
      final sign = clicks < 0 ? '-' : '';
      final abs = clicks.abs();
      text = '$sign${abs ~/ clicksPerRotation}.${abs % clicksPerRotation}';
    } else {
      text = value.toStringAsFixed(digits);
    }
    return withUnit && suffix.isNotEmpty ? '$text $suffix' : text;
  }

  double clamp(double value) => value.clamp(min, max).toDouble();

  Map<String, Object> toJson() => {
    'unit': unit.name,
    'step': step,
    'min': min,
    'max': max,
    if (_asRotations) 'perRotation': clicksPerRotation,
    if (markers.isNotEmpty) 'markers': [for (final m in markers) m.toJson()],
  };

  static GrindScale? fromJson(Object? json) {
    if (json is! Map) return null;
    // "rotations" was its own unit until 2026-10-20: now clicks with clicks
    // per rotation (30 when none was stored, its default then).
    final legacyRotations = json['unit'] == 'rotations';
    final unit = legacyRotations
        ? GrindUnit.clicks
        : GrindUnit.values.asNameMap()[json['unit']];
    final step = json['step'], min = json['min'], max = json['max'];
    if (unit == null || step is! num || min is! num || max is! num) {
      return null;
    }
    if (step <= 0 || max <= min) return null;
    final per = json['perRotation'];
    final markers = json['markers'];
    return GrindScale(
      unit: unit,
      step: step.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      clicksPerRotation: per is num && per > 0
          ? per.toInt()
          : (legacyRotations ? 30 : 0),
      markers: markers is List
          ? [for (final m in markers) ?GrindMarker.fromJson(m)]
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GrindScale &&
      other.unit == unit &&
      other.step == step &&
      other.min == min &&
      other.max == max &&
      other.clicksPerRotation == clicksPerRotation &&
      listEquals(other.markers, markers);

  @override
  int get hashCode => Object.hash(
    unit,
    step,
    min,
    max,
    clicksPerRotation,
    Object.hashAll(markers),
  );
}

/// One setting of the zero point: the dial reading where the burrs touch
/// ("chirp"), may be negative. Kept as a history, so a shot can be
/// compared across re-zeroing and burr changes.
@immutable
class ZeroPoint {
  const ZeroPoint(this.value, this.at);

  final double value;
  final DateTime at;

  Map<String, Object> toJson() => {
    'value': value,
    'at': at.millisecondsSinceEpoch,
  };

  static ZeroPoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final v = json['value'], at = json['at'];
    if (v is! num || at is! int) return null;
    return ZeroPoint(v.toDouble(), DateTime.fromMillisecondsSinceEpoch(at));
  }

  @override
  bool operator ==(Object other) =>
      other is ZeroPoint && other.value == value && other.at == at;

  @override
  int get hashCode => Object.hash(value, at);
}
