import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../machines/gaggimate/gaggimate_shot_log.dart';
import 'history_import.dart';

// A shot file picked by the user for a manually added shot: whatever the
// file knows (curve, profile, weights, time) prefilled into the form, the
// curve stored as the shot's readings. Which format it is is read from the
// content, not the file name:
//
// - GaggiMate `.slog` (binary, magic 'SHOT'), from its web UI
// - Meticulous history entry (JSON with `data` points), from its web UI
// - visualizer.coffee shot JSON (`timeframe` + `data` series) and its CSV
//   export (`information_type,elapsed,…`: meta rows, then one row per
//   moment)
// - Decent: de1app JSON v2 (`elapsed` + series) or the Tcl `.shot` file
// - a profile without a curve (Gaggiuino-style JSON with `phases`, as
//   visualizer.coffee hands it out): name and temperature only

class ShotFileException implements Exception {
  const ShotFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportedShot {
  const ImportedShot({
    required this.format,
    required this.readings,
    this.machine,
    this.externalId,
    this.timestamp,
    this.profileName,
    this.profileColor,
    this.profileJson,
    this.stageExits,
    this.doseGrams,
    this.finalWeight,
    this.durationMs,
    this.grind,
    this.profileTemp,
    this.brewTemp,
  });

  /// Shown after loading ("GaggiMate shot · 412 points").
  final String format;

  /// Brew method key (Shots.machine) the file belongs to; null = the file
  /// doesn't tell (visualizer, Decent), the user's choice stays.
  final String? machine;

  /// Machine history ID (Meticulous) — same as the automatic import, so a
  /// shot is never there twice.
  final String? externalId;
  final DateTime? timestamp;
  final String? profileName;
  final String? profileColor;
  final String? profileJson;
  final String? stageExits;
  final double? doseGrams;
  final double? finalWeight;
  final int? durationMs;
  final String? grind;
  final double? profileTemp;
  final double? brewTemp;
  final List<ShotReadingsCompanion Function(int shotId)> readings;
}

ImportedShot parseShotFile(Uint8List bytes) {
  if (bytes.length >= 4 &&
      ByteData.sublistView(bytes).getUint32(0, Endian.little) == 0x544F4853) {
    return _gaggiMate(bytes);
  }
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.startsWith('{') || text.startsWith('[')) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const ShotFileException('The file is not valid JSON.');
    }
    final map = _shotMap(json);
    if (map != null) {
      if (map['data'] is List) return _meticulous(map);
      if (map['timeframe'] is List && map['data'] is Map) {
        return _visualizer(map);
      }
      if (map['elapsed'] is List) return _decentJson(map);
      if (map['phases'] is List) return _phasesProfile(map);
    }
  } else if (text.startsWith('information_type,')) {
    return _visualizerCsv(text);
  } else if (text.contains('espresso_elapsed')) {
    return _decentTcl(text);
  }
  throw const ShotFileException(
    'Unknown file. Supported: GaggiMate .slog, Meticulous, '
    'visualizer.coffee (JSON, CSV) and Decent shot files.',
  );
}

// A single shot, also inside {"history": [...]} or a one-element list.
Map<String, dynamic>? _shotMap(Object? json) {
  if (json is List && json.isNotEmpty) return _shotMap(json.first);
  if (json is! Map) return null;
  final map = Map<String, dynamic>.from(json);
  if (map['history'] is List) return _shotMap(map['history']);
  return map;
}

ImportedShot _gaggiMate(Uint8List bytes) {
  final GaggiMateShotLog log;
  try {
    log = parseGaggiMateShotLog(bytes);
  } on GaggiMateShotLogException catch (e) {
    throw ShotFileException('Could not read the GaggiMate file ($e).');
  }
  if (log.samples.isEmpty) {
    throw const ShotFileException('The GaggiMate file has no readings.');
  }
  return ImportedShot(
    format: 'GaggiMate shot',
    machine: 'gaggimate',
    timestamp: _plausible(log.startedAt) ? log.startedAt : null,
    profileName: log.profileName.isEmpty ? null : log.profileName,
    finalWeight: log.finalWeight,
    durationMs: log.durationMs > 0 ? log.durationMs : null,
    profileTemp: log.targetTemp,
    brewTemp: log.averageTemp,
    stageExits: log.phaseExits.isEmpty
        ? null
        : jsonEncode([for (final e in log.phaseExits) e.toJson()]),
    // Same columns as the automatic GaggiMate import.
    readings: [
      for (final s in log.samples)
        (shotId) => ShotReadingsCompanion.insert(
          shotId: shotId,
          timeMs: s.timeMs,
          pressure: Value(s.pressure),
          flow: Value(s.pumpFlow),
          weight: Value(s.weight),
          gravimetricFlow: Value(s.scaleConnected ? s.scaleFlow : null),
          barUp: Value(s.currentTemp),
          stage: Value(s.stage),
        ),
    ],
  );
}

