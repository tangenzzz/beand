import 'dart:math' as math;

import 'profile_draft.dart' show newUuid;

// A Pour Over profile being written: bean'd keeps own profiles in the
// Meticulous' format (pour_over_profile_schema/schema.json in
// meticulous-backend), so one file serves the app and the machine. The
// machine refuses unknown fields, so what only the app knows sits under
// [appKey] and stays out of [toMachineJson].
//
// The form thinks in pour time and the wait after it; the format in absolute
// start times. Writing derives the start times, the flow and the running
// total, which makes the machine's consistency rules hold by construction.

const maxPours = 5;
const maxHeightCm = 15.0;
const minDoseG = 5.0;
const maxDoseG = 40.0;
const minTempC = 70.0;
const maxTempC = 100.0;
const maxTimeS = 600.0;
const maxTotalWaterG = 2000.0;
const maxNameLength = 120;
const maxDescriptionLength = 500;
const maxNoteLength = 300;
const minFlowGps = 0.5;
const maxFlowGps = 20.0;

const pourPatterns = {
  'center': 'Center',
  'spiral_out': 'Spiral out',
  'spiral_in': 'Spiral in',
  'spiral_in_out': 'Spiral in and out',
  'concentric_rings': 'Rings',
  'edge': 'Along the edge',
  'pulse': 'Pulse',
};

/// Temperature during a pour. The format only knows an exact value; "let it
/// fall" is the app's and reaches the machine as no value.
enum PourTemp { hold, fall, exact }

class DraftPour {
  DraftPour({
    required this.key,
    required this.name,
    required this.waterG,
    required this.durationS,
    this.waitS = 0,
    this.tempMode = PourTemp.hold,
    this.tempC,
    this.pattern,
    this.heightCm,
    this.note = '',
    Map<String, dynamic>? rawPour,
  }) : _rawPour = rawPour ?? const {};

  final String key;
  String name;
  double waterG;
  double durationS;

  /// Until the next pour starts. Not used on the last one: after it the
  /// draft's drawdown counts.
  double waitS;
  PourTemp tempMode;
  double? tempC;
  String? pattern;
  double? heightCm;
  String note;

  // What the form doesn't show (direction, flow range) stays as it was.
  final Map<String, dynamic> _rawPour;

  double get flowGps => durationS > 0 ? waterG / durationS : 0;

  /// Flow and pour time are two sides of one thing: the water stays, the
  /// time follows. Kept in thousandths, so the flow reads back as set.
  void setFlow(double gPerS) {
    if (gPerS <= 0) return;
    durationS = math.max(0.001, (waterG / gPerS * 1000).roundToDouble() / 1000);
  }

  DraftPour copyAs(String newKey, String newName) => DraftPour(
    key: newKey,
    name: newName,
    waterG: waterG,
    durationS: durationS,
    waitS: waitS,
    tempMode: tempMode,
    tempC: tempC,
    pattern: pattern,
    heightCm: heightCm,
    note: note,
    rawPour: _rawPour,
  );
}

class PourOverDraft {
  PourOverDraft({
    required this.id,
    required this.pours,
    this.name = '',
    this.author = "bean'd",
    String? authorId,
    this.description = '',
    this.accentColor = '#3F6E8C',
    this.doseG = 15,
    this.tempC = 93,
    this.grind = '',
    this.chainId,
    this.brewerName,
    this.filterName,
    this.drawdownS = 60,
    this.timeMaxS,
    Map<String, dynamic>? base,
  }) : authorId = authorId ?? newUuid(),
       _base = base ?? const {};

  /// A sensible start: bloom and one main pour, 1:16.
  factory PourOverDraft.empty() => PourOverDraft(
    id: newUuid(),
    pours: [
      DraftPour(
        key: 'bloom',
        name: 'Bloom',
        waterG: 45,
        durationS: 10,
        waitS: 35,
      ),
      DraftPour(key: 'pour-2', name: 'Pour 2', waterG: 195, durationS: 45),
    ],
    timeMaxS: 180,
  );

