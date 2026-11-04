import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../scale/brew_scale.dart';

// Pour Over brews made on the Meticulous' dial (its own Pour Over mode,
// software 2026-10). The dial keeps its steps to itself while brewing; only
// the finished brew reaches the backend. From outside the machine only the
// LATEST one is reachable (the list `/history/pour-over` answers only
// locally, listing the folders fails with 500 — checked 2026-11-04):
//
//   GET /api/v1/history/pour-over/last          → metadata incl. "file"
//   GET /api/v1/history/pour-over/files/<file>  → the whole brew (JSON)
//
// Brew (schemaVersion 4): recipe {profileId, profileName, doseG,
// temperatureC, targetWaterG, pourTargets[]}, measurements {serverBaselineG,
// brewerG, setupG, doseG, waterTemperatureC, waterPouredG, beverageG,
// retainedG, durationMs, status}, pours[{number, startTimeMs, endTimeMs,
// waterG, ...}], samples[{t, w, f, p}] (every ~200 ms), completion.

class DialPour {
  const DialPour(this.number, this.startMs, this.endMs);
  final int number;
  final double startMs;
  final double endMs;
}

class DialSample {
  const DialSample(this.ms, this.grams, this.flow);
  final int ms;
  final double grams;
  final double flow;
}

class DialBrew {
  DialBrew({
    required this.id,
    required this.startedAt,
    required this.profileName,
    required this.raw,
    this.profileId,
    this.doseG,
    this.temperatureC,
    this.waterG,
    this.beverageG,
    this.durationMs,
    this.brewerG,
    this.serverG,
    this.pours = const [],
    this.samples = const [],
  });

  final String id;
  final DateTime startedAt;
  final String? profileId;
  final String profileName;
  final double? doseG;
  final double? temperatureC;
  final double? waterG;
  final double? beverageG;
  final int? durationMs;
  final double? brewerG;
  final double? serverG;
  final List<DialPour> pours;
  final List<DialSample> samples;

  /// The whole brew as the machine sent it (kept locally with the shot).
  final String raw;

  /// History key — never clashes with espresso shot IDs.
  String get externalId => 'meticulous-pourover:$id';

  /// Label of the pour a moment belongs to ("Pour 2"), empty in between.
  String stageAt(int ms) {
    for (final p in pours) {
      if (ms >= p.startMs && ms <= p.endMs) return 'Pour ${p.number}';
    }
    return '';
  }

  static double? _num(Object? v) =>
      v is num && v.isFinite ? v.toDouble() : null;

  factory DialBrew.fromJson(Map<String, dynamic> j, {String? raw}) {
    final id = j['id'];
    final started = DateTime.tryParse('${j['startedAt']}');
    if (id is! String || id.isEmpty || started == null) {
      throw const FormatException('Pour Over brew without id/startedAt');
    }
    final recipe = j['recipe'] is Map ? j['recipe'] as Map : const {};
    final m = j['measurements'] is Map ? j['measurements'] as Map : const {};
    final name = (recipe['profileName'] ?? j['name'] ?? 'Free Pour')
        .toString();
    return DialBrew(
      id: id,
      startedAt: started.toLocal(),
      profileId: recipe['profileId'] as String?,
      profileName: name.isEmpty ? 'Free Pour' : name,
      doseG: _num(m['doseG']) ?? _num(recipe['doseG']),
      temperatureC:
          _num(m['waterTemperatureC']) ?? _num(recipe['temperatureC']),
      waterG: _num(m['waterPouredG']),
      beverageG: _num(m['beverageG']),
      durationMs: _num(m['durationMs'])?.round(),
      brewerG: _num(m['brewerG']),
      serverG: _num(m['serverBaselineG']),
      pours: [
        for (final p in (j['pours'] as List? ?? const []))
          if (p is Map && _num(p['startTimeMs']) != null)
            DialPour(
              (p['number'] as num?)?.toInt() ?? 0,
              _num(p['startTimeMs'])!,
              _num(p['endTimeMs']) ?? _num(p['startTimeMs'])!,
            ),
      ],
      samples: [
        for (final s in (j['samples'] as List? ?? const []))
          if (s is Map && _num(s['t']) != null && _num(s['w']) != null)
            DialSample(
              _num(s['t'])!.round(),
              _num(s['w'])!,
              _num(s['f']) ?? 0,
            ),
      ],
      raw: raw ?? jsonEncode(j),
    );
  }
}

