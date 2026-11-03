import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/brew_recipe.dart';

// Pour Over profiles stored on the Meticulous (since the 2026-10 software,
// `pour_over_profiles_supported` in /api/v1/machine). They live apart from
// the espresso profiles — `/api/v1/profile/list` never returns them, which
// is why bean'd did not see them before:
//
//   GET /api/v1/pour-over/profile/list        → {"profiles": [...]}
//   GET /api/v1/pour-over/profile/image/{id}  → JPEG (404 without image)
//
// Schema v1 (pour_over_profile_schema/schema.json in meticulous-backend):
// recipe {coffee_dose_g, total_water_g, water_temperature_c,
// target_total_time_s, brewer?, filter?, grind?, ...}, 1–5 stages
// {name, starts_at_s, pour {water_g, duration_s, target_cumulative_water_g,
// flow_rate_g_s, pattern?, height_cm?}, note?}.

/// Brewer keys of brew-recipes (badges, labels) recognised in the free text
/// brewer name of a Meticulous profile.
const _brewerHints = {
  'v60': 'V60',
  'chemex': 'Chemex',
  'aeropress': 'Aeropress',
  'kalita': 'Kalita',
  'orea': 'Orea',
  'origami': 'Origami',
  'april': 'April',
  'stagg': 'StaggX',
};

const _patternLabels = {
  'center': 'Centre pour',
  'spiral_out': 'Spiral out',
  'spiral_in': 'Spiral in',
  'spiral_in_out': 'Spiral in and out',
  'concentric_rings': 'Concentric rings',
  'edge': 'Along the edge',
  'pulse': 'Pulse pour',
};

/// Converts a Meticulous Pour Over profile into the app's recipe model.
/// Throws [BrewRecipeFormatException] when required fields are missing.
BrewRecipe brewRecipeFromMeticulous(Map<String, dynamic> j) {
  if (j['brew_type'] != 'pour_over') {
    throw BrewRecipeFormatException('not a pour over profile');
  }
  final id = j['id'];
  final name = j['name'];
  final recipe = j['recipe'];
  final stages = j['stages'];
  if (id is! String || id.isEmpty) throw BrewRecipeFormatException('id');
  if (name is! String || name.isEmpty) throw BrewRecipeFormatException('name');
  if (recipe is! Map) throw BrewRecipeFormatException('recipe missing');
  if (stages is! List || stages.isEmpty) {
    throw BrewRecipeFormatException('stages missing');
  }
  double number(Object? v, String what) {
    if (v is num && v.isFinite) return v.toDouble();
    throw BrewRecipeFormatException('$what missing');
  }

  final dose = number(recipe['coffee_dose_g'], 'coffee_dose_g');
  final water = number(recipe['total_water_g'], 'total_water_g');
  final temp = recipe['water_temperature_c'];

  final parsed = <({double start, double duration, BrewPhase phase})>[];
  for (final raw in stages) {
    if (raw is! Map) throw BrewRecipeFormatException('stage');
    final pour = raw['pour'];
    if (pour is! Map) throw BrewRecipeFormatException('stage pour');
    final hint = [
      if (_patternLabels[pour['pattern']] case final String label) label,
      if (pour['height_cm'] case final num h when h > 0)
        '${h.toStringAsFixed(h % 1 == 0 ? 0 : 1)} cm high',
    ].join(', ');
    final note = raw['note'] is String ? (raw['note'] as String).trim() : '';
    parsed.add((
      start: number(raw['starts_at_s'], 'starts_at_s'),
      duration: number(pour['duration_s'], 'duration_s'),
      phase: BrewPhase(
        label: raw['name'] is String && (raw['name'] as String).isNotEmpty
            ? raw['name'] as String
            : 'Pour',
        waterG: number(pour['water_g'], 'water_g'),
        note: [
          if (hint.isNotEmpty) hint,
          if (note.isNotEmpty) note,
        ].join('. ').nullIfEmpty,
      ),
    ));
  }
  parsed.sort((a, b) => a.start.compareTo(b.start));

  // The machine gives absolute start times, the app a pause AFTER each pour
  // (wait_seconds): pause = next start − (this start + pouring time).
  final phases = <BrewPhase>[
    for (var i = 0; i < parsed.length; i++)
      BrewPhase(
        label: parsed[i].phase.label,
        waterG: parsed[i].phase.waterG,
        note: parsed[i].phase.note,
        waitSeconds: i + 1 < parsed.length
            ? (parsed[i + 1].start - parsed[i].start - parsed[i].duration)
                  .clamp(0, 86400)
                  .roundToDouble()
            : null,
      ),
  ];

  final brewerName = (recipe['brewer'] is Map)
      ? (recipe['brewer'] as Map)['name']?.toString()
      : null;
  final grind = (recipe['grind'] is Map)
      ? (recipe['grind'] as Map)['description']?.toString()
      : null;
  final filter = (recipe['filter'] is Map)
      ? (recipe['filter'] as Map)['name']?.toString()
      : null;
  final display = j['display'] is Map ? j['display'] as Map : const {};
  final description =
      (display['description'] ?? display['shortDescription']) as String?;

  return BrewRecipe(
    id: id,
    name: name,
    brewer: _brewerKey(brewerName),
    variant: filter,
    doseG: dose,
    waterMl: water,
    waterTempC: temp is num ? temp.toDouble() : null,
    grindSize: grind ?? '',
    description: description?.trim(),
    phases: phases,
    sourceName: (j['author'] as String?) ?? 'Meticulous',
    fromMachine: true,
  );
}

String _brewerKey(String? name) {
  if (name == null || name.trim().isEmpty) return 'Other';
  final lower = name.toLowerCase();
  for (final e in _brewerHints.entries) {
    if (lower.contains(e.key)) return e.value;
  }
  return name.trim();
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Loads the Pour Over profiles from the machine (read-only) and keeps
/// their images in [photoDir] (`meticulous_pourover_<id>.jpg`).
class MeticulousPourOverProfiles {
  MeticulousPourOverProfiles({
    required this.host,
    this.photoDir,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String Function() host;
  final Directory? Function()? photoDir;
  final http.Client _client;

  static String photoName(String id) => 'meticulous_pourover_$id.jpg';

  /// Fetches the list; throws on network/HTTP errors. Profiles the app can't
  /// read are skipped.
  Future<List<BrewRecipe>> fetch() async {
    final response = await _client
        .get(Uri.parse('http://${host()}/api/v1/pour-over/profile/list'))
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw HttpException('Pour Over profiles: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body);
    final list = json is Map ? json['profiles'] : null;
    if (list is! List) return const [];
    final out = <BrewRecipe>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      try {
        out.add(brewRecipeFromMeticulous(Map<String, dynamic>.from(raw)));
      } on BrewRecipeFormatException catch (e) {
        debugPrint('Meticulous pour over profile skipped: ${e.message}');
      }
    }
    return out;
  }

  /// Downloads the profile image if there is none yet; returns the file or
  /// null (no image on the machine, no folder, network error).
  Future<File?> fetchPhoto(String id, {bool refresh = false}) async {
    final dir = photoDir?.call();
    if (dir == null) return null;
    final file = File(p.join(dir.path, photoName(id)));
    if (!refresh && file.existsSync()) return file;
    try {
      final response = await _client
          .get(Uri.parse('http://${host()}/api/v1/pour-over/profile/image/$id'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return file.existsSync() ? file : null;
      }
      await dir.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (_) {
      return file.existsSync() ? file : null;
    }
  }
}