  /// Reads a profile in the format (also one from the machine or a file).
  factory PourOverDraft.fromJson(Map<String, dynamic> j) {
    final recipe = _map(j['recipe']);
    final display = _map(j['display']);
    final app = _map(j[appKey]);
    final fall = {...?(app['temp_fall'] as List?)?.map((e) => '$e')};
    final stages = [
      for (final s in (j['stages'] as List? ?? const []))
        if (s is Map) Map<String, dynamic>.from(s),
    ]..sort((a, b) => _num(a['starts_at_s']).compareTo(_num(b['starts_at_s'])));

    final pours = <DraftPour>[];
    for (var i = 0; i < stages.length; i++) {
      final s = stages[i];
      final pour = _map(s['pour']);
      final start = _num(s['starts_at_s']);
      final duration = _num(pour['duration_s']);
      final next = i + 1 < stages.length
          ? _num(stages[i + 1]['starts_at_s'])
          : null;
      final key = '${s['key'] ?? 'pour-${i + 1}'}';
      final temp = s['temperature_c'];
      pours.add(
        DraftPour(
          key: key,
          name: '${s['name'] ?? 'Pour ${i + 1}'}',
          waterG: _num(pour['water_g']),
          durationS: duration,
          waitS: next == null ? 0 : (next - start - duration).clamp(0, 600),
          tempMode: temp is num
              ? PourTemp.exact
              : fall.contains(key)
              ? PourTemp.fall
              : PourTemp.hold,
          tempC: temp is num ? temp.toDouble() : null,
          pattern: pourPatterns.containsKey(pour['pattern'])
              ? pour['pattern'] as String
              : null,
          heightCm: pour['height_cm'] is num
              ? math.min((pour['height_cm'] as num).toDouble(), maxHeightCm)
              : null,
          note: '${s['note'] ?? ''}',
          rawPour: pour,
        ),
      );
    }
    final lastEnd = stages.isEmpty
        ? 0.0
        : _num(stages.last['starts_at_s']) + pours.last.durationS;
    final target = recipe['target_total_time_s'];
    final max = recipe['target_total_time_max_s'];
    return PourOverDraft(
      id: '${j['id']}',
      pours: pours,
      name: '${j['name'] ?? ''}',
      author: '${j['author'] ?? "bean'd"}',
      authorId: j['author_id'] is String ? j['author_id'] as String : null,
      description: '${display['description'] ?? ''}',
      accentColor: display['accentColor'] is String
          ? display['accentColor'] as String
          : '#3F6E8C',
      doseG: _num(recipe['coffee_dose_g'], 15),
      tempC: _num(recipe['water_temperature_c'], 93),
      grind: '${_map(recipe['grind'])['description'] ?? ''}',
      chainId: app['chain_id'] is String ? app['chain_id'] as String : null,
      brewerName: _map(recipe['brewer'])['name'] as String?,
      filterName: _map(recipe['filter'])['name'] as String?,
      drawdownS: target is num ? (target - lastEnd).clamp(0, 600) : 0,
      timeMaxS: max is num ? max.toDouble() : null,
      base: j,
    );
  }

  /// App-only data in a stored profile; never sent to the machine.
  static const appKey = 'beand';

  final String id;
  final String author;
  final String authorId;
  final Map<String, dynamic> _base;

  String name;
  String description;
  String accentColor;
  double doseG;
  double tempC;
  String grind;
  String? chainId;
  String? brewerName;
  String? filterName;
  List<DraftPour> pours;

  /// After the last pour; together with the pours it makes the lower end of
  /// the time span.
  double drawdownS;

  /// Upper end of the time span, null without one.
  double? timeMaxS;

  double get totalWaterG => pours.fold(0.0, (s, p) => s + p.waterG);
  double get ratio => doseG > 0 ? totalWaterG / doseG : 0;

  /// When each pour starts, in order.
  List<double> get startsS {
    final out = <double>[];
    var t = 0.0;
    for (final p in pours) {
      out.add(t);
      t += p.durationS + p.waitS;
    }
    return out;
  }

  /// End of the last pour — the time span can't start earlier.
  double get lastPourEndS =>
      pours.isEmpty ? 0 : startsS.last + pours.last.durationS;

  double get timeFromS => lastPourEndS + drawdownS;

  /// Moves both ends of the span: the lower one is the drawdown.
  void setTimeSpan(double from, double to) {
    final low = from.clamp(lastPourEndS, maxTimeS);
    drawdownS = low - lastPourEndS;
    timeMaxS = to.clamp(low, maxTimeS);
  }

  /// A new total shared out as the pours stand; the last one takes what
  /// rounding leaves. Too little for a gram per pour: nothing happens.
  void setTotalWater(double total) {
    final old = totalWaterG;
    if (old <= 0 || total < pours.length || total > maxTotalWaterG) return;
    var left = total;
    for (var i = 0; i < pours.length; i++) {
      final remaining = pours.length - i - 1;
      final share = i == pours.length - 1
          ? left
          : (pours[i].waterG * total / old).roundToDouble().clamp(
              1.0,
              left - remaining,
            );
      pours[i].waterG = share;
      left -= share;
    }
  }

  bool get canAddPour => pours.length < maxPours;

  /// Next free name and key.
  (String, String) _nextPour() {
    var n = pours.length + 1;
    while (pours.any((p) => p.key == 'pour-$n')) {
      n++;
    }
    return ('pour-$n', 'Pour ${pours.length + 1}');
  }

  /// A new pour at the end, like the one before it. The wait that was the
  /// drawdown's stays with the last pour.
  void addPour() {
    if (!canAddPour) return;
    final (key, name) = _nextPour();
    final last = pours.isEmpty ? null : pours.last;
    last?.waitS = 30;
    pours = [
      ...pours,
      DraftPour(
        key: key,
        name: name,
        waterG: last?.waterG ?? 50,
        durationS: last?.durationS ?? 15,
      ),
    ];
  }

