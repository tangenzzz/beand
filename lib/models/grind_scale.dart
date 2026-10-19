import 'package:flutter/foundation.dart';

// How a grinder's setting is read (My Coffee Desk → grinder dialog): the
// unit, the step and the range of its dial. The grind ruler in Pre-Shot,
// Pre-Brew and the shot detail follows it.
enum GrindUnit {
  /// Numbers on a dial (Niche 0–50, DF64 0–90).
  dial('Dial', ''),

  /// Clicks of a hand grinder (Comandante, Kingrinder).
  clicks('Clicks', 'clicks'),

  /// Rotations and clicks (1Zpresso: "2.14") — counted as clicks inside.
  rotations('Rotations', ''),

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
    GrindUnit.clicks || GrindUnit.rotations => const [1],
  };
}

@immutable
class GrindScale {
  const GrindScale({
    this.unit = GrindUnit.dial,
    this.step = 0.1,
    this.min = 0,
    this.max = 20,
    this.clicksPerRotation = 30,
  });

  /// Without a grinder (or one without a scale): the ruler as before.
  static const standard = GrindScale();

  final GrindUnit unit;
  final double step;

  /// The range of the dial; may start below zero.
  final double min;
  final double max;

  /// Only for [GrindUnit.rotations].
  final int clicksPerRotation;

  int get digits {
    if (step >= 1) return 0;
    final text = step.toString();
    return text.contains('.') ? text.split('.').last.length : 0;
  }

  /// The value as read on the grinder, with its unit.
  String format(double value, {bool withUnit = true}) {
    final String text;
    if (unit == GrindUnit.rotations && clicksPerRotation > 0) {
      final clicks = value.round();
      final sign = clicks < 0 ? '-' : '';
      final abs = clicks.abs();
      text = '$sign${abs ~/ clicksPerRotation}.${abs % clicksPerRotation}';
    } else {
      text = value.toStringAsFixed(digits);
    }
    return withUnit && unit.suffix.isNotEmpty ? '$text ${unit.suffix}' : text;
  }

  double clamp(double value) => value.clamp(min, max).toDouble();

  Map<String, Object> toJson() => {
    'unit': unit.name,
    'step': step,
    'min': min,
    'max': max,
    if (unit == GrindUnit.rotations) 'perRotation': clicksPerRotation,
  };

  static GrindScale? fromJson(Object? json) {
    if (json is! Map) return null;
    final unit = GrindUnit.values.asNameMap()[json['unit']];
    final step = json['step'], min = json['min'], max = json['max'];
    if (unit == null || step is! num || min is! num || max is! num) {
      return null;
    }
    if (step <= 0 || max <= min) return null;
    final per = json['perRotation'];
    return GrindScale(
      unit: unit,
      step: step.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      clicksPerRotation: per is num && per > 0 ? per.toInt() : 30,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GrindScale &&
      other.unit == unit &&
      other.step == step &&
      other.min == min &&
      other.max == max &&
      other.clicksPerRotation == clicksPerRotation;

  @override
  int get hashCode => Object.hash(unit, step, min, max, clicksPerRotation);
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