ImportedShot _meticulous(Map<String, dynamic> map) {
  final parsed = parseHistoryEntry(map);
  if (parsed == null) {
    throw const ShotFileException('The Meticulous file has no readings.');
  }
  return ImportedShot(
    format: 'Meticulous shot',
    machine: 'meticulous',
    externalId: parsed.externalId,
    timestamp: parsed.timestamp,
    profileName: parsed.profileName,
    profileColor: parsed.profileColor,
    profileJson: parsed.profileJson,
    finalWeight: parsed.finalWeight,
    durationMs: parsed.durationMs,
    profileTemp: parsed.profileTemp,
    brewTemp: parsed.brewTemp,
    readings: parsed.readings,
  );
}

// visualizer.coffee: series as lists of numbers or numeric strings over
// `timeframe` (seconds); details as top-level keys.
ImportedShot _visualizer(Map<String, dynamic> map) {
  final data = Map<String, dynamic>.from(map['data'] as Map);
  return _fromSeries(
    format: 'visualizer.coffee shot',
    seconds: _numbers(map['timeframe']),
    pressure: _numbers(data['espresso_pressure']),
    flow: _numbers(data['espresso_flow']),
    weight: _numbers(data['espresso_weight']),
    weightFlow: _numbers(data['espresso_flow_weight']),
    temp: _numbers(
      data['espresso_temperature_basket'] ?? data['espresso_temperature_mix'],
    ),
    timestamp: _time(map['start_time']),
    profileName: _text(map['profile_title']),
    doseGrams: _number(map['bean_weight']),
    finalWeight: _number(map['drink_weight']),
    grind: _text(map['grinder_setting']),
  );
}

// visualizer.coffee CSV export: `meta` rows (Name, Date, Weight = the drink
// weight) and `moment` rows with the series, columns named in the header.
ImportedShot _visualizerCsv(String text) {
  final lines = const LineSplitter().convert(text);
  final header = lines.first.split(',');
  int col(String name) => header.indexOf(name);
  final type = col('information_type');
  final metaKey = col('metatype');
  final metaValue = col('metadata');
  final meta = <String, String>{};
  final rows = <List<String>>[];
  for (final line in lines.skip(1)) {
    final cells = line.split(',');
    String cell(int i) => i >= 0 && i < cells.length ? cells[i].trim() : '';
    switch (cell(type)) {
      case 'meta':
        meta[cell(metaKey)] = cell(metaValue);
      case 'moment':
        rows.add(cells);
    }
  }
  List<double> series(List<String> names) {
    for (final name in names) {
      final i = col(name);
      if (i < 0) continue;
      final values = [
        for (final r in rows)
          i < r.length ? double.tryParse(r[i].trim()) : null,
      ];
      if (values.any((v) => v != null)) return [for (final v in values) v ?? 0];
    }
    return const [];
  }

  return _fromSeries(
    format: 'visualizer.coffee shot',
    seconds: series(['elapsed']),
    pressure: series(['pressure']),
    flow: series(['flow_in']),
    weight: series(['current_total_shot_weight']),
    weightFlow: series(['flow_out']),
    temp: series([
      'water_temperature_basket',
      'water_temperature_in',
      'water_temperature_boiler',
    ]),
    timestamp: _time(meta['Date']),
    profileName: _text(meta['Name']),
    finalWeight: _number(meta['Weight']),
  );
}

// A profile only (`phases`, Gaggiuino-style, also from visualizer.coffee):
// no curve, but its name and water temperature.
ImportedShot _phasesProfile(Map<String, dynamic> map) => ImportedShot(
  format: 'Profile, no curve',
  profileName: _text(map['name']),
  profileTemp: _number(map['waterTemperature']),
  profileJson: jsonEncode(map),
  readings: const [],
);

// de1app JSON v2: `elapsed` in seconds, series grouped by kind.
ImportedShot _decentJson(Map<String, dynamic> map) {
  Map<String, dynamic> group(String key) => map[key] is Map
      ? Map<String, dynamic>.from(map[key] as Map)
      : const <String, dynamic>{};
  final meta = group('meta');
  final profile = group('profile');
  final temperature = group('temperature');
  final grinder = meta['grinder'] is Map
      ? Map<String, dynamic>.from(meta['grinder'] as Map)
      : const <String, dynamic>{};
  return _fromSeries(
    format: 'Decent shot',
    seconds: _numbers(map['elapsed']),
    pressure: _numbers(group('pressure')['pressure']),
    flow: _numbers(group('flow')['flow']),
    weight: _numbers(group('totals')['weight']),
    weightFlow: _numbers(group('flow')['by_weight']),
    temp: _numbers(temperature['basket'] ?? temperature['mix']),
    timestamp: _time(map['timestamp']),
    profileName: _text(profile['title']),
    doseGrams: _number(meta['in']),
    finalWeight: _number(meta['out']),
    grind: _text(grinder['setting']),
  );
}