/// Fetches the latest dial brew (read-only).
class MeticulousDialBrews {
  MeticulousDialBrews({required this.host, http.Client? client})
    : _client = client ?? http.Client();

  final String Function() host;
  final http.Client _client;

  /// Null when the machine has no Pour Over brew yet.
  Future<DialBrew?> fetchLast() async {
    final base = 'http://${host()}/api/v1/history/pour-over';
    final meta = await _client
        .get(Uri.parse('$base/last'))
        .timeout(const Duration(seconds: 6));
    if (meta.statusCode == 404) return null;
    if (meta.statusCode != 200) {
      throw HttpException('Pour Over last: HTTP ${meta.statusCode}');
    }
    final file = (jsonDecode(meta.body) as Map)['file'];
    if (file is! String || file.isEmpty) return null;
    final body = await _client
        .get(Uri.parse('$base/files/$file'))
        .timeout(const Duration(seconds: 10));
    if (body.statusCode != 200) {
      throw HttpException('Pour Over brew: HTTP ${body.statusCode}');
    }
    return DialBrew.fromJson(
      Map<String, dynamic>.from(jsonDecode(body.body) as Map),
      raw: body.body,
    );
  }
}

/// Watches the Meticulous' scale while the dial runs a brew, to show it
/// live in the app: when did the water start, when came the brewer off.
/// The dial itself reports neither (only its taring is visible).
///
/// Start: after a dial tare the weight rises steadily by [startGrams] —
/// more than any dose of coffee (which also comes after a tare, but is
/// followed by the next one). A tick that jumps more than [maxTickRise]
/// (setting something down, lifting) starts the count anew from there.
/// The start is dated back to where the rise began.
///
/// End: like the dial, the weight falls by at least [liftDrop] below the
/// most poured and stays there for [liftHold].
class DialBrewDetector {
  static const maxTickRise = 4.0;
  static const startGrams = 40.0;
  static const liftDrop = 28.0;
  static const liftHold = Duration(seconds: 3);

  bool _armed = false;
  final List<ScaleReading> _rise = [];
  double? _last;
  double _base = 0;

  bool _running = false;
  double _peak = 0;
  DateTime? _dropSince;

  bool get running => _running;

  void reset() {
    _armed = false;
    _rise.clear();
    _last = null;
    _base = 0;
    _running = false;
    _peak = 0;
    _dropSince = null;
  }

  /// The dial tared (a setup step done): the next rise may be water.
  void deviceTared() {
    if (_running) return;
    _armed = true;
    _rise.clear();
    _last = null;
    _base = 0;
  }

  /// Returns the readings of the rise (oldest first) once it is recognised
  /// as water — the brew started with the first of them.
  List<ScaleReading>? feedIdle(ScaleReading r) {
    if (_running || !_armed) return null;
    final last = _last;
    _last = r.grams;
    if (last != null && (r.grams - last).abs() > maxTickRise) {
      // Something set down or taken off — not water. Count from here.
      _base = r.grams;
      _rise.clear();
      return null;
    }
    if (r.grams <= _base + 0.5) {
      _base = math.min(_base, r.grams);
      _rise.clear();
      return null;
    }
    _rise.add(r);
    if (r.grams - _base < startGrams) return null;
    _running = true;
    _peak = r.grams;
    final out = List.of(_rise);
    _rise.clear();
    return out;
  }

  /// While running: the moment the brewer came off once confirmed, else
  /// null.
  DateTime? feedRunning(ScaleReading r) {
    if (!_running) return null;
    final g = r.grams;
    if (_dropSince == null) _peak = math.max(_peak, g);
    if (g > _peak - liftDrop) {
      _dropSince = null;
      return null;
    }
    final since = _dropSince ??= r.at;
    if (r.at.difference(since) < liftHold) return null;
    _running = false;
    _armed = false;
    return since;
  }
}