  void copyPour(int index) {
    if (!canAddPour) return;
    final (key, name) = _nextPour();
    final copy = pours[index].copyAs(key, name);
    pours = [...pours]..insert(index + 1, copy);
  }

  void removePour(int index) {
    if (pours.length <= 1) return;
    pours = [...pours]..removeAt(index);
    pours.last.waitS = 0;
  }

  /// What keeps this from being saved; empty = fine. Text for the user.
  List<String> get problems => [
    if (name.trim().isEmpty) 'Enter a name',
    if (pours.isEmpty) 'Add a pour',
    if (pours.length > maxPours) 'At most $maxPours pours',
    if (totalWaterG > maxTotalWaterG) 'At most 2000 g of water',
    if (timeFromS > maxTimeS || (timeMaxS ?? 0) > maxTimeS)
      'At most 10 minutes in total',
  ];

  /// The profile as stored in the app. [imageDataUri]: the photo for the
  /// machine (a JPEG data URI); without one an image already in the profile
  /// stays unless [dropImage].
  Map<String, dynamic> toJson({String? imageDataUri, bool dropImage = false}) {
    final baseDisplay = _map(_base['display']);
    final baseRecipe = _map(_base['recipe']);
    final starts = startsS;
    var cumulative = 0.0;
    final stages = <Map<String, dynamic>>[];
    for (var i = 0; i < pours.length; i++) {
      final p = pours[i];
      cumulative += p.waterG;
      final flow = _round(p.flowGps);
      final range = p._rawPour['flow_range_g_s'];
      stages.add({
        'key': p.key,
        'name': p.name.trim().isEmpty ? 'Pour ${i + 1}' : p.name.trim(),
        'starts_at_s': starts[i],
        if (p.tempMode == PourTemp.exact && p.tempC != null)
          'temperature_c': p.tempC,
        'pour': {
          'water_g': p.waterG,
          'duration_s': p.durationS,
          'target_cumulative_water_g': _round(cumulative),
          'flow_rate_g_s': flow,
          if (range is List &&
              range.length == 2 &&
              range[0] is num &&
              range[1] is num &&
              (range[0] as num) <= flow &&
              flow <= (range[1] as num))
            'flow_range_g_s': range,
          'pattern': ?p.pattern,
          if (p._rawPour['direction'] != null)
            'direction': p._rawPour['direction'],
          'height_cm': ?p.heightCm,
        },
        if (p.note.trim().isNotEmpty) 'note': p.note.trim(),
      });
    }
    final fall = [
      for (final p in pours)
        if (p.tempMode == PourTemp.fall) p.key,
    ];
    final max = timeMaxS;
    final image = imageDataUri ?? (dropImage ? null : baseDisplay['image']);
    return {
      // Fields of the format this form doesn't show stay.
      ..._base,
      'version': 1,
      'brew_type': 'pour_over',
      'id': id,
      'name': name.trim(),
      'author': author,
      'author_id': authorId,
      'display': {
        ...baseDisplay,
        'accentColor': accentColor,
        if (description.trim().isNotEmpty)
          'description': description.trim()
        else
          'description': '',
        'image': ?image,
      }..removeWhere((k, v) => v == '' || (k == 'image' && image == null)),
      'recipe':
          {
            ...baseRecipe,
            'coffee_dose_g': doseG,
            'total_water_g': _round(totalWaterG),
            'water_temperature_c': tempC,
            'target_total_time_s': timeFromS,
            if (max != null && max >= timeFromS) 'target_total_time_max_s': max,
            if (brewerName != null)
              'brewer': {..._map(baseRecipe['brewer']), 'name': brewerName},
            if (filterName != null)
              'filter': {..._map(baseRecipe['filter']), 'name': filterName},
            if (grind.trim().isNotEmpty)
              'grind': {
                ..._map(baseRecipe['grind']),
                'description': grind.trim(),
              },
          }..removeWhere(
            (k, _) =>
                (k == 'brewer' && brewerName == null) ||
                (k == 'filter' && filterName == null) ||
                (k == 'grind' && grind.trim().isEmpty) ||
                (k == 'target_total_time_max_s' &&
                    (max == null || max < timeFromS)),
          ),
      'stages': stages,
      appKey: {'chain_id': ?chainId, if (fall.isNotEmpty) 'temp_fall': fall},
    };
  }
}

/// A stored profile as the machine takes it: it refuses unknown fields.
Map<String, dynamic> toMachineJson(Map<String, dynamic> stored) =>
    Map<String, dynamic>.of(stored)..remove(PourOverDraft.appKey);

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

double _num(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

double _round(double v) => (v * 100).roundToDouble() / 100;
