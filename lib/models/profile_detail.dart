import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// Complete profile definition from `GET /api/v1/profile/get/{id}` (or
// `/profile/list?full=true`): description, author, variables and all stages
// with setpoint curve, exit triggers and limits.
//
// Values in stages are either numbers or references to variables
// ("$time_Initial Saturation Duration"); they are resolved here, and the
// variable name is kept for display.
//
// Unit per value type of the machine (pressure, flow, power, weight, time,
// piston_position).
String unitFor(String type) => switch (type) {
  'pressure' => 'bar',
  'flow' => 'ml/s',
  'power' => '%',
  'weight' => 'g',
  'time' => 's',
  'piston_position' => 'mm',
  // GaggiMate only: cumulative pumped water as a stop condition.
  'pumped' => 'ml',
  _ => '',
};

String typeLabel(String type) => switch (type) {
  'pumped' => 'Pumped',
  'pressure' => 'Pressure',
  'flow' => 'Flow',
  'power' => 'Power',
  'weight' => 'Weight',
  'time' => 'Time',
  'piston_position' => 'Piston',
  _ => type,
};

// Colors of the stage types (as in the Meticulous web view: flow blue,
// pressure green, power red, weight yellow) — the same tokens as the curves
// in the chart, so both views mean the same thing.
Color colorForType(BuildContext context, String type) {
  final colors = context.colors;
  return switch (type) {
    'flow' => colors.sensorDown,
    'pressure' => colors.success,
    'power' => colors.danger,
    'weight' => colors.sensorMid,
    'piston_position' => colors.sensorGroup,
    'pumped' => colors.ice,
    _ => colors.textSecondary,
  };
}

