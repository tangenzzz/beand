import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';
import 'shot_phases.dart';

// An entry from GET /api/v1/history?ids=<id>, prepared for the local DB.
class ParsedShot {
  const ParsedShot({
    required this.externalId,
    required this.timestamp,
    required this.profileName,
    required this.profileColor,
    required this.profileImageApiPath,
    required this.finalWeight,
    required this.durationMs,
    required this.brewTemp,
    required this.profileTemp,
    required this.readings,
    this.profileJson,
  });

  final String externalId;
  final DateTime timestamp;
  final String? profileName;
  final String? profileColor;
  // "/api/v1/profile/image/xxx.jpeg" — relative to the machine.
  final String? profileImageApiPath;
  final double? finalWeight;
  // Without retraction.
  final int? durationMs;
  final double? brewTemp;
  // Target temperature of the profile (°C).
  final double? profileTemp;
  final List<ShotReadingsCompanion Function(int shotId)> readings;

  /// The profile as it was on the machine at brew time (see
  /// [compactShotProfile]).
  final String? profileJson;
}

/// The profile from a history entry as it applied at brew time — with
/// stages and variables. The machine includes it in every entry (even in
/// the short list without time series); it is stored with the shot so the
/// analysis runs against the right version even if the profile is later
/// changed or deleted. Image data and author list are dropped, they say
/// nothing about the brew. Null if there are no stages.
String? compactShotProfile(Object? profile) {
  if (profile is! Map) return null;
  final stages = profile['stages'];
  if (stages is! List || stages.isEmpty) return null;
  final m = Map<String, dynamic>.from(profile)
    ..remove('display')
    ..remove('previous_authors')
    ..remove('author_id')
    ..remove('db_key');
  return jsonEncode(m);
}

double? _d(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) {
    final parsed = double.tryParse(v);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

Value<double?> _v(dynamic v) => Value(_d(v));

// null = entry unusable (no ID, no time or no measurement data).
ParsedShot? parseHistoryEntry(Map<String, dynamic> json) {
  final id = json['id'];
  final time = _d(json['time']);
  final data = json['data'];
  if (id is! String || id.isEmpty || time == null) return null;
  if (data is! List || data.isEmpty) return null;

  final profile = json['profile'] is Map
      ? Map<String, dynamic>.from(json['profile'] as Map)
      : const <String, dynamic>{};
  final display = profile['display'] is Map
      ? Map<String, dynamic>.from(profile['display'] as Map)
      : const <String, dynamic>{};

  final points = [
    for (final p in data)
      if (p is Map) Map<String, dynamic>.from(p),
  ];
  if (points.isEmpty) return null;

  int? durationMs;
  double? tempSum;
  var tempCount = 0;
  for (final p in points) {
    if (p['status'] == retractionStage) continue;
    durationMs = (_d(p['time']) ?? durationMs ?? 0).round();
    final sensors = p['sensors'] is Map
        ? Map<String, dynamic>.from(p['sensors'] as Map)
        : const <String, dynamic>{};
    final bars = [
      _d(sensors['bar_up']),
      _d(sensors['bar_mid_up']),
      _d(sensors['bar_mid_down']),
      _d(sensors['bar_down']),
    ].whereType<double>().toList();
    if (bars.isNotEmpty) {
      tempSum = (tempSum ?? 0) + bars.reduce((a, b) => a + b) / bars.length;
      tempCount++;
    }
  }

  final lastShot = points.last['shot'];
  final finalWeight = lastShot is Map ? _d(lastShot['weight']) : null;
  final image = display['image'];

  return ParsedShot(
    externalId: id,
    timestamp: DateTime.fromMillisecondsSinceEpoch((time * 1000).round()),
    profileName: (profile['name'] ?? json['name'])?.toString(),
    profileColor: display['accentColor'] as String?,
    profileImageApiPath: image is String && image.isNotEmpty ? image : null,
    finalWeight: finalWeight,
    durationMs: durationMs,
    brewTemp: tempCount == 0 ? null : tempSum! / tempCount,
    profileTemp: _d(profile['temperature']),
    profileJson: compactShotProfile(json['profile']),
    readings: [
      for (final p in points)
        (shotId) {
          final shot = p['shot'] is Map
              ? Map<String, dynamic>.from(p['shot'] as Map)
              : const <String, dynamic>{};
          final s = p['sensors'] is Map
              ? Map<String, dynamic>.from(p['sensors'] as Map)
              : const <String, dynamic>{};
          return ShotReadingsCompanion.insert(
            shotId: shotId,
            timeMs: (_d(p['time']) ?? 0).round(),
            profileMs: Value((_d(p['profile_time']))?.round()),
            pressure: _v(shot['pressure']),
            flow: _v(shot['flow']),
            weight: _v(shot['weight']),
            gravimetricFlow: _v(shot['gravimetric_flow']),
            externalTemp1: _v(s['external_1']),
            externalTemp2: _v(s['external_2']),
            barUp: _v(s['bar_up']),
            barMidUp: _v(s['bar_mid_up']),
            barMidDown: _v(s['bar_mid_down']),
            barDown: _v(s['bar_down']),
            tubeTemp: _v(s['tube']),
            motorTemp: _v(s['motor_temp']),
            lamTemp: _v(s['lam_temp']),
            motorPosition: _v(s['motor_position']),
            motorSpeed: _v(s['motor_speed']),
            motorPower: _v(s['motor_power']),
            motorCurrent: _v(s['motor_current']),
            bandheaterPower: _v(s['bandheater_power']),
            bandheaterCurrent: _v(s['bandheater_current']),
            pressureSensorRaw: _v(s['pressure_sensor']),
            waterStatus: Value(
              s['water_status'] is bool ? s['water_status'] as bool : null,
            ),
            weightPrediction: _v(s['weight_prediction']),
            stage: Value(p['status'] is String ? p['status'] as String : null),
          );
        },
    ],
  );
}