// The de1app's Tcl `.shot` file: `espresso_pressure {9.0 9.1 …}` lists and
// `key value` / `key {value}` pairs, also nested inside `settings {…}`.
ImportedShot _decentTcl(String text) {
  List<double> list(String key) {
    final m = RegExp('(?:^|\\s)$key \\{([^{}]*)\\}').firstMatch(text);
    return m == null
        ? const []
        : _numbers(m.group(1)!.trim().split(RegExp(r'\s+')));
  }

  String? value(String key) {
    final m = RegExp('(?:^|\\s)$key (?:\\{([^{}]*)\\}|(\\S+))')
        .firstMatch(text);
    if (m == null) return null;
    return _text(m.group(1) ?? m.group(2));
  }

  final clock = int.tryParse(value('clock') ?? '');
  return _fromSeries(
    format: 'Decent shot',
    seconds: list('espresso_elapsed'),
    pressure: list('espresso_pressure'),
    flow: list('espresso_flow'),
    weight: list('espresso_weight'),
    weightFlow: list('espresso_flow_weight'),
    temp: list('espresso_temperature_basket').isNotEmpty
        ? list('espresso_temperature_basket')
        : list('espresso_temperature_mix'),
    timestamp: clock == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(clock * 1000),
    profileName: value('profile_title'),
    doseGrams: double.tryParse(value('grinder_dose_weight') ?? ''),
    finalWeight: double.tryParse(value('drink_weight') ?? ''),
    grind: value('grinder_setting'),
  );
}

ImportedShot _fromSeries({
  required String format,
  required List<double> seconds,
  required List<double> pressure,
  required List<double> flow,
  required List<double> weight,
  required List<double> weightFlow,
  required List<double> temp,
  DateTime? timestamp,
  String? profileName,
  double? doseGrams,
  double? finalWeight,
  String? grind,
}) {
  if (seconds.isEmpty) {
    throw ShotFileException('The $format file has no readings.');
  }
  double? at(List<double> series, int i) =>
      i < series.length ? series[i] : null;
  final temps = [
    for (final t in temp)
      if (t > 0) t,
  ];
  final maxWeight = weight.isEmpty
      ? null
      : weight.reduce((a, b) => a > b ? a : b);
  return ImportedShot(
    format: format,
    timestamp: timestamp != null && _plausible(timestamp) ? timestamp : null,
    profileName: profileName,
    doseGrams: doseGrams != null && doseGrams > 0 ? doseGrams : null,
    finalWeight: finalWeight != null && finalWeight > 0
        ? finalWeight
        : (maxWeight != null && maxWeight > 0 ? maxWeight : null),
    durationMs: (seconds.last * 1000).round(),
    grind: grind,
    brewTemp: temps.isEmpty
        ? null
        : temps.reduce((a, b) => a + b) / temps.length,
    readings: [
      for (var i = 0; i < seconds.length; i++)
        (shotId) => ShotReadingsCompanion.insert(
          shotId: shotId,
          timeMs: (seconds[i] * 1000).round(),
          pressure: Value(at(pressure, i)),
          flow: Value(at(flow, i)),
          weight: Value(at(weight, i)),
          gravimetricFlow: Value(at(weightFlow, i)),
          // The boiler/basket sensor sits where the GaggiMate's does, so the
          // temperature curve of the shot detail works the same.
          barUp: Value(at(temp, i)),
        ),
    ],
  );
}

List<double> _numbers(Object? list) => [
  if (list is List)
    for (final v in list) _number(v) ?? 0,
];

double? _number(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s.trim().replaceAll(',', '.')),
  _ => null,
};

String? _text(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

// ISO text or Unix seconds.
DateTime? _time(Object? v) {
  if (v is num) return DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
  if (v is String) {
    final asNumber = num.tryParse(v);
    if (asNumber != null) return _time(asNumber);
    return DateTime.tryParse(v)?.toLocal();
  }
  return null;
}

// None of these machines pulled a shot before 2010 (Decent files are older
// than the others).
bool _plausible(DateTime t) =>
    t.isAfter(DateTime(2010)) &&
    t.isBefore(DateTime.now().add(const Duration(days: 1)));