// Number without superfluous zeros: 100 -> "100", 1.5 -> "1.5", 0.30 -> "0.3".
String formatNumber(double v) {
  final rounded = (v * 100).round() / 100;
  if (rounded % 1 == 0) return rounded.toStringAsFixed(0);
  var s = rounded.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

class ProfileVariable {
  const ProfileVariable({
    required this.name,
    required this.key,
    required this.type,
    required this.value,
  });

  final String name;
  final String key;
  final String type;
  final double value;
}

// A resolved numeric value; [variable] is the name of the variable if the
// value comes from one.
class ProfileValue {
  const ProfileValue(this.value, {this.variable});

  final double? value;
  final String? variable;
}

class StagePoint {
  const StagePoint(this.x, this.y);

  // Position on the axis (seconds if `over` = time).
  final double? x;
  final double? y;
}

class StageTrigger {
  const StageTrigger({
    required this.type,
    required this.value,
    required this.relative,
    required this.comparison,
  });

  final String type;
  final ProfileValue value;
  // Relative to the stage start (for time: stage duration, not shot time).
  final bool relative;
  final String comparison;
}

class StageLimit {
  const StageLimit({required this.type, required this.value});

  final String type;
  final ProfileValue value;
}

class ProfileStage {
  const ProfileStage({
    required this.number,
    required this.name,
    required this.type,
    required this.points,
    required this.over,
    required this.interpolation,
    required this.exitTriggers,
    required this.limits,
  });

  final int number;
  final String name;
  // What the stage controls: pressure | flow | power.
  final String type;
  final List<StagePoint> points;
  final String over;
  final String interpolation;
  final List<StageTrigger> exitTriggers;
  final List<StageLimit> limits;

  // Setpoint at the start / end of the stage.
  double? get startValue => points.isEmpty ? null : points.first.y;
  double? get endValue => points.isEmpty ? null : points.last.y;

  // Constant setpoint (a single point or all points equal).
  bool get isConstant {
    final ys = points.map((p) => p.y).whereType<double>().toSet();
    return ys.length <= 1;
  }

  // Duration of the curve (last time point), if defined over time.
  double? get curveSeconds {
    if (over != 'time' || points.length < 2) return null;
    return points.last.x;
  }
}

class ProfileDetail {
  const ProfileDetail({
    required this.id,
    required this.name,
    required this.temperature,
    required this.finalWeight,
    required this.accentColor,
    required this.imagePath,
    required this.shortDescription,
    required this.description,
    required this.author,
    required this.previousAuthors,
    required this.lastChanged,
    required this.stages,
    required this.variables,
    required this.isTemporary,
  });

  final String id;
  final String name;
  final double temperature;
  final double finalWeight;
  final Color accentColor;
  final String? imagePath;
  final String? shortDescription;
  final String? description;
  final String? author;
  final List<String> previousAuthors;
  final DateTime? lastChanged;
  final List<ProfileStage> stages;
  final List<ProfileVariable> variables;
  final bool isTemporary;

  factory ProfileDetail.fromJson(Map<String, dynamic> json) {
    final display = json['display'] is Map
        ? Map<String, dynamic>.from(json['display'] as Map)
        : const <String, dynamic>{};

    final variables = <ProfileVariable>[
      for (final v in (json['variables'] as List? ?? const []))
        if (v is Map && _num(v['value']) != null)
          ProfileVariable(
            name: (v['name'] ?? '').toString(),
            key: (v['key'] ?? '').toString(),
            type: (v['type'] ?? '').toString(),
            value: _num(v['value'])!,
          ),
    ];
    final byKey = {for (final v in variables) v.key: v};

    ProfileValue resolve(dynamic raw) {
      if (raw is String && raw.startsWith(r'$')) {
        final variable = byKey[raw.substring(1)];
        return ProfileValue(
          variable?.value,
          variable: variable?.name ?? raw.substring(1),
        );
      }
      return ProfileValue(_num(raw));
    }

    final stages = <ProfileStage>[];
    final rawStages = json['stages'] as List? ?? const [];
    for (var i = 0; i < rawStages.length; i++) {
      final s = rawStages[i];
      if (s is! Map) continue;
      final dynamics = s['dynamics'] is Map
          ? Map<String, dynamic>.from(s['dynamics'] as Map)
          : const <String, dynamic>{};
      stages.add(
        ProfileStage(
          number: i + 1,
          name: (s['name'] ?? '').toString().trim(),
          type: (s['type'] ?? '').toString(),
          points: [
            for (final p in (dynamics['points'] as List? ?? const []))
              if (p is List && p.length >= 2)
                StagePoint(resolve(p[0]).value, resolve(p[1]).value),
          ],
          over: (dynamics['over'] ?? 'time').toString(),
          interpolation: (dynamics['interpolation'] ?? 'linear').toString(),
          exitTriggers: [
            for (final t in (s['exit_triggers'] as List? ?? const []))
              if (t is Map)
                StageTrigger(
                  type: (t['type'] ?? '').toString(),
                  value: resolve(t['value']),
                  relative: t['relative'] == true,
                  comparison: (t['comparison'] ?? '>=').toString(),
                ),
          ],
          limits: [
            for (final l in (s['limits'] as List? ?? const []))
              if (l is Map)
                StageLimit(
                  type: (l['type'] ?? '').toString(),
                  value: resolve(l['value']),
                ),
          ],
        ),
      );
    }

    final changed = _num(json['last_changed']);
    String? clean(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final image = display['image'];
    return ProfileDetail(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      temperature: _num(json['temperature']) ?? 0,
      finalWeight: _num(json['final_weight']) ?? 0,
      accentColor: _parseColor(display['accentColor'] as String?),
      imagePath: image is String && image.isNotEmpty ? image : null,
      shortDescription: clean(display['shortDescription']),
      description: clean(display['description']),
      author: clean(json['author']),
      previousAuthors: [
        for (final a in (json['previous_authors'] as List? ?? const []))
          if (a is Map && clean(a['name']) != null) clean(a['name'])!,
      ],
      lastChanged: changed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((changed * 1000).round()),
      stages: stages,
      variables: variables,
      isTemporary: json['temporary'] == true,
    );
  }

  static double? _num(dynamic v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Color _parseColor(String? hex) {
    final value = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF3F3F44) : Color(0xFF000000 | value);
  }
}
